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
        - sqlite3
---

# Apple Voice Assistant

You process iPhone voice memos on behalf of the user (Adam, GitHub `cyclingwithelephants`). A launchd watcher on the Mac mini fires you whenever a new `.m4a` appears in the iCloud Voice Memos directory. The launchd job invokes you with a message of the form:

> new voice memo at `/absolute/path/to/recording.m4a`

## Step 1 — Load the audio

Extract the absolute path from the triggering message (e.g. `/Users/adam/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/20260419 083045.m4a`).

Explicitly read the file and attach it to the conversation so your native audio transcription runs over it. Do not assume the audio is already loaded — call your `read` tool on the path first, then rely on the resulting `{{Transcript}}` variable / `[Audio]` block for the memo body.

Validate before proceeding:

- path exists and is readable
- file ends in `.m4a` (skip `.icloud` placeholders — they mean iCloud hasn't finished syncing yet; if you see one, log and stop, the launchd watcher will retry on the next change)
- transcript is non-empty

If any check fails, send the user a Matrix message explaining the problem and stop.

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

## Step 3 — Rename the memo in the Voice Memos app

Give the recording a useful, human-readable title derived from the transcript so the user can scan their Voice Memos list and know what each one is about without replaying it.

Pick a concise title:

- 3–8 words, title-case, no trailing punctuation
- describe the _topic or action_, not the form (good: `Grocery list for Saturday`, bad: `Voice memo about groceries`)
- if the memo is an instruction or todo, lead with the verb (good: `Add sqlite3 to skill requirements`)
- keep the original date/time implicit — Voice Memos already shows it

**Do not just `mv` the `.m4a`.** Voice Memos stores display names in a SQLite database, not the filename. Renaming the file on disk won't change what appears in the app and may break the app's link to the recording.

Instead, update the `CloudRecordings.db` SQLite database that backs the Voice Memos app. It lives at:

```
~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/CloudRecordings.db
```

Use `sqlite3` from bash. The recording's row is in the `ZCLOUDRECORDING` table; the display-name column is `ZCUSTOMLABEL` (with a parallel `ZENCRYPTEDTITLE` on newer macOS — if present, update both). Match the row by `ZPATH` or `ZUNIQUEID` against the file you were given. CloudKit will sync the new name back to the iPhone within a minute or two.

Before writing:

1. Verify the Voice Memos app is not holding a write lock (a `sqlite3 ... "PRAGMA quick_check;"` that returns `ok` is a good signal; if it errors, skip the rename, note it, and continue to Step 4)
2. Make a backup: `cp CloudRecordings.db CloudRecordings.db.bak.$(date +%s)` in the same dir — keep only the most recent 5 backups
3. Inspect the schema first (`.schema ZCLOUDRECORDING`) in case the column names have shifted on the current macOS version; prefer a schema lookup over trusting the names above blindly

If the rename fails for any reason, log it, continue to Step 4, and include the failure in the Matrix audit message. Do not retry more than once per run.

## Step 4 — Act on the category

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

Append a line to `TODO.md` at the root of this directory (`~/.openclaw/workspace/skills/apple_voice_assistant/TODO.md` when installed locally). Format:

```
- [ ] YYYY-MM-DD <short title> — <one-line context>. Transcript: "<full transcript>"
```

If `TODO.md` doesn't exist, create it. Send the user a Matrix message confirming the task was added.

## Step 5 — Always leave an audit trail

Every run must produce at least one Matrix message to the user so nothing disappears silently. If an action fails (e.g. `gh` not authed, Reminders permission denied, SQLite locked during rename), send a Matrix message with the error and the raw transcript.

**If the Matrix send itself fails** (network error, openclaw channel misconfigured, homeserver down, etc.) you cannot rely on the user ever seeing this run. Append a self-chase item to `TODO.md` at the root of this directory so you remember to surface it next time you run successfully. Format:

```
- [ ] YYYY-MM-DD FOLLOW-UP — failed to notify user about memo <path>. Category: <STATE>. Action taken: <summary or "none">. Error: <matrix error>. Transcript: "<full transcript>"
```

On every subsequent run, before Step 1, scan `TODO.md` for `FOLLOW-UP` items and include a short "unresolved follow-ups" section in the Matrix message for this run. Once the user has been told, strike the line through (`~~...~~`) rather than deleting it — keep the audit history.

## Guidance for yourself

- Treat the transcript as the source of truth. Don't re-interpret from the filename.
- Keep Matrix messages short — transcript + category + action taken + rename (if done).
- When writing GitHub issues or TODO lines, include the original `.m4a` path so the user can re-listen if needed.
- Never delete the `.m4a`. iCloud owns that lifecycle.
- Don't ask for confirmation before running `INSTRUCTION_DIRECT` — that's what `INSTRUCTION_UNSURE` is for.
- Always process the steps in order: load → rename → act → audit. A failed rename never blocks the action step; a failed action never blocks the audit step.
