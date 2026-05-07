# Action: MEMORY_NOTE

A fact to persist about a person, project, system, or preference. Write it to Hermes internal memory.

**Read [`action_COMMON.md`](action_COMMON.md) first** — it defines the audit requirement, archive frontmatter update, processed JSON write, and audit steps that apply to every state.

---

## Step 1: Write fact to Hermes memory

Extract the key fact from the transcript. Write it to Hermes internal memory using the memory tool.

- Write the fact in clear, direct language — not a paraphrase of the transcript
- The memory MUST be durable and retrievable in future conversations
- If the memory tool is unavailable, write the fact to `~/.local/state/apple-voice-assistant/TODO.md` as a FOLLOW-UP item noting that memory was unavailable

## Step 2: Common steps

Follow **Update archive frontmatter**, **Write processed JSON**, and **Audit** from [`action_COMMON.md`](action_COMMON.md).

## DONE
