# Classification Examples

Worked examples for Step 2 of the skill. This file grows over time as the teaching loop (`INSTRUCTION`) proposes new patterns.

## Clear cases

| Transcript snippet                                                    | State                | Confidence | Why                                                               |
| --------------------------------------------------------------------- | -------------------- | ---------- | ----------------------------------------------------------------- |
| "Remind me to call the dentist on Thursday"                           | `REMINDER_OR_ALARM`      | high       | Explicit reminder with time sensitivity                            |
| "Can you set up a cron job to back up the database every night"       | `IMPLEMENTATION_TASK`    | high       | Clear build/config directive to execute                            |
| "You should always treat YAML changes in the helm chart as high-risk" | `INSTRUCTION`            | high       | Teaching a new rule for this skill or the assistant's behavior      |
| "Can you look into why the deploy failed last night"                  | `RESEARCH_REQUEST`       | high       | "Look into" = research task, not immediate investigation            |
| "Remember that carrot's ZFS pool is mirrored, not striped"            | `MEMORY_NOTE`            | high       | Concrete fact about infrastructure — persist it                     |
| "What if we built a CLI that wraps kubectl with project defaults"     | `IDEA_CAPTURE`           | high       | Product/project idea, not an instruction to build it now            |
| "Buy milk, eggs, and bread"                                           | `REMINDER_OR_ALARM`      | high       | Shopping list/list item capture                                     |
| "Tell Sarah I'll be late to dinner"                                   | `EXTERNAL_MESSAGE_DRAFT` | high       | External comms — draft only; needs explicit confirmation            |
| "How do I open Safari Reading List?"                                  | `QUESTION_ANSWER`        | high       | User wants an explanation/answer                                    |
| "Make a plan for a shared voice app interface"                        | `PLANNING_REQUEST`       | high       | Planning/design deliverable, not immediate implementation           |
| "Something about the deploy... I dunno, look at it when you can"      | `TODO`                   | medium     | Vague, but clearly a task to capture; legacy fallback is acceptable |

## Ambiguous cases

| Transcript snippet                                       | State              | Confidence | Why                                                                                   |
| -------------------------------------------------------- | ------------------ | ---------- | ------------------------------------------------------------------------------------- |
| "Fix the nginx config"                                   | `UNKNOWN`          | medium     | Could be direct instruction, but which config? What's broken? Ambiguous scope → ask   |
| "We need to migrate to the new API"                      | `UNKNOWN`          | low        | "We" is ambiguous — is this an instruction or a thought? Low confidence, ask the user |
| "I think the auth service might be leaking tokens"       | `RESEARCH_REQUEST` | medium     | Not a direct instruction — sounds like a concern to investigate                       |
| "Oh also, my birthday is March 12th"                     | `MEMORY_NOTE`      | high       | Concrete fact about the user                                                          |
| "Hmm, maybe we should switch to Postgres"                | `IDEA_CAPTURE`     | medium     | Speculative — capture the idea, don't act on it                                       |
| "I was thinking about how life has been going lately..." | `UNKNOWN`          | low        | Raw reflection, no actionable content — ask user what to do                           |
| "[garbled audio with background noise]"                  | `UNKNOWN`          | low        | Can't determine intent — message the user                                             |

## Edge cases and biases

| Scenario                                                       | Rule                                                               |
| -------------------------------------------------------------- | ------------------------------------------------------------------ |
| Sounds like an instruction but scope is unclear                | `UNKNOWN` over action categories — ask first                         |
| A fact embedded inside a rambling reflection                   | `MEMORY_NOTE` — extract the fact                                      |
| "Can you send X to Y"                                          | `EXTERNAL_MESSAGE_DRAFT` — draft only; needs explicit confirmation    |
| Memo mentions deletion, financial action, or messaging someone | Apply safety rules; ask/confirm before irreversible external action   |
| Reminder, alarm, shopping-list, or groceries phrasing          | `REMINDER_OR_ALARM`                                                   |
| "How do I..." / "What is..." / "Explain..."                  | `QUESTION_ANSWER`                                                     |
| "Build/fix/create/test/deploy..."                              | `IMPLEMENTATION_TASK` if scope is clear                               |
| "Plan/design/outline an approach..."                           | `PLANNING_REQUEST`                                                    |
| Genuinely no signal — garbled, extremely short, or pure noise  | `UNKNOWN` — message the user                                          |
| "Add a rule that..." or "from now on..."                       | `INSTRUCTION` — user is teaching the skill                            |
