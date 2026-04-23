# Actions by State

What to do for each classification state. All actions are subject to the safety rules in SKILL.md Step 5.

## `INSTRUCTION_DIRECT`

Carry out the instruction using your normal tool set (bash, read/write, etc.). When finished — or if you hit a blocker — send an audit message reporting what you did and any result/output.

**Exception**: if the instruction involves sending a message to someone, creating a public resource, or any external communication, treat it as `MESSAGE_DRAFT` (draft + confirm) regardless of confidence.

## `INSTRUCTION_ADD`

The user is proposing a new rule, pattern, or example for this skill. Persist the proposal somewhere the user will review it later. The goal is a durable, reviewable record — not a specific tool or platform.

Preferred methods, in order of availability:

1. **Append to `PROPOSALS.md`** at the root of this skill's directory (always available, no external dependencies)
2. **Send the user a message** via the audit channel with the full proposal (as a fallback or supplement)

Each proposal entry should include:

- **title**: one-line summary of the rule
- **transcript**: the full memo transcript
- **interpretation**: your understanding of what the rule means
- **suggested change**: a concrete patch or example to add (not just a location reference), targeting `SKILL.md` or `references/classification-examples.md`
- **archive link**: path to the archived transcript from Step 4

Format for `PROPOSALS.md`:

```markdown
## YYYY-MM-DD — <title>

**Transcript**: <full transcript>

**Interpretation**: <what the rule means>

**Suggested change**:
<concrete patch or new example row>

**Archive**: data/YYYY/MM/DD/HH-MM-SS-<slug>.md
**Status**: pending
```

Before appending, scan existing entries in `PROPOSALS.md` for duplicates (similar title or transcript). If a near-duplicate exists, append a note to the existing entry rather than creating a new one.

Send the user an audit message confirming the proposal was recorded.

## `INSTRUCTION_UNSURE`

Do two things:

1. Send a message quoting the transcript and asking the user to confirm the intended action. Offer the best-guess interpretation.
2. Follow the `INSTRUCTION_ADD` action to record a proposal for a disambiguating example — so next time a similar phrasing lands, you'd classify it confidently. The proposal should include:

- The full transcript
- Your best-guess classification and confidence
- A suggested example row for `references/classification-examples.md`
- Why this was ambiguous and what would make it clear

## `TODO_ADAM`

Create an Apple Reminder in the user's default Reminders list (the list Siri uses — don't specify a list name). Use `osascript` with AppleScript:

```applescript
tell application "Reminders"
  set newReminder to make new reminder with properties {name:"<short title>", body:"<context/notes>"}
end tell
```

Where:

- `name`: a concise imperative title derived from the transcript
- `body`: any useful context from the memo (who, when, why) — include the full transcript at the bottom so nothing is lost

Send the user an audit message confirming the reminder was added.

## `TODO_ASSISTANT`

Append a line to `TODO.md` at the root of this skill's directory. Format:

```
- [ ] YYYY-MM-DD <short title> — <one-line context>. Archive: data/YYYY/MM/DD/HH-MM-SS-<slug>.md
```

If `TODO.md` doesn't exist, create it. Send the user an audit message confirming the task was added.

## `MEMORY_NOTE`

Write the fact to your memory system. The skill says _what_ to remember — the host runtime decides _how_ to store it (e.g. `memory/*.md` files, a knowledge base, structured notes). The memory should be durable and retrievable in future conversations.

Also archive the transcript per Step 4 (the archive is the audit trail; the memory write is the action).

Send the user an audit message confirming what was remembered.

## `JOURNAL_NOTE`

Archive the transcript per Step 4. Tag the archive transcript with `type: journal` in frontmatter. No further action — the archive _is_ the deliverable.

Send the user an audit message confirming the journal entry was archived.

## `IDEA_CAPTURE`

Archive the transcript per Step 4. Tag with `type: idea` in frontmatter.

Append to `IDEAS.md` at the root of this skill's directory:

```
- YYYY-MM-DD <short title> — <one-line summary>. Archive: data/YYYY/MM/DD/HH-MM-SS-<slug>.md
```

Send the user an audit message confirming the idea was captured.

## `RESEARCH_REQUEST`

Archive the transcript per Step 4. Tag with `type: research` in frontmatter.

Append to `TODO.md` with a `[research]` prefix:

```
- [ ] YYYY-MM-DD [research] <topic> — <one-line context>. Archive: data/YYYY/MM/DD/HH-MM-SS-<slug>.md
```

Do **not** start the research now — just capture the task. Send the user an audit message confirming the research request was filed.

## `MESSAGE_DRAFT`

Archive the transcript per Step 4. Tag with `type: message-draft` in frontmatter.

Draft the message and present it to the user for review. Include:

- Who the message is for
- The draft message text
- The channel/medium if mentioned (email, Slack, text, etc.)

**Never send the message.** Wait for explicit user confirmation. Send an audit message with the draft and ask for approval.

## `TRANSCRIBE_ONLY`

Archive the transcript per Step 4. No further action.

Send the user an audit message confirming the transcript was saved.

## `UNKNOWN`

Send the user an audit message containing the full transcript and ask how to categorize it. Include your best-guess classification (if any) and why you weren't confident.

This state feeds the classification training pipeline — memos that land here reveal gaps in the taxonomy or examples. Over time, patterns in `UNKNOWN` memos should drive new `INSTRUCTION_ADD` issues proposing additional states or examples.
