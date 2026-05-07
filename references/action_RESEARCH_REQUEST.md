# Action: RESEARCH_REQUEST

"Look into X" — file a research task. DO NOT start the research now.

**Read [`action_COMMON.md`](action_COMMON.md) first** — it defines the audit requirement, archive frontmatter update, processed JSON write, and audit steps that apply to every state.

---

## Step 1: Append research item to TODO.md

Append one line to `~/.local/state/apple-voice-assistant/TODO.md`:

```
- [ ] YYYY-MM-DD [research] <topic> — <one-line context>. Archive: data/YYYY/MM/DD/HH-MM-SS-<slug>.md
```

- `[research]`: MUST include this prefix exactly, for filtering
- `topic`: the subject to research, derived from the transcript
- `one-line context`: why the user wants this researched, if stated
- `archive path`: the path from the webhook payload

If `~/.local/state/apple-voice-assistant/TODO.md` does not exist, create it before appending.

DO NOT start the research. DO NOT open any URLs. DO NOT run any searches. File the task only.

## Step 2: Common steps

Follow **Update archive frontmatter**, **Write processed JSON**, and **Audit** from [`action_COMMON.md`](action_COMMON.md).

## DONE
