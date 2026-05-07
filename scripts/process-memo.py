#!/usr/bin/env python3
"""Deterministic voice memo processor.

Triggered by launchd when new files appear in the Voice Memos directory.
Handles: discovery → transcription → dedup → archive → webhook to Hermes.
Transcription uses a local Whisper API by default (no cloud calls required),
with an optional OpenAI fallback if configured.
"""

import hashlib
import hmac
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path

# ── Config ──────────────────────────────────────────────────────────────
HOME = Path.home()
STATE_DIR = HOME / ".local/state/apple-voice-assistant"
SEEN_FILE = STATE_DIR / "seen.txt"
LOG_FILE = STATE_DIR / "watcher.log"
LOCK_DIR = STATE_DIR / "watcher.lock"
PROCESSED_DIR = STATE_DIR / "processed"
TMP_AUDIO_DIR = STATE_DIR / "tmp-audio"
ARCHIVE_BASE = STATE_DIR / "data"

# Load env file (webhook secret, API keys) written by nix activation or setup scripts.
_env_file = STATE_DIR / "env"
if _env_file.is_file():
    for line in _env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            os.environ.setdefault(k, v)

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
WHISPER_API_BASE = os.environ.get("APPLE_VOICE_ASSISTANT_WHISPER_API_BASE", "http://127.0.0.1:9099")
WEBHOOK_URL = os.environ.get("APPLE_VOICE_ASSISTANT_WEBHOOK_URL", "http://127.0.0.1:8644/webhooks/voice-memo")
WEBHOOK_SECRET = os.environ.get("APPLE_VOICE_ASSISTANT_WEBHOOK_SECRET", "")

RECORDINGS_CANDIDATES = [
    HOME / "Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings",
    HOME / "Library/Application Support/com.apple.voicememos/Recordings",
]

MAX_LOG_BYTES = 10 * 1024 * 1024
LOCK_STALE_SECONDS = 3600  # 1 hour — generous, script is fast now
STABILITY_WAIT = 2  # seconds between size checks

# ── Logging ─────────────────────────────────────────────────────────────
def log(msg: str):
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    line = f"{ts} {msg}\n"
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line)
    except OSError:
        print(line, end="", file=sys.stderr)


# ── Lock ────────────────────────────────────────────────────────────────
def acquire_lock() -> bool:
    try:
        LOCK_DIR.mkdir()
        return True
    except FileExistsError:
        if LOCK_DIR.is_dir():
            age = time.time() - LOCK_DIR.stat().st_mtime
            if age > LOCK_STALE_SECONDS:
                log(f"removing stale lock (age: {int(age)}s)")
                shutil.rmtree(LOCK_DIR, ignore_errors=True)
                try:
                    LOCK_DIR.mkdir()
                    return True
                except FileExistsError:
                    pass
            log(f"another instance running (lock age: {int(age)}s), exiting")
        return False


def release_lock():
    shutil.rmtree(LOCK_DIR, ignore_errors=True)


# ── Log rotation ────────────────────────────────────────────────────────
def rotate_log():
    if LOG_FILE.exists() and LOG_FILE.stat().st_size > MAX_LOG_BYTES:
        data = LOG_FILE.read_bytes()
        LOG_FILE.write_bytes(data[-(MAX_LOG_BYTES // 2):])
        log("rotated log")


# ── Discovery ───────────────────────────────────────────────────────────
def find_recordings_dir() -> Path | None:
    for candidate in RECORDINGS_CANDIDATES:
        if candidate.is_dir():
            return candidate
    return None


def discover_new_memos(recordings_dir: Path) -> list[dict]:
    """Find unseen, stable audio files. Returns list of {source, tmp_copy, size}."""
    seen = set()
    if SEEN_FILE.exists():
        seen = set(SEEN_FILE.read_text().splitlines())

    TMP_AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    new = []

    for src in sorted(recordings_dir.iterdir(), key=lambda p: p.stat().st_mtime):
        if not src.is_file():
            continue
        if src.suffix.lower() not in {".m4a", ".qta"}:
            continue
        if src.name in seen:
            continue

        st1 = src.stat()
        if st1.st_size <= 0:
            continue

        time.sleep(STABILITY_WAIT)
        st2 = src.stat()
        if st1.st_size != st2.st_size:
            log(f"SYNCING {src.name} ({st1.st_size}->{st2.st_size}), skipping")
            continue

        dest = TMP_AUDIO_DIR / src.name
        shutil.copy2(src, dest)
        new.append({"source": src, "tmp_copy": dest, "size": st2.st_size})

    return new


# ── Transcription ───────────────────────────────────────────────────────
def _multipart_audio(audio_path: Path, model: str) -> tuple[bytes, str]:
    """Build multipart form body for an audio transcription request."""
    boundary = f"----WatcherBoundary{int(time.time())}"
    parts = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{audio_path.name}"\r\n'
        f"Content-Type: audio/mp4\r\n\r\n"
    ).encode()
    parts += audio_path.read_bytes()
    parts += (
        f"\r\n--{boundary}\r\n"
        f'Content-Disposition: form-data; name="model"\r\n\r\n'
        f"{model}\r\n"
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="language"\r\n\r\n'
        f"en\r\n"
        f"--{boundary}--\r\n"
    ).encode()
    return parts, boundary


def _transcribe_local_whisper(audio_path: Path) -> str | None:
    """Try the local Whisper API. Returns transcript text or None."""
    try:
        urllib.request.urlopen(f"{WHISPER_API_BASE}/health", timeout=5).close()
    except Exception:
        return None

    try:
        body, boundary = _multipart_audio(audio_path, "whisper-1")
        req = urllib.request.Request(
            f"{WHISPER_API_BASE}/v1/audio/transcriptions",
            data=body,
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=180) as resp:
            result = json.loads(resp.read())
            text = result.get("text", "").strip()
            if text:
                log(f"transcribed {audio_path.name} via local Whisper API at {WHISPER_API_BASE}")
                return text
    except Exception as e:
        log(f"local Whisper API failed for {audio_path.name}: {e}")
    return None


def _transcribe_openai(audio_path: Path) -> str | None:
    """Fallback: OpenAI cloud transcription. Returns transcript text or None."""
    if not OPENAI_API_KEY:
        return None
    try:
        body, boundary = _multipart_audio(audio_path, "gpt-4o-transcribe")
        req = urllib.request.Request(
            "https://api.openai.com/v1/audio/transcriptions",
            data=body,
            headers={
                "Content-Type": f"multipart/form-data; boundary={boundary}",
                "Authorization": f"Bearer {OPENAI_API_KEY}",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=180) as resp:
            result = json.loads(resp.read())
            text = result.get("text", "").strip()
            if text:
                log(f"transcribed {audio_path.name} via OpenAI gpt-4o-transcribe")
                return text
    except Exception as e:
        log(f"OpenAI transcription failed for {audio_path.name}: {e}")
    return None


def transcribe(audio_path: Path) -> str | None:
    """Transcribe audio. Priority: synthetic → local Whisper API → OpenAI cloud."""
    # Check for synthetic transcript first
    synthetic = Path(str(audio_path) + ".transcript.txt")
    if synthetic.exists():
        text = synthetic.read_text().strip()
        if text:
            log(f"using synthetic transcript for {audio_path.name}")
            return text

    # Try local Whisper API first (no cloud dependency)
    text = _transcribe_local_whisper(audio_path)
    if text:
        return text

    # Fall back to OpenAI cloud transcription
    text = _transcribe_openai(audio_path)
    if text:
        return text

    log(f"all transcription methods failed for {audio_path.name}")
    return None


# ── QTA conversion ──────────────────────────────────────────────────────
def convert_qta(qta_path: Path) -> Path | None:
    """Convert .qta to .m4a via afconvert."""
    m4a_path = qta_path.with_suffix(".m4a")
    try:
        subprocess.run(
            ["afconvert", "-f", "m4af", "-d", "aac", str(qta_path), str(m4a_path)],
            capture_output=True, check=True, timeout=60,
        )
        log(f"converted {qta_path.name} -> {m4a_path.name}")
        return m4a_path
    except Exception as e:
        log(f"ERROR: qta conversion failed for {qta_path.name}: {e}")
        return None


# ── Dedup ───────────────────────────────────────────────────────────────
def is_duplicate(memo_id: str, source: Path) -> bool:
    record = PROCESSED_DIR / f"{memo_id}.json"
    if not record.exists():
        return False
    try:
        data = json.loads(record.read_text())
        st = source.stat()
        return (
            data.get("source_mtime") == int(st.st_mtime)
            and data.get("source_size_bytes") == st.st_size
        )
    except Exception:
        return False


# ── Slug generation ─────────────────────────────────────────────────────
def make_slug(transcript: str) -> str:
    """Generate a 2-6 word lowercase hyphenated slug from the transcript."""
    words = re.sub(r"[^a-zA-Z0-9\s]", "", transcript).lower().split()
    if not words:
        return "untitled"
    slug = "-".join(words[:5])
    if len(slug) > 50:
        slug = slug[:50].rsplit("-", 1)[0]
    return slug or "untitled"


def parse_recorded_at(memo_id: str, fallback_mtime: float) -> datetime:
    """Parse recorded_at from Voice Memos filename like '20260419 083045'."""
    m = re.match(r"(\d{4})(\d{2})(\d{2})\s+(\d{2})(\d{2})(\d{2})", memo_id)
    if m:
        return datetime(
            int(m.group(1)), int(m.group(2)), int(m.group(3)),
            int(m.group(4)), int(m.group(5)), int(m.group(6)),
            tzinfo=timezone.utc,
        )
    return datetime.fromtimestamp(fallback_mtime, tz=timezone.utc)


# ── Archive ─────────────────────────────────────────────────────────────
def archive(
    audio_path: Path,
    transcript: str,
    memo_id: str,
    source_path: Path,
    source_mtime: int,
    source_size_bytes: int,
) -> Path:
    """Archive audio + transcript to data/YYYY/MM/DD/HH-MM-SS-<slug>."""
    recorded_at = parse_recorded_at(memo_id, source_mtime)
    now = datetime.now(timezone.utc)
    date_dir = ARCHIVE_BASE / recorded_at.strftime("%Y/%m/%d")
    date_dir.mkdir(parents=True, exist_ok=True)

    slug = make_slug(transcript)
    stem = f"{recorded_at.strftime('%H-%M-%S')}-{slug}"

    # Copy audio
    archive_audio = date_dir / f"{stem}{audio_path.suffix}"
    shutil.copy2(audio_path, archive_audio)

    # Write transcript markdown (Phase 1 fields — Hermes adds classification later)
    archive_md = date_dir / f"{stem}.md"
    archive_md.write_text(
        f"---\n"
        f'memo_id: "{memo_id}"\n'
        f"source_path: {source_path}\n"
        f"source_mtime: {source_mtime}\n"
        f"source_size_bytes: {source_size_bytes}\n"
        f"recorded_at: {recorded_at.isoformat()}\n"
        f"archived_at: {now.isoformat()}\n"
        f"---\n\n"
        f"{transcript}\n"
    )

    # Ensure files are owned by the HOME directory owner, not root.
    # The watcher may run as a LaunchDaemon (root) but Hermes runs as the
    # user and needs to update frontmatter later.
    try:
        home_stat = HOME.stat()
        uid, gid = home_stat.st_uid, home_stat.st_gid
        for p in (date_dir, archive_audio, archive_md):
            try:
                os.chown(p, uid, gid)
            except OSError:
                pass
    except OSError:
        pass

    log(f"archived {memo_id} to {archive_md}")
    return archive_md


# ── Webhook ─────────────────────────────────────────────────────────────
def fire_webhook(
    memo_id: str,
    transcript: str,
    archive_path: str,
    source_filename: str,
    source_mtime: int,
    source_size_bytes: int,
) -> bool:
    """POST to Hermes webhook. Returns True on success."""
    payload = json.dumps({
        "memo_id": memo_id,
        "transcript": transcript,
        "archive_path": str(archive_path),
        "source_filename": source_filename,
        "source_mtime": source_mtime,
        "source_size_bytes": source_size_bytes,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }).encode()

    headers = {
        "Content-Type": "application/json",
    }
    if WEBHOOK_SECRET:
        sig = hmac.new(WEBHOOK_SECRET.encode(), payload, hashlib.sha256).hexdigest()
        headers["X-Hub-Signature-256"] = f"sha256={sig}"

    try:
        req = urllib.request.Request(WEBHOOK_URL, data=payload, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=30) as resp:
            log(f"webhook fired for {memo_id} (status {resp.status})")
            return resp.status < 400
    except Exception as e:
        log(f"webhook failed for {memo_id}: {e}")
        return False


# ── Main ────────────────────────────────────────────────────────────────
def main():
    # Setup
    for d in [STATE_DIR, PROCESSED_DIR, TMP_AUDIO_DIR]:
        d.mkdir(parents=True, exist_ok=True)
    SEEN_FILE.touch(exist_ok=True)
    LOG_FILE.touch(exist_ok=True)

    # Lock
    if not acquire_lock():
        return

    try:
        rotate_log()

        # Find recordings
        recordings_dir = find_recordings_dir()
        if not recordings_dir:
            log("ERROR: no Voice Memos recordings dir found")
            return

        # Discover new memos
        memos = discover_new_memos(recordings_dir)
        if not memos:
            log("watcher run complete")
            return

        for memo in memos:
            source = memo["source"]
            tmp_copy = memo["tmp_copy"]
            memo_basename = source.name
            memo_id = source.stem
            source_stat = source.stat()
            source_mtime = int(source_stat.st_mtime)
            source_size_bytes = source_stat.st_size

            # Validate audio
            if tmp_copy.suffix.lower() == ".qta":
                converted = convert_qta(tmp_copy)
                if not converted:
                    continue
                tmp_copy = converted

            # Dedup
            if is_duplicate(memo_id, source):
                log(f"duplicate: {memo_basename}, skipping")
                with open(SEEN_FILE, "a") as f:
                    f.write(f"{memo_basename}\n")
                continue

            log(f"new memo: {memo_basename}")

            # Transcribe
            transcript = transcribe(tmp_copy)
            if not transcript:
                log(f"ERROR: transcription failed for {memo_basename}")
                continue

            # Archive
            archive_md = archive(
                audio_path=tmp_copy,
                transcript=transcript,
                memo_id=memo_id,
                source_path=source,
                source_mtime=source_mtime,
                source_size_bytes=source_size_bytes,
            )

            # Fire webhook to Hermes
            webhook_ok = fire_webhook(
                memo_id=memo_id,
                transcript=transcript,
                archive_path=str(archive_md),
                source_filename=memo_basename,
                source_mtime=source_mtime,
                source_size_bytes=source_size_bytes,
            )

            if webhook_ok:
                with open(SEEN_FILE, "a") as f:
                    f.write(f"{memo_basename}\n")
                log(f"processed {memo_basename} successfully")
            else:
                log(f"WARN: webhook failed for {memo_basename}, will retry next run")

        log("watcher run complete")

    finally:
        release_lock()


if __name__ == "__main__":
    main()
