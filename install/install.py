#!/usr/bin/env python3
"""Manual installer for Apple Voice Assistant launchd services."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

LABEL = "com.cyclingwithelephants.apple-voice-assistant"
RECORDING_CANDIDATES = [
    "Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings",
    "Library/Application Support/com.apple.voicememos/Recordings",
]


def say(message: str) -> None:
    print(f"==> {message}")


def die(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def run(args: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, text=True, check=check)


def render(template: Path, destination: Path, replacements: dict[str, str]) -> None:
    text = template.read_text(encoding="utf-8")
    for key, value in replacements.items():
        text = text.replace(key, value)
    destination.write_text(text, encoding="utf-8")


def recordings_dir(home: Path) -> Path:
    for rel in RECORDING_CANDIDATES:
        candidate = home / rel
        if candidate.is_dir():
            return candidate
    die("Voice Memos recordings dir not found. Open Voice Memos, record a test memo, then rerun.")


def seed_seen(recordings: Path, seen_file: Path) -> None:
    if seen_file.exists() and seen_file.stat().st_size > 0:
        lines = seen_file.read_text(encoding="utf-8").splitlines()
        if lines and "/" in lines[0]:
            say("Migrating seen-set from full paths to basenames...")
            seen_file.write_text("\n".join(Path(line).name for line in lines if line) + "\n", encoding="utf-8")
        return
    names = sorted(p.name for p in recordings.iterdir() if p.is_file() and p.suffix.lower() in {".m4a", ".qta"})
    seen_file.write_text("\n".join(names) + ("\n" if names else ""), encoding="utf-8")
    say(f"Seeded seen-set with existing memos ({len(names)} files)")


def bootstrap(domain: str, plist: Path, label: str) -> None:
    run(["launchctl", "bootout", domain, str(plist)], check=False)
    run(["launchctl", "bootstrap", domain, str(plist)])
    run(["launchctl", "enable", f"{domain}/{label}"])


def main() -> int:
    home = Path(os.environ.get("HOME", str(Path.home()))).expanduser()
    repo = Path(__file__).resolve().parents[1]
    state_dir = home / ".local/state/apple-voice-assistant"
    launch_agents = home / "Library/LaunchAgents"
    runtime_home = Path(os.environ.get("HERMES_HOME", str(home / ".hermes"))).expanduser()
    skills_root = runtime_home / "skills"
    skill_dir = skills_root / "apple/apple-voice-assistant"

    if shutil.which("hermes") is None:
        die("hermes not on PATH. Install and onboard the assistant runtime first.")
    if shutil.which("osascript") is None:
        die("osascript not found. This installer requires macOS.")

    recordings = recordings_dir(home)
    say(f"Voice Memos dir: {recordings}")
    say(f"Skills root: {skills_root}")

    skill_dir.parent.mkdir(parents=True, exist_ok=True)
    if skill_dir.is_symlink() or not skill_dir.exists():
        if skill_dir.exists() or skill_dir.is_symlink():
            skill_dir.unlink()
        skill_dir.symlink_to(repo)
    elif skill_dir.resolve() != repo:
        die(f"{skill_dir} exists and is not this repo. Move it aside and rerun.")
    say(f"Skill available at: {skill_dir}")

    state_dir.mkdir(parents=True, exist_ok=True)
    (state_dir / "processed").mkdir(exist_ok=True)
    (state_dir / "watcher.log").touch()
    seen_file = state_dir / "seen.txt"
    seen_file.touch()

    launch_agents.mkdir(parents=True, exist_ok=True)
    watcher_script = repo / "install/watcher.py"
    healthcheck_script = repo / "install/healthcheck.py"
    watcher_script.chmod(0o755)
    healthcheck_script.chmod(0o755)

    watcher_plist = launch_agents / f"{LABEL}.plist"
    healthcheck_label = f"{LABEL}-healthcheck"
    healthcheck_plist = launch_agents / f"{healthcheck_label}.plist"

    render(repo / f"install/{LABEL}.plist", watcher_plist, {
        "__WATCHER_SCRIPT__": str(watcher_script),
        "__RECORDINGS_DIR__": str(recordings),
        "__STATE_DIR__": str(state_dir),
    })
    render(repo / f"install/{healthcheck_label}.plist", healthcheck_plist, {
        "__HEALTHCHECK_SCRIPT__": str(healthcheck_script),
        "__STATE_DIR__": str(state_dir),
    })

    domain = f"gui/{os.getuid()}"
    bootstrap(domain, watcher_plist, LABEL)
    bootstrap(domain, healthcheck_plist, healthcheck_label)
    seed_seen(recordings, seen_file)

    print(f"""
Install complete.

  skill:     {skill_dir}
  watcher:   {watcher_script}
  plist:     {watcher_plist}
  state:     {state_dir}
  logs:      {state_dir / 'watcher.log'}
             {state_dir / 'launchd.{out,err}.log'}

Record a new voice memo on your iPhone, then tail the watcher log:

  tail -f "{state_dir / 'watcher.log'}"

To uninstall:

  launchctl bootout "{domain}" "{watcher_plist}"
  launchctl bootout "{domain}" "{healthcheck_plist}"
  rm "{watcher_plist}" "{healthcheck_plist}"
  rm "{skill_dir}"
""")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
