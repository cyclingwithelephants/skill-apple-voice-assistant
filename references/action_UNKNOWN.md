# Action: UNKNOWN

No clear intent, ambiguous instruction, or low confidence. Message the user for clarification.

**Read [`action_COMMON.md`](action_COMMON.md) first** — it defines the audit requirement, archive frontmatter update, processed JSON write, and audit steps that apply to every state.

---

## Step 1: Send user the full transcript

Send the user a message that includes:

- The full transcript quoted verbatim
- A statement that you could not confidently classify it
- Your best-guess classification (if any) and the reason for uncertainty

Example format:

```
Could not classify this memo. Full transcript:

"<verbatim transcript>"

Best guess: TODO (medium confidence) — sounds like a task but unclear who should do it.

How should I handle this? Reply with instructions.
```

If you have no plausible guess, omit the best-guess line entirely. DO NOT fabricate a classification.

## Step 2: Ask what to do

Your message MUST end with a clear question asking the user what to do with this memo.

DO NOT take any action beyond sending the message and writing the processed JSON.

## Step 3: Common steps

Follow **Update archive frontmatter**, **Write processed JSON**, and **Audit** from [`action_COMMON.md`](action_COMMON.md).

## DONE
