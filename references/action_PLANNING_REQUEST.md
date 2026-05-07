# Action: PLANNING_REQUEST

User asks for a project plan, approach, design, migration outline, or implementation proposal rather than immediate execution.

**Read [`action_COMMON.md`](action_COMMON.md) first** — it defines the audit requirement, archive frontmatter update, processed JSON write, and audit steps that apply to every state.

---

## Step 1: Do bounded discovery

Read local repo/files/notes/config that materially affect the plan. Keep discovery bounded. Use web research only if explicitly requested or essential.

## Step 2: Write plan artifact

Create:

```text
~/.local/state/apple-voice-assistant/plans/<memo_id>-<short-slug>.md
```

Include:

- source memo id and request summary
- relevant discovery findings
- assumptions/open questions
- recommended approach
- ordered implementation steps
- risks/trade-offs
- verification/acceptance checks

## Step 3: Common steps

Follow **Update archive frontmatter**, **Write processed JSON**, and **Audit** from [`action_COMMON.md`](action_COMMON.md). Cite the plan artifact path in `action_taken` and `disposition`.

## DONE
