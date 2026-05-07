# Action: IMPLEMENTATION_TASK

User asks you to build, change, fix, test, or generate a concrete artifact now.

**Read [`action_COMMON.md`](action_COMMON.md) first** — it defines the audit requirement, archive frontmatter update, processed JSON write, and audit steps that apply to every state.

---

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

## Step 3: Common steps

Follow **Update archive frontmatter**, **Write processed JSON**, and **Audit** from [`action_COMMON.md`](action_COMMON.md). Include what changed, verification result or blocker, and artifact path.

## DONE
