# Action: INSTRUCTION

The user is teaching a new rule, pattern, or example for this skill. Record it as a proposal for later review.

**Read [`action_COMMON.md`](action_COMMON.md) first** — it defines the audit requirement, archive frontmatter update, processed JSON write, and audit steps that apply to every state.

---

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

If `~/.local/state/apple-voice-assistant/PROPOSALS.md` does not exist, create it before appending.

## Step 3: Common steps

Follow **Update archive frontmatter**, **Write processed JSON**, and **Audit** from [`action_COMMON.md`](action_COMMON.md).

## DONE
