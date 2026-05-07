# Action: QUESTION_ANSWER

User asks a factual, how-to, or explanatory question.

**Read [`action_COMMON.md`](action_COMMON.md) first** — it defines the audit requirement, archive frontmatter update, processed JSON write, and audit steps that apply to every state.

---

## Step 1: Answer the question

Answer directly and concisely. Use tools when the answer depends on current facts, files, system state, arithmetic, or anything that needs grounding.

If the transcript is ambiguous, answer the likely question and flag uncertainty; if too ambiguous, reclassify as `UNKNOWN` instead.

## Step 2: Common steps

Follow **Update archive frontmatter**, **Write processed JSON**, and **Audit** from [`action_COMMON.md`](action_COMMON.md). Send the answer as the audit message body.

## DONE
