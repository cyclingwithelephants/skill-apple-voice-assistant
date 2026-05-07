# Action: QUESTION_ANSWER

User asks a factual, how-to, or explanatory question.

STATE_DIR: `~/.local/state/apple-voice-assistant`

---

## Non-negotiable confirmation requirement

The user requires an audit message every time a voice memo is processed, regardless of category or whether the action succeeded, failed, or only created a draft. Send it to the configured audit target (see `APPLE_VOICE_ASSISTANT_AUDIT_TARGET` env var). If delivery fails, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md` with enough detail to replay the missed confirmation later.

## Step 1: Answer the question

Answer directly and concisely. Use tools when the answer depends on current facts, files, system state, arithmetic, or anything that needs grounding.

If the transcript is ambiguous, answer the likely question and flag uncertainty; if too ambiguous, reclassify as `UNKNOWN` instead.

## Step 2: Update archive frontmatter

Add:

- `category: QUESTION_ANSWER`
- `confidence: <high|medium|low>`
- `action_taken: answered question in Matrix audit`

## Step 3: Write processed JSON

Write `~/.local/state/apple-voice-assistant/processed/<memo_id>.json` with category `QUESTION_ANSWER` and disposition `answered question in Matrix audit`.

## Step 4: Audit

Send the answer to Matrix. Include confidence and archive path after the answer.

## DONE
