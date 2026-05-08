# Action: UNKNOWN

No clear intent, ambiguous instruction, or low confidence. Message the user for clarification.

STATE_DIR: `~/.local/state/apple-voice-assistant`

---

## Non-negotiable confirmation requirement

The user wants a Matrix confirmation/audit message every time a voice memo is processed, regardless of category or whether the action succeeded, failed, or only created a draft. Send it to the audit target configured in `APPLE_VOICE_ASSISTANT_AUDIT_TARGET`. If Matrix delivery fails, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md` with enough detail to replay the missed confirmation later.

## Step 1: Send user the full transcript

Send the user a message that includes:

- The full transcript quoted verbatim
- A statement that you could not confidently classify it
- Your best-guess classification (if any) and the reason for uncertainty

Example format:

```
Could not classify this memo. Full transcript:

"<verbatim transcript>"

Best guess: TODO (medium confidence) — sounds like a task but unclear who should do it.

How should I handle this? Reply with instructions.
```

If you have no plausible guess, omit the best-guess line entirely. DO NOT fabricate a classification.

## Step 2: Ask what to do

Your message MUST end with a clear question asking the user what to do with this memo.

DO NOT take any action beyond sending the message and writing the processed JSON.

## Step 3: Update archive frontmatter

Update the YAML frontmatter in the archive file at `archive_path` (from the webhook payload) to add:

- `category: UNKNOWN`
- `confidence: <high|medium|low>`
- `action_taken: <disposition summary>`

Read the file, insert the new fields before the closing `---`, and write it back.

## Step 4: Write processed JSON

Write this JSON to `~/.local/state/apple-voice-assistant/processed/<memo_id>.json`:

```json
{
  "memo_id": "<basename without extension>",
  "source_filename": "<original filename>",
  "source_mtime": "<source_mtime from webhook payload>",
  "source_size_bytes": "<source_size_bytes from webhook payload>",
  "category": "UNKNOWN",
  "confidence": "<high|medium|low>",
  "archive_path": "<archive_path from webhook payload>",
  "disposition": "sent transcript to user for clarification",
  "processed_at": "<ISO8601 timestamp>"
}
```

## Step: Audit

Send audit summary to the Matrix room configured in `APPLE_VOICE_ASSISTANT_AUDIT_TARGET`.
If Matrix is unavailable, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md`.
Include: transcript summary, category, confidence, action taken, archive path.

## DONE
