# Apple Voice Assistant

Hermes skill that processes iPhone Voice Memos. A launchd-triggered Python watcher discovers new recordings synced via iCloud, transcribes them locally, archives them, and POSTs a webhook to the Hermes gateway. Hermes then classifies intent, dispatches actions, and audits results.

## Core design principle: self-improving taxonomy

This skill is designed to discover new use cases and evolve its own classification over time. The taxonomy is not fixed — it grows through a teaching loop:

1. **`UNKNOWN` as a signal, not a dead end.** When a memo doesn't fit any existing state, the agent classifies it as `UNKNOWN` and asks the user for clarification. That clarification becomes training data for better future classification.
2. **`INSTRUCTION` state for self-modification.** When the user says things like "from now on, treat X as Y" or "add a rule that...", the agent records a concrete proposal in `PROPOSALS.md` with a suggested patch to `SKILL.md` or `references/classification-examples.md`. The user reviews and merges these proposals — the skill literally rewrites its own classification rules.
3. **`references/classification-examples.md` is living ground truth.** This file grows over time as the teaching loop proposes new patterns. Every ambiguous memo that gets resolved becomes a new worked example that prevents the same ambiguity next time.
4. **New states can be added.** The current 12 states emerged from real usage. When a pattern of memos consistently doesn't fit existing buckets, the right response is to propose a new state with its own action file in `references/action_<STATE>.md`.

When working on this skill, preserve and strengthen this feedback loop. Don't hardcode behaviour that should be learned. Prefer adding classification examples over adding code branches. The goal is an agent that gets better at understanding its user over time without code changes.

## Architecture

```
iPhone Voice Memo
  → iCloud sync to ~/Library/Group Containers/.../Recordings/
  → launchd fires watcher (scripts/process-memo.py)
  → transcribe (scripts/transcribe.py — local Whisper API, with fallback chain)
  → archive audio + transcript to ~/.local/state/apple-voice-assistant/data/
  → POST webhook to Hermes gateway
  → Hermes classifies → dispatches action → audits via Matrix
```

Two runtime paths exist:

- **Manual install**: `install/install.sh` sets up LaunchAgents from plist templates
- **Nix-darwin module**: `flake.nix` exports `darwinModules.apple-voice-assistant` for declarative config

## Key files

| Path                                    | Purpose                                                                                             |
| --------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `SKILL.md`                              | Authoritative skill spec — states, classification rules, action dispatch, safety rules              |
| `scripts/process-memo.py`               | Main watcher: discovery → transcription → dedup → archive → webhook                                 |
| `scripts/transcribe.py`                 | Transcription with provider fallback chain (Whisper API → SFSpeech → mlx → faster-whisper → OpenAI) |
| `install/watcher.py`                    | Legacy shell-era watcher (Python rewrite), invoked by launchd                                       |
| `install/healthcheck.py`                | Daily health check — alerts if watcher silent >24h                                                  |
| `flake.nix`                             | Nix-darwin module with `services.apple-voice-assistant` options                                     |
| `references/actions.md`                 | Detailed action specs per classification state                                                      |
| `references/classification-examples.md` | Ground truth examples for classification (grows via teaching loop)                                  |
| `references/archive-format.md`          | Archive directory layout and transcript frontmatter spec                                            |
| `references/action_*.md`                | Per-state action reference documents                                                                |

## Classification states

There are 12 states — see `SKILL.md` Step 2 for the full table. Key ones:
`INSTRUCTION_DIRECT`, `INSTRUCTION`, `TODO`, `MEMORY_NOTE`, `IDEA_CAPTURE`, `RESEARCH_REQUEST`, `QUESTION_ANSWER`, `IMPLEMENTATION_TASK`, `PLANNING_REQUEST`, `EXTERNAL_MESSAGE_DRAFT`, `REMINDER_OR_ALARM`, `UNKNOWN`

## Safety rules

1. **Never send/post externally** without explicit user confirmation
2. **Low confidence = no irreversible actions** — ask the user instead
3. **Never delete/move source `.m4a` files** — iCloud owns their lifecycle
4. **SKILL.md is the authority** — when in doubt, defer to it over code comments or READMEs

## Environment variables

The watcher reads these at runtime (all optional, sensible defaults exist):

| Variable                                 | Purpose                                                         |
| ---------------------------------------- | --------------------------------------------------------------- |
| `HERMES_HOME`                            | Hermes runtime home (default: `~/.hermes`)                      |
| `APPLE_VOICE_ASSISTANT_PYTHON`           | Python interpreter path                                         |
| `APPLE_VOICE_ASSISTANT_WHISPER_API_BASE` | Local Whisper API URL (default: `http://127.0.0.1:9099`)        |
| `APPLE_VOICE_ASSISTANT_AUDIT_TARGET`     | Messaging target for audit trail (e.g. `matrix:!roomid:server`) |
| `APPLE_VOICE_ASSISTANT_WEBHOOK_URL`      | Hermes webhook endpoint                                         |
| `APPLE_VOICE_ASSISTANT_WEBHOOK_SECRET`   | HMAC secret for webhook signing                                 |
| `APPLE_VOICE_ASSISTANT_RECORDINGS_DIR`   | Voice Memos sync directory override                             |
| `APPLE_VOICE_ASSISTANT_STATE_DIR`        | State directory override                                        |

## Verification commands

```bash
# Lint Python scripts
python3 -m py_compile scripts/process-memo.py
python3 -m py_compile scripts/transcribe.py
python3 -m py_compile install/watcher.py
python3 -m py_compile install/healthcheck.py
python3 -m py_compile install/install.py

# Lint shell scripts
shellcheck install/watcher.sh install/healthcheck.sh install/install.sh scripts/transcribe.sh

# Validate Nix flake
nix flake check --no-build

# Check nix-darwin module builds (requires a consuming flake, e.g. lab-radish)
# nix build .#darwinConfigurations.<host>.system --no-link

# End-to-end test: place a synthetic .m4a in the recordings dir and watch logs
# tail -f ~/.local/state/apple-voice-assistant/watcher.log
```

## State directory layout (runtime, not in repo)

```
~/.local/state/apple-voice-assistant/
├── seen.txt          # Newline-delimited basenames of processed memos
├── watcher.log       # Watcher log (auto-rotates at 10MB)
├── watcher.lock/     # mkdir-based lock for serialization
├── processed/*.json  # Per-memo idempotency records
├── tmp-audio/        # Staging dir (TCC workaround for iCloud files)
├── data/YYYY/MM/DD/  # Archived audio + transcripts
└── env               # Runtime env vars (written by nix activation or setup)
```
