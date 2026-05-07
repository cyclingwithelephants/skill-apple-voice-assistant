# Action: EXTERNAL_MESSAGE_DRAFT

User wants a message drafted for another person or external channel.

**Read [`action_COMMON.md`](action_COMMON.md) first** — it defines the audit requirement, archive frontmatter update, processed JSON write, and audit steps that apply to every state.

---

## Step 1: Draft only

Extract:

- recipient/person/channel if stated
- proposed message text
- target platform if stated
- any ambiguity or missing details

Do **not** send, post, email, or publish. Do **not** use external messaging tools except to send the draft to the user for confirmation via the configured audit channel.

## Step 2: Store pending confirmation

Append one line to `~/.local/state/apple-voice-assistant/TODO.md`:

```text
- [ ] YYYY-MM-DD EXTERNAL DRAFT — <recipient/platform>: "<draft>" Needs explicit confirmation before sending. Archive: <archive_path>
```

## Step 3: Common steps

Follow **Update archive frontmatter**, **Write processed JSON**, and **Audit** from [`action_COMMON.md`](action_COMMON.md). Send the user the draft and explicitly say it was **not sent**. Include recipient/platform, confidence, and archive path.

## DONE
