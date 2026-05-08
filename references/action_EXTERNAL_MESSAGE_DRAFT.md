# Action: EXTERNAL_MESSAGE_DRAFT

User wants a message drafted for another person or external channel.

STATE_DIR: `~/.local/state/apple-voice-assistant`

---

## Non-negotiable confirmation requirement

The user wants a Matrix confirmation/audit message every time a voice memo is processed, regardless of category or whether the action succeeded, failed, or only created a draft. Send it to the audit target configured in `APPLE_VOICE_ASSISTANT_AUDIT_TARGET`. If Matrix delivery fails, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md` with enough detail to replay the missed confirmation later.

## Step 1: Draft only

Extract:

- recipient/person/channel if stated
- proposed message text
- target platform if stated
- any ambiguity or missing details

Do **not** send, post, email, or publish. Do **not** use external messaging tools except to send the draft to the user for confirmation in Matrix.

## Step 2: Store pending confirmation

Append one line to `~/.local/state/apple-voice-assistant/TODO.md`:

```text
- [ ] YYYY-MM-DD EXTERNAL DRAFT — <recipient/platform>: “<draft>” Needs explicit confirmation before sending. Archive: <archive_path>
```

## Step 3: Update archive frontmatter

Add:

- `category: EXTERNAL_MESSAGE_DRAFT`
- `confidence: <high|medium|low>`
- `action_taken: drafted message only; awaiting explicit confirmation`

## Step 4: Write processed JSON

Write `~/.local/state/apple-voice-assistant/processed/<memo_id>.json` with category `EXTERNAL_MESSAGE_DRAFT` and disposition `drafted message only; awaiting explicit confirmation`.

## Step 5: Audit

Send the user the draft and explicitly say it was **not sent**. Include recipient/platform, confidence, and archive path.

## DONE
