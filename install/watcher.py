#!/usr/bin/env python3
"""Watch for new Voice Memos and hand each one to Hermes for processing."""

from __future__ import annotations

import logging
import os
import re
import shutil
import subprocess
import sys
import time
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

log = logging.getLogger("watcher")

HERMES_SKILL = "apple-voice-assistant"
HERMES_TOOLSETS = "file,terminal,messaging,memory,todo"
MAX_LOG_BYTES = 10 * 1024 * 1024
STABLE_WAIT = 2
MAX_ATTEMPTS = 3
FILENAME_RE = re.compile(r"^(\d{4})(\d{2})(\d{2}) (\d{2})(\d{2})(\d{2})(-(.+))?$")
STANDARD_FILENAME_RE = re.compile(r"^\d{8} \d{6}(-[A-Z0-9]+)?\.(m4a|qta)$")
RECORDINGS_CANDIDATES = [
    "Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings",
    "Library/Application Support/com.apple.voicememos/Recordings",
]


@dataclass(frozen=True)
class Config:
    home: Path
    hermes_home: Path
    state_dir: Path
    python_bin: Path
    hermes_timeout: int
    lock_stale_seconds: int
    audit_target: str
    self_check: bool

    @classmethod
    def from_env(cls) -> Config:
        home_str = os.environ.get("HOME")
        if not home_str:
            print("ERROR: HOME must be set", file=sys.stderr)
            sys.exit(1)
        home = Path(home_str)
        hermes_home = Path(os.environ.get("HERMES_HOME", str(home / ".hermes")))
        hermes_timeout = int(os.environ.get("APPLE_VOICE_ASSISTANT_HERMES_TIMEOUT", "900"))
        python_bin = Path(os.environ.get(
            "APPLE_VOICE_ASSISTANT_PYTHON",
            str(hermes_home / "hermes-agent/venv/bin/python"),
        ))
        if not python_bin.is_file():
            fallback = shutil.which("python3")
            if fallback:
                python_bin = Path(fallback)
        return cls(
            home=home,
            hermes_home=hermes_home,
            state_dir=home / ".local/state/apple-voice-assistant",
            python_bin=python_bin,
            hermes_timeout=hermes_timeout,
            lock_stale_seconds=hermes_timeout * 4 + 120,
            audit_target=os.environ.get("APPLE_VOICE_ASSISTANT_AUDIT_TARGET", "not set"),
            self_check=os.environ.get("APPLE_VOICE_ASSISTANT_SELF_CHECK", "0") == "1",
        )

    @property
    def seen_file(self) -> Path:
        return self.state_dir / "seen.txt"

    @property
    def log_file(self) -> Path:
        return self.state_dir / "watcher.log"

    @property
    def lock_dir(self) -> Path:
        return self.state_dir / "watcher.lock"

    @property
    def processed_dir(self) -> Path:
        return self.state_dir / "processed"

    @property
    def tmp_audio_dir(self) -> Path:
        return self.state_dir / "tmp-audio"

    @property
    def env_file(self) -> Path:
        return self.state_dir / "env"


def source_env_file(path: Path) -> None:
    """Load KEY=VALUE lines from an env file into os.environ."""
    if not path.is_file():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            key, _, value = line.partition("=")
            os.environ[key.strip()] = value.strip()


def setup_logging(log_file: Path) -> None:
    handler = logging.FileHandler(log_file)
    fmt = logging.Formatter("%(asctime)s %(message)s", datefmt="%Y-%m-%dT%H:%M:%SZ")
    fmt.converter = time.gmtime
    handler.setFormatter(fmt)
    log.addHandler(handler)
    log.setLevel(logging.INFO)


def rotate_log(log_file: Path) -> None:
    if not log_file.exists():
        return
    size = log_file.stat().st_size
    if size > MAX_LOG_BYTES:
        log_file.write_bytes(log_file.read_bytes()[-(MAX_LOG_BYTES // 2):])
        log.info("rotated log (was %d bytes)", size)


@contextmanager
def file_lock(lock_dir: Path, stale_seconds: int):
    """mkdir-based lock with stale detection. Yields True if acquired."""
    try:
        lock_dir.mkdir()
    except FileExistsError:
        if lock_dir.is_dir():
            age = time.time() - lock_dir.stat().st_mtime
            if age > stale_seconds:
                log.info("removing stale lock (age: %ds)", int(age))
                shutil.rmtree(lock_dir, ignore_errors=True)
                try:
                    lock_dir.mkdir()
                except FileExistsError:
                    log.info("still locked after stale removal")
                    yield False
                    return
            else:
                log.info("another instance running (lock age: %ds), exiting", int(age))
                yield False
                return
        else:
            try:
                lock_dir.mkdir()
            except FileExistsError:
                log.info("lock race, exiting")
                yield False
                return
    try:
        yield True
    finally:
        shutil.rmtree(lock_dir, ignore_errors=True)


def find_recordings_dir(home: Path) -> Path | None:
    for rel in RECORDINGS_CANDIDATES:
        candidate = home / rel
        if candidate.is_dir():
            return candidate
    return None


def load_seen(seen_file: Path) -> set[str]:
    if not seen_file.exists():
        return set()
    return set(seen_file.read_text().splitlines())


def discover_new_memos(
    recordings_dir: Path, seen: set[str], tmp_audio_dir: Path
) -> list[tuple[Path, Path, int]]:
    """Return (staged_copy, source_path, size) for each unseen memo."""
    tmp_audio_dir.mkdir(parents=True, exist_ok=True)
    results = []
    for src in sorted(recordings_dir.iterdir(), key=lambda p: p.stat().st_mtime):
        if not src.is_file() or src.suffix.lower() not in {".m4a", ".qta"}:
            continue
        if src.name in seen:
            continue
        st1 = src.stat()
        if st1.st_size <= 0:
            continue
        time.sleep(STABLE_WAIT)
        st2 = src.stat()
        if st1.st_size != st2.st_size:
            log.info("SYNCING %s (%d->%d)", src.name, st1.st_size, st2.st_size)
            continue
        dest = tmp_audio_dir / src.name
        shutil.copy2(src, dest)
        results.append((dest, src, st2.st_size))
    return results


def normalized_stem(name: str) -> str:
    m = FILENAME_RE.match(name)
    if m:
        suffix = f"-{m.group(8).lower()}" if m.group(8) else ""
        return f"{m.group(1)}-{m.group(2)}-{m.group(3)}-{m.group(4)}-{m.group(5)}-{m.group(6)}{suffix}"
    return name.lower().replace(" ", "-")


def validate_audio(path: Path) -> bool:
    afinfo = shutil.which("afinfo")
    if not afinfo:
        return True
    return subprocess.run([afinfo, str(path)], capture_output=True).returncode == 0


def convert_qta_to_m4a(src: Path, dest: Path) -> bool:
    return subprocess.run(
        ["afconvert", "-f", "m4af", "-d", "aac", str(src), str(dest)],
        capture_output=True,
    ).returncode == 0


def build_prompt(handoff_path: Path, cfg: Config) -> str:
    return (
        f"new voice memo at `{handoff_path}`\n\n"
        f"Process it with apple-voice-assistant. "
        f"At the audit step, you MUST send the audit summary to the Matrix room "
        f"configured in APPLE_VOICE_ASSISTANT_AUDIT_TARGET (`{cfg.audit_target}`). "
        f"If the messaging tool is not available or the send fails, you MUST append "
        f"a follow-up item to `{cfg.state_dir}/TODO.md` (see Step 6 in SKILL.md for "
        f"the exact format). Do NOT silently skip the audit — either deliver it or "
        f"record the failure."
    )


def find_timeout_bin() -> str:
    for name in ("timeout", "gtimeout"):
        path = shutil.which(name)
        if path:
            return path
    log.error("timeout(1) not found — install coreutils")
    sys.exit(1)


def handoff_to_hermes(cfg: Config, timeout_bin: str, handoff_path: Path) -> bool:
    cmd = [
        timeout_bin, str(cfg.hermes_timeout),
        str(cfg.python_bin), str(cfg.hermes_home / "hermes-agent/hermes"), "chat",
        "--source", HERMES_SKILL,
        "--skills", HERMES_SKILL,
        "--toolsets", HERMES_TOOLSETS,
        "--pass-session-id", "--yolo", "--quiet",
        "--query", build_prompt(handoff_path, cfg),
    ]
    for attempt in range(1, MAX_ATTEMPTS + 1):
        with open(cfg.log_file, "a") as log_fd:
            rc = subprocess.run(cmd, stdout=log_fd, stderr=log_fd).returncode
        if rc == 0:
            return True
        log.info("WARN: Hermes handoff failed for %s (attempt %d/%d)",
                 handoff_path.name, attempt, MAX_ATTEMPTS)
        if attempt < MAX_ATTEMPTS:
            time.sleep(5)
    return False


def main() -> None:
    cfg = Config.from_env()

    # Source API keys written by the nix activation script
    source_env_file(cfg.env_file)

    for d in (cfg.state_dir, cfg.processed_dir, cfg.tmp_audio_dir):
        d.mkdir(parents=True, exist_ok=True)
    cfg.seen_file.touch()
    cfg.log_file.touch()

    setup_logging(cfg.log_file)
    rotate_log(cfg.log_file)

    if not cfg.python_bin.is_file():
        log.error("Hermes Python not found at %s", cfg.python_bin)
        sys.exit(1)

    recordings_dir = find_recordings_dir(cfg.home)
    if not recordings_dir:
        log.error("no Voice Memos recordings dir found")
        sys.exit(1)

    if cfg.self_check:
        try:
            next(recordings_dir.iterdir())
        except (StopIteration, PermissionError):
            pass
        except OSError:
            log.error("watcher self-check failed to enumerate recordings dir")
            sys.exit(1)
        log.info("watcher self-check ok")
        return

    timeout_bin = find_timeout_bin()

    with file_lock(cfg.lock_dir, cfg.lock_stale_seconds) as acquired:
        if not acquired:
            return

        seen = load_seen(cfg.seen_file)
        for staged, source, _size in discover_new_memos(recordings_dir, seen, cfg.tmp_audio_dir):
            basename = source.name
            ext = source.suffix.lstrip(".").lower()

            if not validate_audio(staged):
                log.warning("afinfo failed, file may be corrupt: %s", basename)
                continue
            if not STANDARD_FILENAME_RE.match(basename):
                log.warning("non-standard filename, reduced confidence: %s", basename)

            normalized = normalized_stem(source.stem)
            handoff_path = staged
            if ext == "qta":
                converted = cfg.tmp_audio_dir / f"{normalized}.m4a"
                if convert_qta_to_m4a(staged, converted):
                    handoff_path = converted
                    log.info("converted qta to m4a: %s -> %s", basename, converted.name)
                else:
                    log.error("failed to convert qta to m4a: %s", basename)
                    continue

            log.info("new memo: %s", basename)
            if handoff_to_hermes(cfg, timeout_bin, handoff_path):
                with open(cfg.seen_file, "a") as f:
                    f.write(basename + "\n")
            else:
                log.error("Hermes invocation failed after retries for %s", basename)

    log.info("watcher run complete")


if __name__ == "__main__":
    main()
