# Action: INSTRUCTION_DIRECT

A direct instruction to carry out now using available tools.

**Read [`action_COMMON.md`](action_COMMON.md) first** — it defines the audit requirement, archive frontmatter update, processed JSON write, and audit steps that apply to every state.

---

## Step 1: Check for external communication

Read the transcript. If the instruction involves any of:

- Sending a message to another person
- Posting to a public channel, Slack, Discord, Matrix (outbound)
- Creating a public GitHub issue or resource
- Sending email

STOP. Do NOT execute. Instead, draft the message and present it to the user for review via the audit channel. Never send without explicit confirmation.

## Step 2: Handle plan or design requests

If the direct instruction asks for a plan, design, proposal, architecture, implementation outline, migration approach, investigation write-up, or similar markdown-style deliverable, create a concrete Markdown artifact under `STATE_DIR` instead of only summarizing the answer in chat or audit.

Before writing the artifact, perform lightweight local discovery when relevant to the request:

- Read nearby repo files, existing notes, local state, or configuration that materially affects the plan
- Keep discovery bounded to what is needed for a useful plan
- Do not perform external research unless the user explicitly asked for it and it does not violate Step 1

Write the artifact to:

```text
~/.local/state/apple-voice-assistant/artifacts/<memo_id>-<short-slug>.md
```

The artifact should be concrete enough to act on later. Include title, source memo id, user request summary, proposed approach, ordered implementation steps, risks/open questions, and verification checks.

Continue to Step 4 after writing the artifact.

## Step 3: Execute other direct instructions

If Step 2 does not apply, use your available tools to carry out the instruction.

- Execute exactly what was asked — do not broaden scope
- If you hit a blocker or the instruction is ambiguous, STOP and send the user a message explaining the issue

## Step 4: Common steps

Follow **Update archive frontmatter**, **Write processed JSON**, and **Audit** from [`action_COMMON.md`](action_COMMON.md). For plan/design requests, cite the artifact path in `action_taken` and `disposition`.

## DONE
