# skill-apple-voice-assistant

An [openclaw](https://openclaw.ai) skill that turns iPhone voice memos into actions.

Record a memo on your phone. iCloud syncs it to your Mac mini. A launchd watcher fires openclaw. openclaw transcribes natively, classifies the intent, and either does the thing, asks you about it, or files it for later — reporting back on Matrix.

## What it does

Each new `.m4a` in your Voice Memos iCloud sync dir is classified into one of six states, each with its own action:

| State                | Action                                                            |
| -------------------- | ----------------------------------------------------------------- |
| `UNKNOWN`            | Ask on Matrix how to categorize                                   |
| `INSTRUCTION_ADD`    | Open a GitHub issue on this repo with the proposed rule           |
| `INSTRUCTION_DIRECT` | Carry out the instruction, report back on Matrix                  |
| `INSTRUCTION_UNSURE` | Ask on Matrix **and** file an issue with a disambiguating example |
| `TODO_ADAM`          | Create an Apple Reminder in the default (Siri) list               |
| `TODO_ASSISTANT`     | Append to `TODO.md` in this repo                                  |

All six actions produce a Matrix message so nothing disappears silently. See [`SKILL.md`](SKILL.md) for the full classification rules.

Every memo is also archived into this skill's own `data/` tree, organized by date:

```
data/YYYY/MM/DD/HHMMSS.m4a    # copy of the original audio
data/YYYY/MM/DD/HHMMSS.md     # transcript + metadata (source path, category, action taken)
```

`data/` is git-ignored — the archive is a local history on whichever machine the skill runs on, not something to sync to GitHub.

## Architecture

```
iPhone Voice Memos.app
        │   records .m4a
        ▼
iCloud sync
        │
        ▼
Mac mini: ~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/
        │   launchd WatchPaths fires
        ▼
install/watcher.sh
        │   diffs against seen-set, emits one openclaw call per new memo
        ▼
openclaw agent --message "new voice memo at <path>"
        │   loads SKILL.md, attaches audio, native Whisper transcribes
        ▼
classify → act → report on Matrix
```

## Prerequisites

- macOS (tested on Apple Silicon; should work on Intel)
- [openclaw](https://openclaw.ai) installed and onboarded (`openclaw onboard`)
- Matrix channel configured in openclaw (`openclaw channels add`) — the skill assumes openclaw knows how to reach you
- `gh` authenticated (`gh auth status`) with `repo` scope — needed for `INSTRUCTION_ADD` / `INSTRUCTION_UNSURE`
- Voice Memos signed into the same iCloud account as your iPhone, with iCloud sync enabled (System Settings → Apple ID → iCloud → Voice Memos)
- Mac mini stays awake, or is set to wake for network access

## Install

```bash
git clone https://github.com/cyclingwithelephants/skill-apple-voice-assistant.git
cd skill-apple-voice-assistant
./install/install.sh
```

The installer:

1. Symlinks this repo into `~/.openclaw/workspace/skills/apple_voice_assistant`
2. Renders `install/com.cyclingwithelephants.apple-voice-assistant.plist` into `~/Library/LaunchAgents/`
3. Bootstraps the launchd job
4. Seeds the seen-set with existing memos so your history doesn't get re-processed

Record a new memo on your iPhone. Tail the log to confirm:

```bash
tail -f ~/.local/state/apple-voice-assistant/watcher.log
```

## Uninstall

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.cyclingwithelephants.apple-voice-assistant.plist
rm ~/Library/LaunchAgents/com.cyclingwithelephants.apple-voice-assistant.plist
rm ~/.openclaw/workspace/skills/apple_voice_assistant
```

## Teaching it new rules

Record a memo describing the new rule (e.g. "when I say 'remind me to X', always treat that as a `TODO_ADAM`, never `TODO_ASSISTANT`"). If classified as `INSTRUCTION_ADD`, openclaw will open a GitHub issue here proposing the edit to `SKILL.md`. Review, merge, done — next run picks up the new rule.

## Files

- [`SKILL.md`](SKILL.md) — the skill itself (classification rules + actions)
- [`install/watcher.sh`](install/watcher.sh) — launchd-fired shell script that diffs new memos and invokes openclaw
- [`install/com.cyclingwithelephants.apple-voice-assistant.plist`](install/com.cyclingwithelephants.apple-voice-assistant.plist) — launchd agent template
- [`install/install.sh`](install/install.sh) — wires it all up

## License

MIT
