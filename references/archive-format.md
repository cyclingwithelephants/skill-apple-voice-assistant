# Archive Format

Specification for the voice memo archive. Archiving happens in two phases across two components.

## Two-phase archiving

| Phase | Component                   | Fields written                                                                                           |
| ----- | --------------------------- | -------------------------------------------------------------------------------------------------------- |
| 1     | Watcher (`process-memo.py`) | `memo_id`, `source_path`, `source_mtime`, `source_size_bytes`, `recorded_at`, `archived_at` + audio copy |
| 2     | Hermes (SKILL.md Step 4)    | `category`, `confidence`, `type`, `action_taken`                                                         |

The watcher creates the archive file with Phase 1 fields. Hermes updates the same file's YAML frontmatter to add Phase 2 fields after classification and action.

## Directory layout

Archives live under `~/.local/state/apple-voice-assistant/data/`:

```
data/YYYY/MM/DD/HH-MM-SS-<slug>.m4a      # copy of the original audio
data/YYYY/MM/DD/HH-MM-SS-<slug>.md       # transcript + metadata
```

Example: `data/2026/04/19/08-30-45-grocery-list-for-saturday.m4a` + `data/2026/04/19/08-30-45-grocery-list-for-saturday.md`

The audio and transcript must share the same `HH-MM-SS-<slug>` stem — never drift.

## Deriving the timestamp

Prefer the timestamp embedded in the Voice Memos filename — the app names recordings like `YYYYMMDD HHMMSS.m4a` (e.g. `20260419 083045.m4a`). Parse out year, month, day, hour, minute, and second, then format as `YYYY/MM/DD` for the directory path and `HH-MM-SS` for the filename prefix.

If the filename doesn't follow that pattern, fall back to the file's mtime via `stat -f %m <path>`.

## Deriving the slug

The watcher generates a deterministic slug from the first ~5 words of the transcript. Rules:

- 2–6 words, all lowercase, hyphen-separated
- Strip all non-ASCII-alphanumeric characters before hyphenating
- Cap total slug length at 50 characters — truncate at the nearest hyphen rather than mid-word
- If the transcript is too empty or noisy to produce a meaningful slug, use `untitled`

## Audio file

`cp` (never `mv`) from the source path — iCloud owns the Voice Memos file lifecycle and moving would break the app. Preserve the original extension (normally `.m4a`, but derive from the source path, don't assume).

## Transcript file

A Markdown file with YAML frontmatter followed by the full transcript body:

```markdown
---
memo_id: "20260419 083045"
source_path: ~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/20260419 083045.m4a
source_mtime: 1745053845
source_size_bytes: 234567
recorded_at: 2026-04-19T08:30:45Z
archived_at: 2026-04-19T08:31:02Z
duration_seconds: 47
category: TODO
confidence: high
type: memo
action_taken: created Apple Reminder
---

<full transcript verbatim>
```

### Phase 1 fields (written by watcher)

- `memo_id` — basename without extension, used for dedup
- `source_path` — absolute path to the original `.m4a`
- `source_mtime` — Unix timestamp of the source file's mtime
- `source_size_bytes` — file size in bytes
- `recorded_at` — derived from filename or mtime
- `archived_at` — current time when archiving

### Phase 2 fields (written by Hermes in Step 4)

- `category` — the classification state (required)
- `confidence` — high/medium/low (required)
- `type` — semantic tag: `memo` (default), `idea`, `research` (optional)
- `action_taken` — filled in after Step 5 completes, update the file after acting (optional)

### Other optional fields

- `duration_seconds` — audio duration if determinable
- `transcript_confidence` — if the runtime provides a transcription confidence score

## If archiving fails

Phase 1 (watcher): if the copy or transcript write fails, the watcher logs the error and does not fire the webhook — the memo will be retried on the next run.

Phase 2 (Hermes): if updating the archive frontmatter fails, log it and continue to Step 5 anyway — the action the user intended should still happen. Include the failure in the audit message.
