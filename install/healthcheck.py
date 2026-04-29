#!/usr/bin/env python3
"""Daily launchd health check for the Apple Voice Assistant watcher."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HOME = Path(os.environ.get("HOME", str(Path.home()))).expanduser()
STATE_DIR = Path(os.environ.get("APPLE_VOICE_ASSISTANT_STATE_DIR", str(HOME / ".local/state/apple-voice-assistant"))).expanduser()
LOG_FILE = STATE_DIR / "watcher.log"
ALERT_FILE = STATE_DIR / "healthcheck.alert"
MAX_SILENCE_SECONDS = int(os.environ.get("APPLE_VOICE_ASSISTANT_MAX_SILENCE_SECONDS", "86400"))


def iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def notify(message: str) -> None:
    if shutil.which("osascript") is None:
        return
    subprocess.run([
        "osascript",
        "-e",
        f'display notification "{message}" with title "Voice Assistant Health Check" sound name "Basso"',
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main() -> int:
    if not LOG_FILE.exists():
        print(f"WARN: watcher log does not exist at {LOG_FILE}", file=sys.stderr)
        return 1
    last = LOG_FILE.stat().st_mtime
    age = int(time.time() - last)
    if age <= MAX_SILENCE_SECONDS:
        ALERT_FILE.unlink(missing_ok=True)
        return 0
    hours = age // 3600
    message = f"apple-voice-assistant watcher has been silent for {hours}h (last log entry {iso(last)})"
    ALERT_FILE.write_text(message + "\n", encoding="utf-8")
    notify(message)
    print(f"ALERT: {message}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
