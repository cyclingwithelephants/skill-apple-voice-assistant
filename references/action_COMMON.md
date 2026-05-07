# Common steps for all action files

These steps apply to every classification state. Each `action_<STATE>.md` file references this file for shared boilerplate.

STATE_DIR: `~/.local/state/apple-voice-assistant`

---

## Audit requirement

The user requires an audit message every time a voice memo is processed, regardless of category or whether the action succeeded, failed, or only created a draft. Send it to the configured audit target (see `APPLE_VOICE_ASSISTANT_AUDIT_TARGET` env var). If delivery fails, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md` with enough detail to replay the missed confirmation later.

## Update archive frontmatter

Update the YAML frontmatter in the archive file at `archive_path` (from the webhook payload) to add:

- `category: <STATE>` — the classification from Step 2
- `confidence: <high|medium|low>`
- `action_taken: <disposition summary>` — fill in after the action completes

Read the file, insert the new fields before the closing `---`, and write it back.

## Write processed JSON

Write this JSON to `~/.local/state/apple-voice-assistant/processed/<memo_id>.json`:

```json
{
  "memo_id": "<basename without extension>",
  "source_filename": "<original filename>",
  "source_mtime": "<source_mtime from webhook payload>",
  "source_size_bytes": "<source_size_bytes from webhook payload>",
  "category": "<STATE>",
  "confidence": "<high|medium|low>",
  "archive_path": "<archive_path from webhook payload>",
  "disposition": "<what was done>",
  "processed_at": "<ISO8601 timestamp>"
}
```

## Audit

Send audit summary to the configured audit target.
If the audit channel is unavailable, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md`.
Include: transcript summary, category, confidence, action taken, archive path.
