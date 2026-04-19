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

## Step 3 — Archive the audio and transcript

Copy the raw audio and write a matching transcript file into this skill's own `data/` tree, organized by date. This gives a durable, greppable history independent of Voice Memos / iCloud and survives any upstream deletion.

### Derive the timestamp

Prefer the timestamp embedded in the Voice Memos filename — the app names recordings like `YYYYMMDD HHMMSS.m4a` (e.g. `20260419 083045.m4a`). Parse out year, month, day, and time components from the filename.

If the filename doesn't follow that pattern, fall back to the file's mtime via `stat -f %m <path>`.

### Write both files

The skill's own directory is at `~/.openclaw/workspace/skills/apple_voice_assistant/`. Archive under its `data/` subtree:

```
data/YYYY/MM/DD/HHMMSS.m4a      # copy of the original audio, extension preserved
data/YYYY/MM/DD/HHMMSS.md       # transcript + metadata
```

Create any missing intermediate directories with `mkdir -p`.

**Audio**: `cp` (never `mv`) from the source path — iCloud owns the Voice Memos file lifecycle and moving would break the app. Preserve the original extension (normally `.m4a`, but don't assume — derive from the source path).

**Transcript**: a Markdown file with YAML frontmatter followed by the full transcript body. Use this structure:

```markdown
---
source_path: /Users/adam/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/20260419 083045.m4a
recorded_at: 2026-04-19T08:30:45Z
archived_at: 2026-04-19T08:31:02Z
duration_seconds: 47
category: INSTRUCTION_UNSURE
action_taken: filed GitHub issue #12 + Matrix message
---

<full transcript verbatim>
```

Include whichever frontmatter fields you have information for — `duration_seconds` is optional, `source_path` / `recorded_at` / `archived_at` / `category` are required. `action_taken` is filled in after Step 4 completes (either update the file or append it at the end; updating is fine).

### If archiving fails

If the `cp` or transcript write fails (disk full, permission denied, etc.), log it and continue to Step 4 anyway — the action the user intended should still happen. Include the failure in the Matrix audit message.

## Step 4 — Act on the category

### `UNKNOWN`

Send the user a Matrix message containing the full transcript and ask how to categorize it. Do nothing else.

### `INSTRUCTION_ADD`

Open a GitHub issue on `cyclingwithelephants/skill-apple-voice-assistant` capturing the proposed rule/example. Use `gh issue create` with:

- title: one-line summary of the rule (prefix `instruction: `)
- body: full transcript + your interpretation of what the rule means + suggested edit location in `SKILL.md` + a reference to the archived transcript path from Step 3

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
- [ ] YYYY-MM-DD <short title> — <one-line context>. Archive: data/YYYY/MM/DD/HHMMSS.md
```

If `TODO.md` doesn't exist, create it. Send the user a Matrix message confirming the task was added.

## Step 5 — Always leave an audit trail

Every run must produce at least one Matrix message to the user so nothing disappears silently. If an action fails (e.g. `gh` not authed, Reminders permission denied, archive write failed), send a Matrix message with the error and the raw transcript.

**If the Matrix send itself fails** (network error, openclaw channel misconfigured, homeserver down, etc.) you cannot rely on the user ever seeing this run. Append a self-chase item to `TODO.md` at the root of this directory so you remember to surface it next time you run successfully. Format:

```
- [ ] YYYY-MM-DD FOLLOW-UP — failed to notify user about memo. Archive: data/YYYY/MM/DD/HHMMSS.md. Category: <STATE>. Action taken: <summary or "none">. Error: <matrix error>.
```

On every subsequent run, before Step 1, scan `TODO.md` for `FOLLOW-UP` items and include a short "unresolved follow-ups" section in the Matrix message for this run. Once the user has been told, strike the line through (`~~...~~`) rather than deleting it — keep the audit history.

## Guidance for yourself

- Treat the transcript as the source of truth. Don't re-interpret from the filename.
- Keep Matrix messages short — transcript + category + action taken + archive path.
- When writing GitHub issues or TODO lines, reference the archived transcript path (`data/YYYY/MM/DD/HHMMSS.md`) rather than the original Voice Memos path — the archive is stable, the source may move or be deleted by iCloud.
- Never delete or move the source `.m4a`. iCloud owns that lifecycle; archiving is a copy.
- Don't ask for confirmation before running `INSTRUCTION_DIRECT` — that's what `INSTRUCTION_UNSURE` is for.
- Always process the steps in order: load → categorize → archive → act → audit. A failed archive never blocks the action step; a failed action never blocks the audit step.
