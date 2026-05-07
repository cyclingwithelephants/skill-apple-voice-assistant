# Action: MEMORY_NOTE

A fact to persist about a person, project, system, or preference. Write it to Hermes internal memory.

STATE_DIR: `~/.local/state/apple-voice-assistant`

---

## Non-negotiable confirmation requirement

The user requires an audit message every time a voice memo is processed, regardless of category or whether the action succeeded, failed, or only created a draft. Send it to the configured audit target (see `APPLE_VOICE_ASSISTANT_AUDIT_TARGET` env var). If delivery fails, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md` with enough detail to replay the missed confirmation later.

## Step 1: Write fact to Hermes memory

Extract the key fact from the transcript. Write it to Hermes internal memory using the memory tool.

- Write the fact in clear, direct language — not a paraphrase of the transcript
- The memory MUST be durable and retrievable in future conversations
- If the memory tool is unavailable, write the fact to `~/.local/state/apple-voice-assistant/TODO.md` as a FOLLOW-UP item noting that memory was unavailable

## Step 2: Update archive frontmatter

Update the YAML frontmatter in the archive file at `archive_path` (from the webhook payload) to add:

- `category: MEMORY_NOTE`
- `confidence: <high|medium|low>`
- `action_taken: <disposition summary>`

Read the file, insert the new fields before the closing `---`, and write it back.

## Step 3: Write processed JSON

Write this JSON to `~/.local/state/apple-voice-assistant/processed/<memo_id>.json`:

```json
{
  "memo_id": "<basename without extension>",
  "source_filename": "<original filename>",
  "source_mtime": "<source_mtime from webhook payload>",
  "source_size_bytes": "<source_size_bytes from webhook payload>",
  "category": "MEMORY_NOTE",
  "confidence": "<high|medium|low>",
  "archive_path": "<archive_path from webhook payload>",
  "disposition": "wrote fact to Hermes memory",
  "processed_at": "<ISO8601 timestamp>"
}
```

## Step: Audit

Send audit summary to the configured audit target.
If Matrix is unavailable, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md`.
Include: transcript summary, category, confidence, action taken, archive path.

## DONE
