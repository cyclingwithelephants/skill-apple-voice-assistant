# Action: RESEARCH_REQUEST

"Look into X" — file a research task. DO NOT start the research now.

STATE_DIR: `~/.local/state/apple-voice-assistant`

---

## Non-negotiable confirmation requirement

The user wants a Matrix confirmation/audit message every time a voice memo is processed, regardless of category or whether the action succeeded, failed, or only created a draft. Send it to the audit target configured in `APPLE_VOICE_ASSISTANT_AUDIT_TARGET`. If Matrix delivery fails, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md` with enough detail to replay the missed confirmation later.

## Step 1: Append research item to TODO.md

Append one line to `~/.local/state/apple-voice-assistant/TODO.md`:

```
- [ ] YYYY-MM-DD [research] <topic> — <one-line context>. Archive: data/YYYY/MM/DD/HH-MM-SS-<slug>.md
```

- `[research]`: MUST include this prefix exactly, for filtering
- `topic`: the subject to research, derived from the transcript
- `one-line context`: why the user wants this researched, if stated
- `archive path`: the path written in Step 4 (not the Voice Memos source path)

If `~/.local/state/apple-voice-assistant/TODO.md` does not exist, create it before appending.

DO NOT start the research. DO NOT open any URLs. DO NOT run any searches. File the task only.

## Step 2: Update archive frontmatter

Update the YAML frontmatter in the archive file at `archive_path` (from the webhook payload) to add:

- `category: RESEARCH_REQUEST` (the classification from Step 2)
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
  "category": "RESEARCH_REQUEST",
  "confidence": "<high|medium|low>",
  "archive_path": "<archive_path from webhook payload>",
  "disposition": "appended [research] item to TODO.md",
  "processed_at": "<ISO8601 timestamp>"
}
```

## Step: Audit

Send audit summary to the Matrix room configured in `APPLE_VOICE_ASSISTANT_AUDIT_TARGET`.
If Matrix is unavailable, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md`.
Include: transcript summary, category, confidence, action taken, archive path.

## DONE
