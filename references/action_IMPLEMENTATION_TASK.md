# Action: IMPLEMENTATION_TASK

User asks you to build, change, fix, test, or generate a concrete artifact now.

STATE_DIR: `~/.local/state/apple-voice-assistant`

---

## Non-negotiable confirmation requirement

The user wants a Matrix confirmation/audit message every time a voice memo is processed, regardless of category or whether the action succeeded, failed, or only created a draft. Send it to the audit target configured in `APPLE_VOICE_ASSISTANT_AUDIT_TARGET`. If Matrix delivery fails, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md` with enough detail to replay the missed confirmation later.

## Step 1: Bound the task

Identify the requested artifact/change and likely working directory. Do not broaden scope beyond the memo. If the task requires external sending/posting/publishing, stop and use `EXTERNAL_MESSAGE_DRAFT` safety behavior instead.

## Step 2: Implement using tools

Use available tools to make the requested change or artifact. For repo/code/config work:

- inspect relevant files first
- edit through the appropriate repo/config workflow
- run targeted verification when practical
- if blocked, capture the exact blocker and next step

For generated local artifacts, write under:

```text
~/.local/state/apple-voice-assistant/artifacts/<memo_id>-<short-slug>.<ext>
```

## Step 3: Update archive frontmatter

Add:

- `category: IMPLEMENTATION_TASK`
- `confidence: <high|medium|low>`
- `action_taken: <summary, including artifact path/PR/test result/blocker>`

## Step 4: Write processed JSON

Write `~/.local/state/apple-voice-assistant/processed/<memo_id>.json` with category `IMPLEMENTATION_TASK` and disposition matching the implementation result.

## Step 5: Audit

Send Matrix audit with what changed, verification result or blocker, confidence, and archive path.

## DONE
