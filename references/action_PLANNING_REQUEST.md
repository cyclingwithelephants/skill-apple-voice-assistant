# Action: PLANNING_REQUEST

User asks for a project plan, approach, design, migration outline, or implementation proposal rather than immediate execution.

STATE_DIR: `~/.local/state/apple-voice-assistant`

---

## Non-negotiable confirmation requirement

Adam wants a Matrix confirmation/audit message every time a voice memo is processed, regardless of category or whether the action succeeded, failed, or only created a draft. Send it to `matrix:!nSlDhIlsFlFubTCaWO:matrix.adamland.xyz`. If Matrix delivery fails, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md` with enough detail to replay the missed confirmation later.

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

## Step 3: Update archive frontmatter

Add:

- `category: PLANNING_REQUEST`
- `confidence: <high|medium|low>`
- `action_taken: created plan artifact at <path>`

## Step 4: Write processed JSON

Write `~/.local/state/apple-voice-assistant/processed/<memo_id>.json` with category `PLANNING_REQUEST` and disposition citing the plan path.

## Step 5: Audit

Send Matrix audit with the short recommendation, plan path, confidence, and archive path.

## DONE
