# Classification Examples

Worked examples for Step 2 of the skill. This file grows over time as the teaching loop (`INSTRUCTION_ADD`) proposes new patterns.

## Clear cases

| Transcript snippet                                                    | State                | Confidence | Why                                                                 |
| --------------------------------------------------------------------- | -------------------- | ---------- | ------------------------------------------------------------------- |
| "Remind me to call the dentist on Thursday"                           | `TODO_ADAM`          | high       | Explicit "remind me" = user's own task                              |
| "Can you set up a cron job to back up the database every night"       | `INSTRUCTION_DIRECT` | high       | Clear directive to the assistant                                    |
| "You should always treat YAML changes in the helm chart as high-risk" | `INSTRUCTION_ADD`    | high       | Teaching a new rule for this skill or the assistant's behavior      |
| "Can you look into why the deploy failed last night"                  | `RESEARCH_REQUEST`   | high       | "Look into" = research, not immediate action                        |
| "Remember that carrot's ZFS pool is mirrored, not striped"            | `MEMORY_NOTE`        | high       | Concrete fact about infrastructure — persist it                     |
| "I was thinking about how life has been going lately..."              | `JOURNAL_NOTE`       | high       | Raw reflection, no actionable content                               |
| "What if we built a CLI that wraps kubectl with project defaults"     | `IDEA_CAPTURE`       | high       | Product/project idea, not an instruction to build it now            |
| "Tell Sarah I'll be late to dinner"                                   | `MESSAGE_DRAFT`      | high       | "Tell someone" = message draft, **never** send without confirmation |
| "Just save this, I want a record of what happened at the meeting"     | `TRANSCRIBE_ONLY`    | high       | Explicit "just save this"                                           |
| "Buy milk, eggs, and bread"                                           | `TODO_ADAM`          | high       | Shopping list = user's own task                                     |

## Ambiguous cases

| Transcript snippet                                               | State                | Confidence | Why                                                                                    |
| ---------------------------------------------------------------- | -------------------- | ---------- | -------------------------------------------------------------------------------------- |
| "Fix the nginx config"                                           | `INSTRUCTION_UNSURE` | medium     | Could be direct instruction, but which config? What's broken? Ambiguous scope → UNSURE |
| "We need to migrate to the new API"                              | `INSTRUCTION_UNSURE` | low        | "We" is ambiguous — is this an instruction or a thought? Low confidence, do not act    |
| "I think the auth service might be leaking tokens"               | `RESEARCH_REQUEST`   | medium     | Not a direct instruction — sounds like a concern to investigate                        |
| "Something about the deploy... I dunno, look at it when you can" | `TODO_ASSISTANT`     | medium     | Vague, but clearly delegated ("you... when you can")                                   |
| "Oh also, Adam's birthday is March 12th"                         | `MEMORY_NOTE`        | high       | Concrete fact about a person                                                           |
| "Hmm, maybe we should switch to Postgres"                        | `IDEA_CAPTURE`       | medium     | Speculative — capture the idea, don't act on it                                        |
| "Send... actually never mind, just save this"                    | `TRANSCRIBE_ONLY`    | high       | User explicitly corrected themselves                                                   |
| "[garbled audio with background noise]"                          | `UNKNOWN`            | low        | Can't determine intent — feeds the classification training pipeline                    |

## Edge cases and biases

| Scenario                                                       | Rule                                                               |
| -------------------------------------------------------------- | ------------------------------------------------------------------ |
| Sounds like an instruction but scope is unclear                | `INSTRUCTION_UNSURE` over `INSTRUCTION_DIRECT`                     |
| Unclear whether user or assistant should do it                 | `TODO_ADAM` over `TODO_ASSISTANT`                                  |
| A fact embedded inside a rambling reflection                   | `MEMORY_NOTE` over `JOURNAL_NOTE` — extract the fact               |
| "Can you send X to Y"                                          | `MESSAGE_DRAFT` — **always** draft, never send                     |
| Memo mentions deletion, financial action, or messaging someone | Even if `INSTRUCTION_DIRECT`, apply Safety rule 1: draft + confirm |
| Genuinely no signal — garbled, extremely short, or pure noise  | `UNKNOWN` — this is what the training pipeline is for              |
| User says "just a thought" or "thinking out loud"              | `JOURNAL_NOTE` unless a concrete fact or idea is embedded          |
| "Add a rule that..." or "from now on..."                       | `INSTRUCTION_ADD` — user is teaching the skill                     |
