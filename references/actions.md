# Actions by State

What to do for each classification state. All actions are subject to the safety rules in SKILL.md Step 5.

## `INSTRUCTION_DIRECT`

Carry out the instruction using your normal tool set (bash, read/write, etc.). When finished — or if you hit a blocker — send an audit message reporting what you did and any result/output.

**Exception**: if the instruction involves sending a message to someone, creating a public resource, or any external communication, treat it as `MESSAGE_DRAFT` (draft + confirm) regardless of confidence.

## `INSTRUCTION_ADD`

Open a GitHub issue on `cyclingwithelephants/skill-apple-voice-assistant` capturing the proposed rule/example. Use `gh issue create` with:

- **title**: one-line summary of the rule (prefix `instruction: `)
- **body**: full transcript, your interpretation of what the rule means, a suggested patch snippet showing the proposed edit (not just a location reference), and the archived transcript path from Step 4

Before creating, check for existing open issues with similar titles (`gh issue list -s open --search "<keywords>"`) to avoid duplicates.

Send the user a short audit message confirming the issue URL.

## `INSTRUCTION_UNSURE`

Do two things:

1. Send a message quoting the transcript and asking the user to confirm the intended action. Offer the best-guess interpretation.
2. Follow the `INSTRUCTION_ADD` action to file a GitHub issue proposing an example that would have disambiguated this memo — so next time a similar phrasing lands, you'd classify it confidently. Use the normalized template:

```markdown
## Type

Edge case / disambiguating example

## Transcript

<full transcript>

## Proposed classification

<your best guess state> (confidence: <level>)

## Suggested example for references/classification-examples.md

| "<key phrase>" | `<STATE>` | <confidence> | <reasoning> |

## Context

<why this was ambiguous, what would make it clear>
```

Reference the audit message in the issue.

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
