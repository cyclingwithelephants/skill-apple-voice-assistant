# skill-apple-voice-assistant

An [Hermes](https://Hermes.ai) skill that turns iPhone voice memos into actions.

Record a memo on your phone. iCloud syncs it to your Mac. A deterministic Python watcher transcribes it, archives it, and fires a webhook to the Hermes gateway. Hermes classifies the intent and either does the thing, asks you about it, or files it for later — reporting back via Matrix.

## What it does

Each new `.m4a` in your Voice Memos iCloud sync dir is classified into one of twelve states, each with its own action file:

| State                    | Action                                                               |
| ------------------------ | -------------------------------------------------------------------- |
| `EXTERNAL_MESSAGE_DRAFT` | Draft a message/reply; never send without explicit confirmation      |
| `REMINDER_OR_ALARM`      | Create a reminder/alarm/list item and log fallback state             |
| `QUESTION_ANSWER`        | Answer a factual/how-to/explanatory question directly                |
| `IMPLEMENTATION_TASK`    | Build/change/test something now, then report                         |
| `PLANNING_REQUEST`       | Produce a project plan/approach/design                               |
| `INSTRUCTION_DIRECT`     | Legacy/general direct instruction not covered by a narrower state    |
| `INSTRUCTION`            | Record a rule proposal in `PROPOSALS.md` with a suggested patch      |
| `TODO`                   | Legacy/general task capture — create an Apple Reminder + log TODO.md |
| `MEMORY_NOTE`            | Persist a durable fact to Hermes memory                              |
| `IDEA_CAPTURE`           | Capture a product/project/creative idea in memory                    |
| `RESEARCH_REQUEST`       | File a research task; do not act immediately                         |
| `UNKNOWN`                | Message the user for clarification                                   |

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
Mac: ~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/
        │   launchd WatchPaths fires
        ▼
scripts/process-memo.py                          ← deterministic, no LLM
        │   acquires lock, validates file stability, diffs against seen-set
        │   transcribes via local Whisper API
        │   archives audio + transcript to ~/.local/state/.../data/
        │   POSTs webhook to Hermes gateway
        ▼
Hermes gateway (http://127.0.0.1:8644/webhooks/voice-memo)
        │   receives JSON: memo_id, transcript, archive_path, source metadata
        │   loads SKILL.md + apple-voice-assistant skill
        ▼
classify (+ confidence) → update archive → act → audit to Matrix
```

Two decoupled components:

- **Watcher** (`process-memo.py`) — deterministic Python, no LLM calls. Handles I/O: discovery, transcription, dedup, archiving, webhook POST.
- **Hermes webhook handler** — LLM-powered. Handles intelligence: classification, action dispatch, audit.

## Prerequisites

- macOS
- [Hermes](https://Hermes.ai) installed and onboarded (`Hermes onboard`)
- Local Whisper API running at `http://127.0.0.1:9099` (for transcription)
- Messaging channel configured in Hermes — the skill reports back via Matrix
- Voice Memos signed into the same iCloud account as your iPhone, with iCloud sync enabled (System Settings → Apple ID → iCloud → Voice Memos)
- Mac stays awake, or is set to wake for network access

## Install

### Option A: nix-darwin (declarative)

This repo exports a nix-darwin module via `flake.nix`. Add it to your flake inputs, import `darwinModules.apple-voice-assistant`, and enable the service in your host configuration. After a rebuild, register the webhook:

```bash
bash ~/.hermes/skills/apple/apple-voice-assistant/scripts/setup-webhook.sh
```

### Option B: manual (any macOS host)

```bash
git clone https://github.com/cyclingwithelephants/skill-apple-voice-assistant.git
cd skill-apple-voice-assistant
./install/install.sh
```

The installer:

1. Validates prerequisites (`Hermes`, `osascript`)
2. Symlinks this repo into the active Hermes workspace's `skills/` directory
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
rm ~/.hermes/skills/apple/apple-voice-assistant
```

## Teaching it new rules

Record a memo describing the new rule (e.g. "when I say 'remind me to X', always treat that as a `TODO`"). If classified as `INSTRUCTION`, Hermes will append a proposal to `PROPOSALS.md` with a suggested patch for `SKILL.md` or the classification examples. Review, apply, done — next run picks up the new rule.

Classification examples live in [`references/classification-examples.md`](references/classification-examples.md) and grow over time as the teaching loop proposes new patterns.

## Files

- [`SKILL.md`](SKILL.md) — the skill core (workflow, safety rules, classification states)
- [`scripts/process-memo.py`](scripts/process-memo.py) — deterministic Python watcher (discovery, transcription, archiving, webhook POST)
- [`scripts/setup-webhook.sh`](scripts/setup-webhook.sh) — registers the voice-memo webhook subscription with the Hermes gateway
- [`scripts/transcribe.sh`](scripts/transcribe.sh) — transcription fallback chain (whisper API, mlx-whisper, faster-whisper, OpenAI)
- [`references/classification-examples.md`](references/classification-examples.md) — worked examples for classification
- [`references/action_*.md`](references/) — per-state action specs (one per classification state)
- [`references/archive-format.md`](references/archive-format.md) — archive directory layout and transcript metadata spec
- [`install/healthcheck.sh`](install/healthcheck.sh) — daily health check (alerts if watcher goes silent)
- [`install/watcher.sh`](install/watcher.sh) — legacy shell watcher (for non-Nix installs without webhook support)
- [`install/install.sh`](install/install.sh) — legacy installer for non-Nix macOS hosts

## License

MIT
