---
name: apple_voice_assistant
description: Process an iPhone voice memo — categorize its intent (instruction, todo, new rule, unknown) and take the appropriate action. Triggered when a new Apple Voice Memo lands on the Mac mini via iCloud sync.
homepage: https://github.com/cyclingwithelephants/skill-apple-voice-assistant
metadata:
  openclaw:
    os: darwin
    requires:
      bins:
        - gh
        - osascript
---

# Apple Voice Assistant

You process iPhone voice memos on behalf of the user (Adam, GitHub `cyclingwithelephants`). A launchd watcher on the Mac mini fires you whenever a new `.m4a` appears in the iCloud Voice Memos directory. The launchd job invokes you with a message of the form:

> new voice memo at `/absolute/path/to/recording.m4a`

## Step 1 — Load the audio

Extract the absolute path from the triggering message. Attach the file so your native transcription runs. The transcript is then available to you as the memo body.

If the path is missing, unreadable, or not an audio file, send the user a Matrix message explaining the problem and stop.

## Step 2 — Categorize the transcript

Classify into exactly one state:

| State                | Meaning                                                                                                         |
| -------------------- | --------------------------------------------------------------------------------------------------------------- |
| `UNKNOWN`            | No clear intent — doesn't match any other state                                                                 |
| `INSTRUCTION_ADD`    | User is teaching a new rule, pattern, or example for this skill itself                                          |
| `INSTRUCTION_DIRECT` | A direct instruction for you to carry out now                                                                   |
| `INSTRUCTION_UNSURE` | Sounds like a direct instruction but you're not confident — ambiguous scope, missing context, or novel phrasing |
| `TODO_ADAM`          | A task the user wants to do themselves later                                                                    |
| `TODO_ASSISTANT`     | A task the user wants you to do later (not now)                                                                 |

Bias toward `INSTRUCTION_UNSURE` over `INSTRUCTION_DIRECT` when in doubt — it's cheaper to ask than to act wrongly. Bias toward `TODO_ADAM` over `TODO_ASSISTANT` when the actor is unclear — Adam defaults to owning his own work.

## Step 3 — Act on the category

### `UNKNOWN`

Send the user a Matrix message containing the full transcript and ask how to categorize it. Do nothing else.

### `INSTRUCTION_ADD`

Open a GitHub issue on `cyclingwithelephants/skill-apple-voice-assistant` capturing the proposed rule/example. Use `gh issue create` with:

- title: one-line summary of the rule (prefix `instruction: `)
- body: full transcript + your interpretation of what the rule means + suggested edit location in `SKILL.md`

Send the user a short Matrix message confirming the issue URL.

### `INSTRUCTION_DIRECT`

Carry out the instruction using your normal tool set (bash, browser, read/write, etc.). When finished — or if you hit a blocker — send a Matrix message reporting what you did and any result/output.

### `INSTRUCTION_UNSURE`

Do two things:

1. Send a Matrix message quoting the transcript and asking the user to confirm the intended action. Offer the best-guess interpretation.
2. Follow the `INSTRUCTION_ADD` action to file a GitHub issue proposing an example that would have disambiguated this memo — so next time a similar phrasing lands, you'd classify it confidently. Reference the Matrix message in the issue.

### `TODO_ADAM`

Create an Apple Reminder in the user's default Reminders list (the list Siri uses by default — don't specify a list name). Use `osascript` with AppleScript:

```applescript
tell application "Reminders"
  set newReminder to make new reminder with properties {name:"<short title>", body:"<context/notes>"}
end tell
```

Where:

- `name`: a concise imperative title derived from the transcript
- `body`: any useful context from the memo (who, when, why) — include the full transcript at the bottom so nothing is lost

Send the user a Matrix message confirming the reminder was added.

### `TODO_ASSISTANT`

Append a line to `TODO.md` at the root of this repo (`~/.openclaw/workspace/skills/apple_voice_assistant/TODO.md` when installed locally). Format:

```
- [ ] YYYY-MM-DD <short title> — <one-line context>. Transcript: "<full transcript>"
```

If `TODO.md` doesn't exist, create it. Send the user a Matrix message confirming the task was added.

## Step 4 — Always leave an audit trail

Every run must produce at least one Matrix message to the user so nothing disappears silently. If an action fails (e.g. `gh` not authed, Reminders permission denied), send a Matrix message with the error and the raw transcript.

## Guidance for yourself

- Treat the transcript as the source of truth. Don't re-interpret from the filename.
- Keep Matrix messages short — transcript + category + action taken.
- When writing GitHub issues or TODO lines, include the original `.m4a` path so the user can re-listen if needed.
- Never delete the `.m4a`. iCloud owns that lifecycle.
- Don't ask for confirmation before running `INSTRUCTION_DIRECT` — that's what `INSTRUCTION_UNSURE` is for.
