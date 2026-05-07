#!/usr/bin/env python3
"""Launchd watcher for Apple Voice Assistant.

Find stable new Voice Memos files, copy them out of the protected iCloud
container, convert .qta files when needed, and hand each staged file to Hermes.
State lives outside the skill source so this script can run from a read-only Nix
store path.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

AUDIO_SUFFIXES = {".m4a", ".qta"}
MAX_LOG_BYTES = 10 * 1024 * 1024
HERMES_SKILL = "apple-voice-assistant"
HERMES_TOOLSETS = "file,terminal,messaging,memory,todo"


def env_path(name: str, default: Path | str) -> Path:
    return Path(os.environ.get(name, str(default))).expanduser()


HOME = env_path("HOME", Path.home())
HERMES_HOME = env_path("HERMES_HOME", HOME / ".hermes")
STATE_DIR = env_path("APPLE_VOICE_ASSISTANT_STATE_DIR", HOME / ".local/state/apple-voice-assistant")
SEEN_FILE = STATE_DIR / "seen.txt"
LOG_FILE = STATE_DIR / "watcher.log"
LOCK_DIR = STATE_DIR / "watcher.lock"
PROCESSED_DIR = STATE_DIR / "processed"
TMP_AUDIO_DIR = STATE_DIR / "tmp-audio"
PYTHON_BIN = env_path("APPLE_VOICE_ASSISTANT_PYTHON", HERMES_HOME / "hermes-agent/venv/bin/python")
HERMES_TIMEOUT = int(os.environ.get("APPLE_VOICE_ASSISTANT_HERMES_TIMEOUT", "900"))
SELF_CHECK = os.environ.get("APPLE_VOICE_ASSISTANT_SELF_CHECK", "0") == "1"
AUDIT_TARGET = os.environ.get("APPLE_VOICE_ASSISTANT_AUDIT_TARGET", "")


def log(message: str) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with LOG_FILE.open("a", encoding="utf-8") as fh:
        fh.write(f"{stamp} {message}\n")


def rotate_log() -> None:
    if LOG_FILE.exists() and LOG_FILE.stat().st_size > MAX_LOG_BYTES:
        LOG_FILE.write_bytes(LOG_FILE.read_bytes()[-MAX_LOG_BYTES // 2 :])
        log(f"rotated log (was over {MAX_LOG_BYTES} bytes)")


@contextmanager
def watcher_lock():
    stale_after = HERMES_TIMEOUT * 4 + 120
    try:
        LOCK_DIR.mkdir()
    except FileExistsError:
        age = time.time() - LOCK_DIR.stat().st_mtime
        if age <= stale_after:
            log(f"another instance running (lock age: {int(age)}s), exiting")
            raise SystemExit(0)
        log(f"removing stale lock (age: {int(age)}s)")
        shutil.rmtree(LOCK_DIR, ignore_errors=True)
        LOCK_DIR.mkdir()
    try:
        yield
    finally:
        shutil.rmtree(LOCK_DIR, ignore_errors=True)


def recordings_dir() -> Path:
    configured = os.environ.get("APPLE_VOICE_ASSISTANT_RECORDINGS_DIR")
    candidates = [Path(configured)] if configured else []
    candidates += [
        HOME / "Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings",
        HOME / "Library/Application Support/com.apple.voicememos/Recordings",
    ]
    for candidate in candidates:
        if candidate and candidate.is_dir():
            return candidate
    raise RuntimeError("no Voice Memos recordings dir found")


def normalized_stem(name: str) -> str:
    match = re.match(r"^(\d{4})(\d{2})(\d{2}) (\d{2})(\d{2})(\d{2})(-(.+))?$", name)
    if match:
        suffix = f"-{match.group(8).lower()}" if match.group(8) else ""
        return "-".join(match.groups()[:6]) + suffix
    return name.lower().replace(" ", "-")


def seen_names() -> set[str]:
    if not SEEN_FILE.exists():
        return set()
    return {line.strip() for line in SEEN_FILE.read_text(encoding="utf-8").splitlines() if line.strip()}


def is_stable(path: Path) -> bool:
    first = path.stat().st_size
    if first <= 0:
        return False
    time.sleep(2)
    second = path.stat().st_size
    if first != second:
        log(f"SYNCING {path.name} {first}->{second}")
        return False
    return True


def discover(recordings: Path) -> list[tuple[Path, Path]]:
    seen = seen_names()
    staged: list[tuple[Path, Path]] = []
    for source in sorted(recordings.iterdir(), key=lambda p: p.stat().st_mtime):
        if not source.is_file() or source.suffix.lower() not in AUDIO_SUFFIXES or source.name in seen:
            continue
        if not is_stable(source):
            continue
        copied = TMP_AUDIO_DIR / source.name
        shutil.copy2(source, copied)
        staged.append((copied, source))
    return staged


def command_exists(name: str) -> bool:
    return shutil.which(name) is not None


def afinfo_ok(path: Path) -> bool:
    if not command_exists("afinfo"):
        return True
    return subprocess.run(["afinfo", str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def convert_qta(path: Path, normalized_name: str) -> Path | None:
    if path.suffix.lower() != ".qta":
        return path
    output = TMP_AUDIO_DIR / f"{normalized_name}.m4a"
    result = subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", str(path), str(output)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if result.returncode == 0:
        log(f"converted qta to m4a: {path.name} -> {output.name}")
        return output
    log(f"ERROR: failed to convert qta to m4a: {path.name}")
    return None


def pick_provider() -> tuple[str, str]:
    provider = os.environ.get("APPLE_VOICE_ASSISTANT_PROVIDER", "")
    model = os.environ.get("APPLE_VOICE_ASSISTANT_MODEL", "")
    if provider or model:
        return provider, model
    auth_file = HERMES_HOME / "auth.json"
    if not auth_file.exists():
        return "llama-local", "qwen3.6-35b-a3b"
    try:
        auth = json.loads(auth_file.read_text(encoding="utf-8"))
    except Exception:
        return "llama-local", "qwen3.6-35b-a3b"
    providers = auth.get("providers", {})
    pool = auth.get("credential_pool", {})
    if providers.get("openai-codex") or pool.get("openai-codex"):
        return "openai-codex", "gpt-5.5"
    if pool.get("openrouter"):
        return "openrouter", "google/gemini-2.5-flash-preview:free"
    return "llama-local", "qwen3.6-35b-a3b"


def prompt_for(path: Path) -> str:
    prompt = f"new voice memo at `{path}`\n\nProcess it with apple-voice-assistant."
    if AUDIT_TARGET:
        return prompt + f" At the audit step, send the audit summary using explicit target `{AUDIT_TARGET}` if the messaging tool is available; otherwise print the audit summary to stdout."
    return prompt + " At the audit step, send the audit summary through the configured messaging channel if available; otherwise print the audit summary to stdout."


def hermes_cmd(path: Path) -> list[str]:
    provider, model = pick_provider()
    cmd = [
        str(PYTHON_BIN),
        str(HERMES_HOME / "hermes-agent/hermes"),
        "chat",
        "--source", "apple-voice-assistant",
        "--skills", HERMES_SKILL,
        "--toolsets", HERMES_TOOLSETS,
        "--pass-session-id",
        "--quiet",
    ]
    if provider:
        cmd += ["--provider", provider]
    if model:
        cmd += ["--model", model]
    cmd += ["--query", prompt_for(path)]
    log(f"using Hermes provider={provider or 'default'} model={model or 'default'} for {path.name}")
    return cmd


def handoff(path: Path) -> bool:
    for attempt in range(1, 4):
        try:
            with LOG_FILE.open("a", encoding="utf-8") as log_fh:
                subprocess.run(hermes_cmd(path), stdout=log_fh, stderr=subprocess.STDOUT, timeout=HERMES_TIMEOUT, check=True)
            return True
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            log(f"WARN: Hermes handoff failed for {path.name} (attempt {attempt}/3): {exc}")
            time.sleep(5)
    return False


def process(copied: Path, source: Path) -> None:
    basename = source.name
    if not afinfo_ok(copied):
        log(f"WARN: afinfo failed, file may be corrupt: {basename}")
        return
    if not re.match(r"^[0-9]{8} [0-9]{6}(-[A-Z0-9]+)?\.(m4a|qta)$", basename):
        log(f"WARN: non-standard filename, processing with reduced confidence: {basename}")
    normalized = normalized_stem(source.stem)
    handoff_path = convert_qta(copied, normalized)
    if handoff_path is None:
        return
    log(f"new memo: {basename}")
    if handoff(handoff_path):
        with SEEN_FILE.open("a", encoding="utf-8") as fh:
            fh.write(basename + "\n")
    else:
        log(f"ERROR: Hermes invocation failed after retries for {basename}")


def self_check(recordings: Path) -> int:
    if not PYTHON_BIN.exists():
        log(f"ERROR: Python not found at {PYTHON_BIN}")
        return 1
    next(recordings.iterdir(), None)
    log("watcher self-check ok")
    return 0


def main() -> int:
    for directory in (STATE_DIR, PROCESSED_DIR, TMP_AUDIO_DIR):
        directory.mkdir(parents=True, exist_ok=True)
    SEEN_FILE.touch(exist_ok=True)
    LOG_FILE.touch(exist_ok=True)
    rotate_log()
    with watcher_lock():
        recordings = recordings_dir()
        if SELF_CHECK:
            return self_check(recordings)
        if not PYTHON_BIN.exists():
            log(f"ERROR: Python not found at {PYTHON_BIN}")
            return 1
        for copied, source in discover(recordings):
            process(copied, source)
        log("watcher run complete")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        log(f"ERROR: {exc}")
        raise
