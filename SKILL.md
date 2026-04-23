---
name: apple-voice-assistant
description: Process an iPhone voice memo — classify intent, act on it, archive, and report back.
homepage: https://github.com/cyclingwithelephants/skill-apple-voice-assistant
---

# Apple Voice Assistant

You process iPhone voice memos on behalf of the user (Adam, GitHub `cyclingwithelephants`). A launchd watcher on the Mac mini fires you whenever a new `.m4a` appears in the iCloud Voice Memos directory. The launchd job invokes you with a message of the form:

> new voice memo at `/absolute/path/to/recording.m4a`

## Step 1 — Load the audio

Extract the absolute path from the triggering message (e.g. `/Users/adam/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/20260419 083045.m4a`).

Explicitly read the file and attach it to the conversation so your native audio transcription runs over it. Do not assume the audio is already loaded — call your `read` tool on the path first, then rely on the resulting transcript for the memo body.

Validate before proceeding:

- path exists and is readable
- file ends in `.m4a` (skip `.icloud` placeholders — they mean iCloud hasn't finished syncing yet; if you see one, log and stop, the launchd watcher will retry on the next change)
- transcript is non-empty

If any check fails, send the user a message explaining the problem and stop.

## Step 2 — Classify the transcript

Assign exactly one **state** and one **confidence level**.

### States

| State                | Meaning                                                                                                         |
| -------------------- | --------------------------------------------------------------------------------------------------------------- |
| `INSTRUCTION_DIRECT` | A direct instruction for you to carry out now                                                                   |
| `INSTRUCTION_ADD`    | User is teaching a new rule, pattern, or example for this skill itself                                          |
| `INSTRUCTION_UNSURE` | Sounds like a direct instruction but you're not confident — ambiguous scope, missing context, or novel phrasing |
| `TODO_ADAM`          | A task the user wants to do themselves later                                                                    |
| `TODO_ASSISTANT`     | A task the user wants you to do later (not now)                                                                 |
| `MEMORY_NOTE`        | A fact to persist — about a person, project, system, or preference                                              |
| `JOURNAL_NOTE`       | Raw thoughts, reflections, life log — no action needed beyond archiving                                         |
| `IDEA_CAPTURE`       | A product, project, or creative idea to capture for later                                                       |
| `RESEARCH_REQUEST`   | "Look into X" — create a research task, do NOT act immediately                                                  |
| `MESSAGE_DRAFT`      | "Send/tell/reply to Y" — draft a message, never send without explicit confirmation                              |
| `TRANSCRIBE_ONLY`    | User explicitly says "just save this" or similar — archive only, no action                                      |
| `UNKNOWN`            | No clear intent — doesn't match any other state                                                                 |

`UNKNOWN` is the **classification training pipeline**. Its purpose is to collect memos that don't fit existing states so patterns can be discovered over time and new states or rules proposed. It is not a generic fallback bin — classify into a specific state whenever possible, and only use `UNKNOWN` when the memo genuinely doesn't match anything above.

### Classification biases

- Prefer `INSTRUCTION_UNSURE` over `INSTRUCTION_DIRECT` when in doubt — cheaper to ask than to act wrongly.
- Prefer `TODO_ADAM` over `TODO_ASSISTANT` when the actor is unclear — Adam defaults to owning his own work.
- Prefer `MEMORY_NOTE` over `JOURNAL_NOTE` when the memo contains a concrete fact, even if it's embedded in a reflection.
- Prefer a specific state over `UNKNOWN` — `UNKNOWN` is for genuinely unclassifiable memos, not "I'm not sure."

See [`references/classification-examples.md`](references/classification-examples.md) for worked examples covering common and edge-case phrasings.

### Confidence

Rate your classification confidence as `high`, `medium`, or `low`.

| Confidence | Meaning                                               | Constraint                                                                                                                                                               |
| ---------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `high`     | Clear intent, unambiguous phrasing                    | No restrictions                                                                                                                                                          |
| `medium`   | Likely correct but some ambiguity                     | Proceed, but note uncertainty in audit message                                                                                                                           |
| `low`      | Guessing — transcript is noisy, garbled, or ambiguous | **Never perform external or irreversible actions.** Escalate to draft/confirm. Treat as `INSTRUCTION_UNSURE` if it looked like an instruction, or archive-only otherwise |

Voice-to-text errors are common. A misheard word can completely change intent. When confidence is low, the cost of asking is always lower than the cost of acting wrongly.

## Step 3 — Check for duplicates

Before archiving or acting, check whether this memo has already been processed. The watcher writes an idempotency record for each processed memo at:

```
~/.local/state/apple-voice-assistant/processed/<memo_id>.json
```

Where `<memo_id>` is derived from the source filename (basename without extension). If a record already exists with the same `source_mtime` and `source_size_bytes`, skip this memo — it's a duplicate triggered by iCloud sync churn.

If no record exists, create one after Step 5 completes:

```json
{
  "memo_id": "20260419 083045",
  "source_filename": "20260419 083045.m4a",
  "source_mtime": 1745053845,
  "source_size_bytes": 234567,
  "category": "TODO_ADAM",
  "confidence": "high",
  "archive_path": "data/2026/04/19/08-30-45-grocery-list-for-saturday.md",
  "disposition": "created Apple Reminder",
  "processed_at": "2026-04-19T08:31:02Z"
}
```

## Step 4 — Archive the audio and transcript

Copy the raw audio and write a matching transcript file into this skill's `data/` tree. This gives a durable, greppable history independent of Voice Memos / iCloud.

See [`references/archive-format.md`](references/archive-format.md) for the full archive specification (directory layout, slug rules, transcript frontmatter fields, failure handling).

## Step 5 — Act on the category

Each state maps to a specific action. See [`references/actions.md`](references/actions.md) for the full action specification.

### Safety rules (apply to ALL states)

1. **Never send, post, or publish externally without confirmation.** Any action that sends a message to another person, creates a public GitHub issue outside this repo, posts to a channel, or emails — default to **draft + confirm**. This applies to `MESSAGE_DRAFT` by definition, but also to any `INSTRUCTION_DIRECT` that involves external communication. Voice memos are too easy to underspecify.

2. **Low confidence = no irreversible actions.** If confidence is `low`, do not execute instructions, create external resources, or send messages. Archive the transcript and ask the user for clarification.

3. **Never delete or move the source `.m4a`.** iCloud owns that lifecycle; archiving is always a copy.

## Step 6 — Audit trail

Every run must produce at least one message to the user so nothing disappears silently. Use whatever messaging channel the runtime provides (e.g. the primary notification channel configured in the host). Do not hardcode a specific channel.

The audit message should include: transcript summary, category, confidence, action taken, and archive path.

If an action fails (e.g. `gh` not authed, Reminders permission denied, archive write failed), send a message with the error and the raw transcript.

**If the message send itself fails** (network error, channel misconfigured, etc.), append a self-chase item to `TODO.md` at the root of this skill's directory:

```
- [ ] YYYY-MM-DD FOLLOW-UP — failed to notify user about memo. Archive: data/YYYY/MM/DD/HH-MM-SS-<slug>.md. Category: <STATE>. Confidence: <level>. Action taken: <summary or "none">. Error: <error>.
```

On every subsequent run, before Step 1, scan `TODO.md` for `FOLLOW-UP` items and include an "unresolved follow-ups" section in the audit message. Once the user has been told, strike the line through (`~~...~~`) rather than deleting it — keep the audit history.

## Guidance

- Treat the transcript as the source of truth. Don't re-interpret from the filename.
- Keep audit messages short — transcript summary + category + confidence + action taken + archive path.
- When writing GitHub issues or TODO lines, reference the archived transcript path (`data/YYYY/MM/DD/HH-MM-SS-<slug>.md`) rather than the original Voice Memos path — the archive is stable, the source may move or be deleted by iCloud.
- Don't ask for confirmation before running `INSTRUCTION_DIRECT` (that's what `INSTRUCTION_UNSURE` is for) — **unless** it involves external communication (see Safety rule 1).
- Always process the steps in order: load → classify → dedup → archive → act → audit. A failed archive never blocks the action step; a failed action never blocks the audit step.
