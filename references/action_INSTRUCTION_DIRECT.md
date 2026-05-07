# Action: INSTRUCTION_DIRECT

A direct instruction to carry out now using available tools.

STATE_DIR: `~/.local/state/apple-voice-assistant`

---

## Non-negotiable confirmation requirement

The user requires an audit message every time a voice memo is processed, regardless of category or whether the action succeeded, failed, or only created a draft. Send it to the configured audit target (see `APPLE_VOICE_ASSISTANT_AUDIT_TARGET` env var). If delivery fails, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md` with enough detail to replay the missed confirmation later.

## Step 1: Check for external communication

Read the transcript. If the instruction involves any of:

- Sending a message to another person
- Posting to a public channel, Slack, Discord, Matrix (outbound)
- Creating a public GitHub issue or resource
- Sending email

STOP. Do NOT execute. Instead, draft the message and present it to the user for review via Matrix. Never send without explicit confirmation.

## Step 2: Handle plan or design requests

If the direct instruction asks for a plan, design, proposal, architecture, implementation outline, migration approach, investigation write-up, or similar markdown-style deliverable, create a concrete Markdown artifact under `STATE_DIR` instead of only summarizing the answer in chat or audit.

Before writing the artifact, perform lightweight local discovery when relevant to the request:

- Read nearby repo files, existing notes, local state, or configuration that materially affects the plan
- Prefer targeted commands such as `rg`, `rg --files`, `sed`, `ls`, `find`, or existing project scripts
- Keep discovery bounded to what is needed for a useful plan
- Do not perform external research unless the user explicitly asked for it and it does not violate Step 1
- If local discovery is blocked or unnecessary, note that in the artifact

Write the artifact to a deterministic path under `STATE_DIR`, for example:

```text
~/.local/state/apple-voice-assistant/artifacts/<memo_id>-<short-slug>.md
```

The artifact should be concrete enough to act on later. Include, as applicable:

- Title and source memo id
- User request summary
- Relevant local discovery findings
- Proposed approach or design
- Ordered implementation steps
- Risks, open questions, or assumptions
- Verification or acceptance checks

Set `action_taken` and the processed JSON `disposition` to cite the artifact path, for example:

```text
created plan artifact at ~/.local/state/apple-voice-assistant/artifacts/<memo_id>-<short-slug>.md
```

Continue to Step 4 and Step 5 after writing the artifact. Do not skip archive, processed JSON, or audit.

## Step 3: Execute other direct instructions

If Step 2 does not apply, use your available tools (bash, read, write, etc.) to carry out the instruction.

- Execute exactly what was asked — do not broaden scope
- If you hit a blocker or the instruction is ambiguous, STOP and send the user a message explaining the issue

## Step 4: Update archive frontmatter

Update the YAML frontmatter in the archive file at `archive_path` (from the webhook payload) to add:

- `category: INSTRUCTION_DIRECT` (the classification from Step 2)
- `confidence: <high|medium|low>`
- `action_taken: <disposition summary>`

Read the file, insert the new fields before the closing `---`, and write it back.

For plan or design requests, `action_taken` MUST cite the artifact path created in Step 2.

## Step 5: Write processed JSON

Write this JSON to `~/.local/state/apple-voice-assistant/processed/<memo_id>.json`:

```json
{
  "memo_id": "<basename without extension>",
  "source_filename": "<original filename>",
  "source_mtime": "<source_mtime from webhook payload>",
  "source_size_bytes": "<source_size_bytes from webhook payload>",
  "category": "INSTRUCTION_DIRECT",
  "confidence": "<high|medium|low>",
  "archive_path": "<archive_path from webhook payload>",
  "disposition": "<what you did, or 'drafted message for user review'>",
  "processed_at": "<ISO8601 timestamp>"
}
```

For plan or design requests, `disposition` MUST cite the artifact path created in Step 2.

## Step: Audit

Send audit summary to the configured audit target.
If Matrix is unavailable, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md`.
Include: transcript summary, category, confidence, action taken, archive path.

## DONE
