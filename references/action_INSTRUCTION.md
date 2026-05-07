# Action: INSTRUCTION

The user is teaching a new rule, pattern, or example for this skill. Record it as a proposal for later review.

STATE_DIR: `~/.local/state/apple-voice-assistant`

---

## Non-negotiable confirmation requirement

The user requires an audit message every time a voice memo is processed, regardless of category or whether the action succeeded, failed, or only created a draft. Send it to the configured audit target (see `APPLE_VOICE_ASSISTANT_AUDIT_TARGET` env var). If delivery fails, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md` with enough detail to replay the missed confirmation later.

## Step 1: Check for duplicate proposals

Read `~/.local/state/apple-voice-assistant/PROPOSALS.md` if it exists. Scan existing entries for similar title or transcript. If a near-duplicate exists, append a note to that existing entry instead of creating a new one.

## Step 2: Append proposal to PROPOSALS.md

Append to `~/.local/state/apple-voice-assistant/PROPOSALS.md` (NOT the skill root — that is a read-only nix store path):

```markdown
## YYYY-MM-DD — <one-line title of the rule>

**Transcript**: <full transcript>

**Interpretation**: <what the rule means>

**Suggested change**:
<concrete patch or new example row targeting SKILL.md or references/classification-examples.md>

**Archive**: <archive path>
**Status**: pending
```

Include all five fields:

- `title`: one-line summary of the proposed rule
- `transcript`: the full memo transcript verbatim
- `interpretation`: your understanding of what the rule means
- `suggested change`: a concrete patch or example — NOT just a location reference
- `archive link`: the archive path from the webhook payload

If `~/.local/state/apple-voice-assistant/PROPOSALS.md` does not exist, create it before appending.

## Step 3: Update archive frontmatter

Update the YAML frontmatter in the archive file at `archive_path` (from the webhook payload) to add:

- `category: INSTRUCTION`
- `confidence: <high|medium|low>`
- `action_taken: <disposition summary>`

Read the file, insert the new fields before the closing `---`, and write it back.

## Step 4: Write processed JSON

Write this JSON to `~/.local/state/apple-voice-assistant/processed/<memo_id>.json`:

```json
{
  "memo_id": "<basename without extension>",
  "source_filename": "<original filename>",
  "source_mtime": "<source_mtime from webhook payload>",
  "source_size_bytes": "<source_size_bytes from webhook payload>",
  "category": "INSTRUCTION",
  "confidence": "<high|medium|low>",
  "archive_path": "<archive_path from webhook payload>",
  "disposition": "appended proposal to PROPOSALS.md",
  "processed_at": "<ISO8601 timestamp>"
}
```

## Step: Audit

Send audit summary to the configured audit target.
If Matrix is unavailable, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md`.
Include: transcript summary, category, confidence, action taken, archive path.

## DONE
