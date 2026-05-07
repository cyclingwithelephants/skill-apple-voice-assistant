# Action: REMINDER_OR_ALARM

A reminder, alarm, shopping-list addition, or time-sensitive personal task.

**Read [`action_COMMON.md`](action_COMMON.md) first** — it defines the audit requirement, archive frontmatter update, processed JSON write, and audit steps that apply to every state.

---

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

## Step 4: Common steps

Follow **Update archive frontmatter**, **Write processed JSON**, and **Audit** from [`action_COMMON.md`](action_COMMON.md). Include reminder/list title, due date/list if any.

## DONE
