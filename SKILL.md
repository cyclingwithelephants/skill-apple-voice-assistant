---
name: apple-voice-assistant
description: Process an iPhone voice memo — classify intent, act on it, archive, and report back.
homepage: https://github.com/cyclingwithelephants/skill-apple-voice-assistant
---

# Apple Voice Assistant

You process iPhone voice memos on behalf of the user. A deterministic Python watcher (`scripts/process-memo.py`) handles file discovery, transcription, deduplication, and archiving, then POSTs a webhook to the Hermes gateway with the transcript and metadata. You receive the webhook payload and handle classification, action dispatch, and audit.

## Step 0 — Webhook payload

The watcher POSTs a JSON payload to your webhook endpoint. You receive these fields:

| Field               | Type   | Description                                                 |
| ------------------- | ------ | ----------------------------------------------------------- |
| `memo_id`           | string | Voice Memos filename stem, e.g. `"20260419 083045"`         |
| `transcript`        | string | Full transcript text (already transcribed by the watcher)   |
| `archive_path`      | string | Absolute path to the archived transcript `.md` file         |
| `source_filename`   | string | Original Voice Memos filename, e.g. `"20260419 083045.m4a"` |
| `source_mtime`      | int    | Unix timestamp of the original file's mtime                 |
| `source_size_bytes` | int    | Size of the original file in bytes                          |
| `timestamp`         | string | ISO 8601 timestamp of when the webhook was fired            |

The watcher has already handled: file discovery, iCloud sync stability checks, `.qta` → `.m4a` conversion, transcription (via local Whisper API), deduplication (via `seen.txt` + processed JSON), and Phase 1 archiving (audio copy + transcript with deterministic frontmatter).

## Step 1 — Validate the payload

Extract the transcript from the webhook payload. Validate before proceeding:

- `transcript` is non-empty
- `memo_id` is present
- `archive_path` is present

If any check fails, send the user an audit message explaining the problem and stop.

## Step 2 — Classify the transcript

Assign exactly one **state** and one **confidence level**.

### States

| State                    | Meaning                                                                                                             |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| `EXTERNAL_MESSAGE_DRAFT` | User wants a message/reply drafted for another person or external channel; never send without explicit confirmation |
| `REMINDER_OR_ALARM`      | Time-sensitive reminder/alarm/shopping-list item; create Apple Reminder/List item and log fallback state            |
| `QUESTION_ANSWER`        | User asks a factual/how-to/explanatory question; answer directly and archive                                        |
| `IMPLEMENTATION_TASK`    | User asks you to build/change/test something now; implement or create concrete artifact, then report                |
| `PLANNING_REQUEST`       | User asks for a project plan/approach/design, not immediate implementation                                          |
| `INSTRUCTION_DIRECT`     | Legacy/general direct instruction not covered by a narrower state                                                   |
| `INSTRUCTION`            | User is teaching a new rule, pattern, or example for this skill itself                                              |
| `TODO`                   | Legacy/general task capture — create an Apple Reminder and log to TODO.md                                           |
| `MEMORY_NOTE`            | A fact to persist — about a person, project, system, or preference                                                  |
| `IDEA_CAPTURE`           | A product, project, or creative idea to capture in memory                                                           |
| `RESEARCH_REQUEST`       | "Look into X" — create a research task, do NOT act immediately                                                      |
| `UNKNOWN`                | No clear intent or ambiguous instruction — message the user                                                         |

`UNKNOWN` is the catch-all. Use it when intent is genuinely unclear, when a memo sounds like an instruction but scope or meaning is ambiguous, or when confidence is too low to act. Always message the user for clarification. Classify into a specific state whenever possible.

### Classification biases

- Prefer narrow categories over legacy catch-alls: `EXTERNAL_MESSAGE_DRAFT`, `REMINDER_OR_ALARM`, `QUESTION_ANSWER`, `IMPLEMENTATION_TASK`, or `PLANNING_REQUEST` before `INSTRUCTION_DIRECT`/`TODO`.
- Prefer `EXTERNAL_MESSAGE_DRAFT` for any outbound message draft, even if the user says "message X". Draft only; ask for confirmation before sending.
- Prefer `REMINDER_OR_ALARM` for reminders, shopping-list additions, alarms, and time-sensitive personal tasks.
- Prefer `QUESTION_ANSWER` when the intended action is just answering/explaining.
- Prefer `IMPLEMENTATION_TASK` when code/config/file changes or tests should happen now.
- Prefer `PLANNING_REQUEST` when the output should be a plan/design/approach document rather than immediate implementation.
- Prefer `UNKNOWN` over action categories when scope is genuinely unclear — cheaper to ask than to act wrongly.
- Prefer `MEMORY_NOTE` over `IDEA_CAPTURE` when the memo contains a concrete fact, even if framed as an idea.
- Prefer a specific state over `UNKNOWN` — but when genuinely unsure, `UNKNOWN` + messaging the user is always safe.

See [`references/classification-examples.md`](references/classification-examples.md) for worked examples covering common and edge-case phrasings.

### Confidence

Rate your classification confidence as `high`, `medium`, or `low`.

| Confidence | Meaning                                               | Constraint                                                                                                       |
| ---------- | ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `high`     | Clear intent, unambiguous phrasing                    | No restrictions                                                                                                  |
| `medium`   | Likely correct but some ambiguity                     | Proceed, but note uncertainty in audit message                                                                   |
| `low`      | Guessing — transcript is noisy, garbled, or ambiguous | **Never perform external or irreversible actions.** Classify as `UNKNOWN` and message the user for clarification |

Voice-to-text errors are common. A misheard word can completely change intent. When confidence is low, the cost of asking is always lower than the cost of acting wrongly.

## Step 3 — Deduplication (handled by watcher)

The watcher deduplicates before firing the webhook — via `seen.txt` and processed JSON checks. If you received a webhook, the memo is new. Proceed.

## Step 4 — Update the archive

The watcher has already archived the audio and transcript to `archive_path` with Phase 1 frontmatter (deterministic fields: `memo_id`, `source_path`, `source_mtime`, `source_size_bytes`, `recorded_at`, `archived_at`).

Update the archive file at `archive_path` to add classification metadata — insert these fields into the existing YAML frontmatter:

- `category` — the state from Step 2
- `confidence` — high/medium/low from Step 2
- `type` — semantic tag: `memo` (default), `idea`, `research`
- `action_taken` — fill in after Step 5 completes (update the file after acting)

See [`references/archive-format.md`](references/archive-format.md) for the full archive specification.

## Step 5 — Act on the category

STOP. Read the action file for your classified state. The filename follows this pattern exactly:

```
references/action_<STATE>.md
```

Replace `<STATE>` with the state you assigned in Step 2. Example: if you classified as `TODO`, read `references/action_TODO.md`.

Read that file NOW. Follow its numbered steps. Do NOT skip any step. When the file says DONE, you are done.

### Safety rules (apply to ALL states)

1. **NEVER send, post, or publish externally without confirmation.** Draft + confirm for any external communication.
2. **Low confidence = no irreversible actions.** Archive only and ask for clarification.
3. **NEVER delete or move the source `.m4a`.** iCloud owns that lifecycle.

## Intake status report workflow

Use this when the user asks for a status report, summary, audit, or "what's actionable" view of voice memo intake.

1. Inspect live state, do not answer from memory:
   - `~/.local/state/apple-voice-assistant/data/**/*.md` for archived transcripts, frontmatter category/confidence/type/action_taken, and archive paths
   - `~/.local/state/apple-voice-assistant/processed/*.json` for processed metadata
   - `~/.local/state/apple-voice-assistant/seen.txt` plus the Voice Memos recordings directory to detect unseen/pending audio
   - `~/.local/state/apple-voice-assistant/TODO.md` for reliable task/research/follow-up fallback records
   - Apple Reminders via `/opt/homebrew/bin/remindctl all` when assessing TODO/reminder actions
   - `~/.local/state/apple-voice-assistant/watcher.log` for recent errors, webhook failures, and rate-limit symptoms
2. Report pipeline health first: total recordings, seen/unseen, archive count, processed count, missing classification/action metadata, newest processed memo, and watcher health/errors.
3. Group archived memos by category and confidence. Normalize quoted categories such as `"INSTRUCTION_DIRECT"` when summarizing.
4. Separate outcomes into useful buckets:
   - actionable personal tasks/reminders
   - research requests logged but not yet executed
   - engineering/project tasks or generated artifacts/plans/tests
   - external message drafts needing explicit confirmation before sending
   - captured ideas/memory notes that are not currently tasks
   - UNKNOWN/noise/test memos needing clarification or no action
5. Call out duplicates and stale follow-up mess explicitly. Common examples: duplicated TODO.md research entries, duplicated Apple Reminders, and Matrix 429 audit failures written as FOLLOW-UP lines.
6. If asked to clean/dedupe the intake state, preserve source archives and processed JSON, but rewrite `TODO.md` into human-useful sections: active tasks, external drafts awaiting confirmation, and captured/non-task notes. Remove Matrix 429 FOLLOW-UP noise after confirming the underlying action already happened or is captured elsewhere.
7. When deduping Apple Reminders, only delete clearly duplicated voice-memo fallout items. Prefer keeping the shorter canonical reminder title when duplicates differ (for example keep `Experiment with CI node CPU allocation`, remove `Create lab experiment comparing CI node CPU allocation`). Verify with `remindctl all --json` before and after deletion.
8. Include concrete artifact paths for plans/tests/archives when they matter, but keep the final report human-prioritized rather than dumping every path.
9. End with a short opinionated priority list of next cleanup/actions.

## Operational notes

- **User confirmation requirement.** The user wants a Matrix confirmation/audit message every time a voice memo is processed, regardless of category or whether the action succeeded, failed, or only created a draft. Use the audit target configured via `APPLE_VOICE_ASSISTANT_AUDIT_TARGET` (set in `~/.local/state/apple-voice-assistant/env` or passed via the webhook subscription's `--deliver-chat-id`). If Matrix delivery fails, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md` with enough detail to replay the missed confirmation later.
- **Two-component architecture.** The Python watcher (`scripts/process-memo.py`) runs as a launchd daemon, handles all I/O (discovery, transcription, archiving), and POSTs to the Hermes webhook. You receive the webhook payload and handle classification, action dispatch, and audit.
- The watcher runs as a LaunchDaemon (starts at boot, before login) — it only does file I/O and webhook POSTs, no GUI access needed. It needs `HOME` set and a `PATH` that includes `/run/current-system/sw/bin`.
- Voice Memos TCC access: the watcher uses the Hermes venv Python interpreter to enumerate the protected Voice Memos directory, then copies files to `~/.local/state/apple-voice-assistant/tmp-audio/` before processing.
- Hermes model selection is controlled by `~/.hermes/config.yaml` (default model + `fallback_providers` chain), not by the watcher or webhook config.
- The webhook subscription is registered by `scripts/setup-webhook.sh`. Run it once after deploying, or re-run when the prompt template changes. Subscriptions persist across gateway restarts.
- For Matrix audit delivery, use the target configured in `APPLE_VOICE_ASSISTANT_AUDIT_TARGET`.

## End-to-end verification recipe

Use a synthetic memo rather than waiting on iCloud. Two stages to verify:

### Stage 1 — Watcher (deterministic)

1. Copy a known-good Voice Memos audio file (`.qta` is fine) into the Voice Memos recordings directory with a unique filename like `YYYYMMDD HHMMSS-HERMESTEST.qta`.
2. Add a matching synthetic transcript at the staged copy path:
   ```text
   ~/.local/state/apple-voice-assistant/tmp-audio/YYYYMMDD HHMMSS-HERMESTEST.m4a.transcript.txt
   ```
3. Remove that basename from `~/.local/state/apple-voice-assistant/seen.txt` and remove any old processed JSON for the same memo id.
4. Run or kick the watcher, then tail `~/.local/state/apple-voice-assistant/watcher.log`.
5. Verify watcher artifacts:
   - Archive transcript: `~/.local/state/apple-voice-assistant/data/YYYY/MM/DD/HH-MM-SS-<slug>.md` (Phase 1 frontmatter only)
   - Archive audio: matching `.m4a` in the same directory
   - Log shows: `archived`, `webhook fired` with status 200

### Stage 2 — Hermes (LLM)

6. Check Hermes gateway logs — confirm webhook received, skill session started.
7. Check Matrix room — confirm audit message with classification, action taken, archive path.
8. Re-read the archive file — confirm Phase 2 fields added (`category`, `confidence`, `type`, `action_taken`).
9. Verify processed JSON at `~/.local/state/apple-voice-assistant/processed/<memo_id>.json`.
10. Verify launchd health: `launchctl print system/com.cyclingwithelephants.apple-voice-assistant`; `state = not running` with `last exit code = 0` is healthy (short-lived daemon).
