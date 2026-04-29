# Archive Format

Specification for Step 4 of the skill — archiving audio and transcripts.

## Directory layout

The skill's own directory is the active Hermes workspace's symlinked skill path, typically `${HERMES_HOME:-$HOME/.hermes}/skills/apple/apple-voice-assistant/`. Archive under its `data/` subtree:

```
data/YYYY/MM/DD/HH-MM-SS-<slug>.m4a      # copy of the original audio
data/YYYY/MM/DD/HH-MM-SS-<slug>.md       # transcript + metadata
```

Example: `data/2026/04/19/08-30-45-grocery-list-for-saturday.m4a` + `data/2026/04/19/08-30-45-grocery-list-for-saturday.md`

Create missing intermediate directories with `mkdir -p`. The audio and transcript must share the same `HH-MM-SS-<slug>` stem — never drift.

## Deriving the timestamp

Prefer the timestamp embedded in the Voice Memos filename — the app names recordings like `YYYYMMDD HHMMSS.m4a` (e.g. `20260419 083045.m4a`). Parse out year, month, day, hour, minute, and second, then format as `YYYY/MM/DD` for the directory path and `HH-MM-SS` for the filename prefix.

If the filename doesn't follow that pattern, fall back to the file's mtime via `stat -f %m <path>`.

## Deriving the slug

Generate a short human-readable slug from the transcript so archived files are self-describing at a glance.

Rules:

- 2–6 words, all lowercase, hyphen-separated
- Describe the topic or action, not the form (good: `grocery-list-for-saturday`, bad: `voice-memo-about-groceries`)
- Strip all non-ASCII-alphanumeric characters before hyphenating (spaces, punctuation, emoji, accents → gone)
- Cap total slug length at 50 characters — truncate at the nearest hyphen rather than mid-word
- If the transcript is too empty or noisy to produce a meaningful slug, use `untitled`

## Audio file

`cp` (never `mv`) from the source path — iCloud owns the Voice Memos file lifecycle and moving would break the app. Preserve the original extension (normally `.m4a`, but derive from the source path, don't assume).

## Transcript file

A Markdown file with YAML frontmatter followed by the full transcript body:

```markdown
---
memo_id: "20260419 083045"
source_path: /Users/<user>/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/20260419 083045.m4a
source_mtime: 1745053845
source_size_bytes: 234567
recorded_at: 2026-04-19T08:30:45Z
archived_at: 2026-04-19T08:31:02Z
duration_seconds: 47
category: TODO_ADAM
confidence: high
type: memo
action_taken: created Apple Reminder
---

<full transcript verbatim>
```

### Required fields

- `memo_id` — basename without extension, used for dedup
- `source_path` — absolute path to the original `.m4a`
- `source_mtime` — Unix timestamp of the source file's mtime
- `source_size_bytes` — file size in bytes
- `recorded_at` — derived from filename or mtime
- `archived_at` — current time when archiving
- `category` — the classification state
- `confidence` — high/medium/low

### Optional fields

- `duration_seconds` — audio duration if determinable
- `type` — semantic tag: `memo` (default), `journal`, `idea`, `research`, `message-draft`
- `action_taken` — filled in after Step 5 completes (update the file after acting)
- `transcript_confidence` — if the runtime provides a transcription confidence score

## If archiving fails

If the `cp` or transcript write fails (disk full, permission denied, etc.), log it and continue to Step 5 anyway — the action the user intended should still happen. Include the failure in the audit message.
