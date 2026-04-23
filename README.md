# skill-apple-voice-assistant

An [openclaw](https://openclaw.ai) skill that turns iPhone voice memos into actions.

Record a memo on your phone. iCloud syncs it to your Mac mini. A launchd watcher fires openclaw. openclaw transcribes natively, classifies the intent, and either does the thing, asks you about it, or files it for later — reporting back via your configured messaging channel.

## What it does

Each new `.m4a` in your Voice Memos iCloud sync dir is classified into one of twelve states, each with its own action:

| State                | Action                                                             |
| -------------------- | ------------------------------------------------------------------ |
| `INSTRUCTION_DIRECT` | Carry out the instruction, report back                             |
| `INSTRUCTION_ADD`    | Record a rule proposal in `PROPOSALS.md` with a suggested patch    |
| `INSTRUCTION_UNSURE` | Ask the user to confirm **and** file a disambiguating example      |
| `TODO_ADAM`          | Create an Apple Reminder in the default (Siri) list                |
| `TODO_ASSISTANT`     | Append to `TODO.md` in this skill's directory                      |
| `MEMORY_NOTE`        | Write to the runtime's memory system                               |
| `JOURNAL_NOTE`       | Archive only — raw thoughts, reflections                           |
| `IDEA_CAPTURE`       | Archive + append to `IDEAS.md`                                     |
| `RESEARCH_REQUEST`   | File a research task (don't act immediately)                       |
| `MESSAGE_DRAFT`      | Draft a message, **never** send without confirmation               |
| `TRANSCRIBE_ONLY`    | Archive transcript, no action                                      |
| `UNKNOWN`            | Ask how to categorize — feeds the classification training pipeline |

Every classification also carries a **confidence level** (`high`/`medium`/`low`). Low-confidence classifications never trigger external or irreversible actions.

All states produce an audit message so nothing disappears silently. See [`SKILL.md`](SKILL.md) for the workflow and [`references/`](references/) for classification examples, action specs, and archive format.

Every memo is also archived into this skill's own `data/` tree, organized by date:

```
data/YYYY/MM/DD/HH-MM-SS-<slug>.m4a    # copy of the original audio
data/YYYY/MM/DD/HH-MM-SS-<slug>.md     # transcript + metadata (source path, category, confidence, action taken)
```

Where `<slug>` is a 2–6-word lowercase summary derived from the transcript (e.g. `08-30-45-grocery-list-for-saturday.m4a`) so you can find a memo by skimming filenames.

`data/` is git-ignored — the archive is a local history on whichever machine the skill runs on.

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
        │   acquires lock, validates file stability, diffs against seen-set
        │   emits one openclaw call per new memo (with timeout)
        ▼
openclaw agent --message "new voice memo at <path>"
        │   loads SKILL.md, attaches audio, native Whisper transcribes
        ▼
classify (+ confidence) → dedup check → archive → act → audit
```

## Prerequisites

- macOS (tested on Apple Silicon; should work on Intel)
- [openclaw](https://openclaw.ai) installed and onboarded (`openclaw onboard`)
- Messaging channel configured in openclaw (`openclaw channels add`) — the skill reports back via your primary channel
- Voice Memos signed into the same iCloud account as your iPhone, with iCloud sync enabled (System Settings → Apple ID → iCloud → Voice Memos)
- Mac mini stays awake, or is set to wake for network access

## Install

```bash
git clone https://github.com/cyclingwithelephants/skill-apple-voice-assistant.git
cd skill-apple-voice-assistant
./install/install.sh
```

The installer:

1. Validates prerequisites (`openclaw`, `osascript`)
2. Symlinks this repo into `~/.openclaw/workspace/skills/apple_voice_assistant`
3. Renders and bootstraps the launchd watcher (fires on directory changes)
4. Installs a daily health check (09:00 — alerts if the watcher has gone silent)
5. Seeds the seen-set with existing memos so your history doesn't get re-processed

Record a new memo on your iPhone. Tail the log to confirm:

```bash
tail -f ~/.local/state/apple-voice-assistant/watcher.log
```

## Uninstall

```bash
DOMAIN="gui/$(id -u)"
launchctl bootout "${DOMAIN}" ~/Library/LaunchAgents/com.cyclingwithelephants.apple-voice-assistant.plist
launchctl bootout "${DOMAIN}" ~/Library/LaunchAgents/com.cyclingwithelephants.apple-voice-assistant-healthcheck.plist
rm ~/Library/LaunchAgents/com.cyclingwithelephants.apple-voice-assistant*.plist
rm ~/.openclaw/workspace/skills/apple_voice_assistant
```

## Teaching it new rules

Record a memo describing the new rule (e.g. "when I say 'remind me to X', always treat that as a `TODO_ADAM`, never `TODO_ASSISTANT`"). If classified as `INSTRUCTION_ADD`, openclaw will append a proposal to `PROPOSALS.md` with a suggested patch for `SKILL.md` or the classification examples. Review, apply, done — next run picks up the new rule.

Classification examples live in [`references/classification-examples.md`](references/classification-examples.md) and grow over time as the teaching loop proposes new patterns.

## Files

- [`SKILL.md`](SKILL.md) — the skill core (workflow, safety rules, classification states)
- [`references/classification-examples.md`](references/classification-examples.md) — worked examples for classification
- [`references/actions.md`](references/actions.md) — what each state does
- [`references/archive-format.md`](references/archive-format.md) — archive directory layout and transcript metadata spec
- [`install/watcher.sh`](install/watcher.sh) — launchd-fired shell script (lock, stability check, timeout, seen-set diff)
- [`install/healthcheck.sh`](install/healthcheck.sh) — daily health check (alerts if watcher goes silent)
- [`install/com.cyclingwithelephants.apple-voice-assistant.plist`](install/com.cyclingwithelephants.apple-voice-assistant.plist) — launchd watcher agent
- [`install/com.cyclingwithelephants.apple-voice-assistant-healthcheck.plist`](install/com.cyclingwithelephants.apple-voice-assistant-healthcheck.plist) — launchd health check agent
- [`install/install.sh`](install/install.sh) — wires it all up

## License

MIT
