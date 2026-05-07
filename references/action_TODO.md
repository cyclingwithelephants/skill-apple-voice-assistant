# Action: TODO

A task to capture. Try to create an Apple Reminder (best-effort), then always log to TODO.md.

STATE_DIR: `~/.local/state/apple-voice-assistant`

---

## Non-negotiable confirmation requirement

Adam wants a Matrix confirmation/audit message every time a voice memo is processed, regardless of category or whether the action succeeded, failed, or only created a draft. Send it to `matrix:!nSlDhIlsFlFubTCaWO:matrix.adamland.xyz`. If Matrix delivery fails, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md` with enough detail to replay the missed confirmation later.

## Step 1: Try Apple Reminder via remindctl (best-effort)

**Apple Reminders may be unavailable from daemon/webhook contexts** (Mach error 4099 — the system LaunchDaemon cannot reach the user-session Reminders XPC service). Treat this step as best-effort. If it fails, log the error and continue to Step 2.

Run this command, substituting the placeholders:

```bash
/opt/homebrew/bin/remindctl add --title "<title>" --notes "<full transcript>"
```

If the memo mentions a due date, add `--due <date>`:

```bash
/opt/homebrew/bin/remindctl add --title "<title>" --due "<YYYY-MM-DD>" --notes "<full transcript>"
```

- `title`: descriptive title that preserves the key context from the memo — include the what, who, and why so the reminder is actionable without re-reading the transcript. Aim for 8-15 words. (e.g. "Compare CI node CPU allocation: fewer full-CPU vs more small-CPU nodes")
- `notes`: the **full verbatim transcript** from the webhook payload — this is the reminder's description/body so the user can see exactly what they said
- `due`: **must be `YYYY-MM-DD` format only** — natural language dates are unreliable
- DO NOT specify a list — use the default list
- Use the absolute path `/opt/homebrew/bin/remindctl` — Homebrew is not on PATH in daemon contexts

If remindctl fails for any reason, do NOT retry. Log the error and continue to Step 2.

## Step 2: Append to TODO.md (always)

This step runs regardless of whether Step 1 succeeded. TODO.md is the reliable record.

Append one line to `~/.local/state/apple-voice-assistant/TODO.md`:

```
- [ ] YYYY-MM-DD <short title> — <one-line context>. Archive: <archive_path>
```

- `title`: same descriptive title as the Reminder
- `one-line context`: who, when, why — enough to act on later without re-reading the transcript

If `~/.local/state/apple-voice-assistant/TODO.md` does not exist, create it before appending.

## Step 3: Update archive frontmatter

Update the YAML frontmatter in the archive file at `archive_path` (from the webhook payload) to add:

- `category: TODO`
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
  "category": "TODO",
  "confidence": "<high|medium|low>",
  "archive_path": "<archive_path from webhook payload>",
  "disposition": "created Apple Reminder + appended to TODO.md",
  "processed_at": "<ISO8601 timestamp>"
}
```

## Step: Audit

Send audit summary to Matrix room `matrix:!nSlDhIlsFlFubTCaWO:matrix.adamland.xyz`.
If Matrix is unavailable, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md`.
Include: transcript summary, category, confidence, action taken, archive path.

## DONE
