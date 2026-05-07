# Action: TODO

A task to capture. Try to create an Apple Reminder (best-effort), then always log to TODO.md.

**Read [`action_COMMON.md`](action_COMMON.md) first** — it defines the audit requirement, archive frontmatter update, processed JSON write, and audit steps that apply to every state.

---

## Step 1: Try Apple Reminder via remindctl (best-effort)

**Apple Reminders may be unavailable from daemon/webhook contexts** (Mach error 4099 — the system LaunchDaemon cannot reach the user-session Reminders XPC service). Treat this step as best-effort. If it fails, log the error and continue to Step 2.

Run this command, substituting the placeholders:

```bash
/opt/homebrew/bin/remindctl add --title "<title>" --notes "<full transcript>"
```

If the memo mentions a due date, add `--due <date>`:

```bash
/opt/homebrew/bin/remindctl add --title "<title>" --due "<YYYY-MM-DD>" --notes "<full transcript>"
```

- `title`: descriptive title that preserves the key context from the memo — include the what, who, and why so the reminder is actionable without re-reading the transcript. Aim for 8-15 words.
- `notes`: the **full verbatim transcript** from the webhook payload
- `due`: **must be `YYYY-MM-DD` format only** — natural language dates are unreliable
- DO NOT specify a list — use the default list
- Use the absolute path `/opt/homebrew/bin/remindctl` — Homebrew is not on PATH in daemon contexts

If remindctl fails for any reason, do NOT retry. Log the error and continue to Step 2.

## Step 2: Append to TODO.md (always)

This step runs regardless of whether Step 1 succeeded. TODO.md is the reliable record.

Append one line to `~/.local/state/apple-voice-assistant/TODO.md`:

```
- [ ] YYYY-MM-DD <short title> — <one-line context>. Archive: <archive_path>
```

If `~/.local/state/apple-voice-assistant/TODO.md` does not exist, create it before appending.

## Step 3: Common steps

Follow **Update archive frontmatter**, **Write processed JSON**, and **Audit** from [`action_COMMON.md`](action_COMMON.md).

## DONE
