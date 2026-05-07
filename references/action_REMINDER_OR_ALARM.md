# Action: REMINDER_OR_ALARM

A reminder, alarm, shopping-list addition, or time-sensitive personal task.

STATE_DIR: `~/.local/state/apple-voice-assistant`

---

## Non-negotiable confirmation requirement

Adam wants a Matrix confirmation/audit message every time a voice memo is processed, regardless of category or whether the action succeeded, failed, or only created a draft. Send it to `matrix:!nSlDhIlsFlFubTCaWO:matrix.adamland.xyz`. If Matrix delivery fails, append a FOLLOW-UP line to `~/.local/state/apple-voice-assistant/TODO.md` with enough detail to replay the missed confirmation later.

## Step 1: Interpret destination

- If the memo says shopping list/groceries/buy/add to shopping list, use the `Shopping` list when supported.
- Otherwise use the default Reminders list.
- If the memo includes a due date/time, convert it to a precise supported date format. If ambiguous, omit due date and mention ambiguity in audit.

## Step 2: Try Apple Reminders via remindctl (best-effort)

Use absolute path `/opt/homebrew/bin/remindctl`.

Default task:

```bash
/opt/homebrew/bin/remindctl add --title "<title>" --notes "<full transcript>"
```

Shopping item, if list support works in the installed remindctl:

```bash
/opt/homebrew/bin/remindctl add --title "<item>" --list Shopping --notes "<full transcript>"
```

If a due date is clear, add `--due "YYYY-MM-DD"` or `--due "YYYY-MM-DD HH:mm"`.

If remindctl fails, do not retry forever. Log the error and continue.

## Step 3: Append reliable fallback to TODO.md

Always append one line:

```text
- [ ] YYYY-MM-DD <short title> — Reminder/alarm/list item from voice memo. Archive: <archive_path>
```

## Step 4: Update archive frontmatter

Add:

- `category: REMINDER_OR_ALARM`
- `confidence: <high|medium|low>`
- `action_taken: <created Reminder/list item and appended TODO fallback OR fallback only with error>`

## Step 5: Write processed JSON

Write `~/.local/state/apple-voice-assistant/processed/<memo_id>.json` with category `REMINDER_OR_ALARM` and disposition matching the action taken.

## Step 6: Audit

Send Matrix audit with transcript summary, reminder/list title, due date/list if any, confidence, action taken, archive path.

## DONE
