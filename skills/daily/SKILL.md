---
name: daily
description: >-
  Manage the user's daily journal in Obsidian using a structured morning/
  evening workflow. Use this skill whenever the user mentions their daily
  journal, daily note, morning planning, evening review, daily agenda,
  daily log, or any variation of "plan my day", "review my day", "update my
  journal", "what's on today", "wrap up my day", "end of day", "start of
  day", or "daily". Also trigger when the user asks to check, create, or
  update today's (or any specific date's) journal entry. This skill depends
  on the `vault` skill for vault conventions and PARA awareness — always
  read the `vault` SKILL.md first.
allowed-tools:
  - mcp__obsidian__date_time
  - mcp__obsidian__daily_read
  - mcp__obsidian__daily_append
  - mcp__obsidian__daily_prepend
  - mcp__obsidian__file_read
  - mcp__obsidian__file_create
  - mcp__obsidian__file_append
  - mcp__obsidian__templates_list
  - mcp__obsidian__template_read
  - mcp__obsidian__tasks_list
  - mcp__obsidian__task_update
---

# Obsidian Daily Journal

A skill for preparing, updating, and maintaining daily journal entries in
the user's Obsidian vault. Supports two distinct workflows — **morning
planning** and **evening review** — designed to take 5–15 minutes each.

## Dependencies

- **`vault` skill**: Read it first for vault conventions, PARA structure,
  and MCP gotchas.
- **User's `claude.md`** (if present): Always check for vault-specific
  conventions before writing.

## Journal Template

Do NOT hardcode or assume the template structure. Instead:

1. Use `mcp__obsidian__templates_list` to see available templates.
2. Use `mcp__obsidian__template_read` with the matching `name` (set
   `resolve: true` if you want variables interpolated) to read the actual
   template content.
3. Use that template as-is when seeding a new journal entry.

### Rules when working with the template

- Never modify or regenerate `dataviewjs` or `dataview` code blocks — treat
  them as read-only.
- Tasks use standard Obsidian checkbox syntax: `- [ ]` (open) / `- [x]`
  (done).
- Keep frontmatter fields intact. Only update fields like `location` if
  the user explicitly says so.
- Dates follow `YYYY-MM-DD` format (grab them from
  `mcp__obsidian__date_time`).
- If the template can't be found, ask the user — don't guess.

## Workflow

### Step 0: Determine mode

Ask the user (or infer from context/time cues):

| Signal                                                           | Mode                                       |
| ---------------------------------------------------------------- | ------------------------------------------ |
| "plan my day", "morning", "start of day", "what's on today"      | Morning                                    |
| "review", "wrap up", "end of day", "evening", "how did today go" | Evening                                    |
| Ambiguous or just "daily" / "journal"                            | Ask: "Morning planning or evening review?" |

### Step 1: Locate or create the journal entry

1. Try `mcp__obsidian__daily_read` to fetch today's note.
2. If it already exists → work with it.
3. If it doesn't exist → read the journal template (see "Journal Template"
   above) and create the entry. The simplest path is
   `mcp__obsidian__daily_append` with the template body as `content` —
   that tool auto-creates today's daily note via the user's Daily Notes
   settings. If the user's setup doesn't auto-create, fall back to
   `mcp__obsidian__file_create` with a `path` derived from the user's
   daily-note convention and today's date from `date_time`.
4. If the user specifies a different date → use that date instead of
   today. The server's `daily_*` tools always target today, so
   non-today dates have to go through `file_read` / `file_create` /
   `file_append` with an explicit `path` you compute from the user's
   convention + the date.

### Step 2a: Morning Planning (5–15 min)

Goal: Help the user walk into their day with clarity.

1. **Read yesterday's journal** (if it exists). The server doesn't expose
   a "yesterday" helper — compute yesterday's date from
   `mcp__obsidian__date_time`, then `mcp__obsidian__file_read` with the
   corresponding `path` based on the user's daily-note convention. If you
   can't determine the convention, ask the user. Scan for:
   - Unfinished tasks (carry forward if still relevant)
   - Any "tomorrow" notes in the Log
2. **Check external context** if available (calendar, email via connected
   tools). Summarize what's coming up today.
3. **Populate the Agenda section** with:
   - Carried-over tasks from yesterday
   - Calendar events / meetings
   - Anything the user mentions
4. **Populate the Tasks section** with actionable items derived from the
   agenda. Keep them concrete and completable.
5. **Present a summary** to the user and ask if anything is missing or
   should change.
6. **Write the file** once confirmed. Use `mcp__obsidian__daily_append`
   (or `daily_prepend` if the template expects new content at the top).

Keep the tone concise and practical — no motivational fluff. The user
wants to think clearly, not be coached.

### Step 2b: Evening Review (5–15 min)

Goal: Help the user close the day cleanly and capture what matters.

1. **Read today's journal** with `mcp__obsidian__daily_read` — review
   Agenda and Tasks.
2. **Ask the user** (briefly, not an interrogation):
   - "What got done? Anything to note?"
   - "Anything to carry to tomorrow?"
3. **Update the Tasks section**: Mark completed items `- [x]` using
   `mcp__obsidian__task_update` (pass `ref` as `path:line` with
   `done: true` or `toggle: true`). Leave open items as-is, or move them
   to tomorrow's note if the user says so.
4. **Update the Log section** with:
   - Key outcomes, decisions, observations the user shares
   - Keep it bullet-point style, concise
   - Use `mcp__obsidian__daily_append` with the new lines.
5. **Optionally preview tomorrow**: If the user wants, create tomorrow's
   journal entry via `mcp__obsidian__file_create` at the appropriate
   path and seed its Agenda with carried-over items.
6. **Confirm** what you wrote once the user is satisfied.

### PARA Integration

The journal itself lives outside the PARA hierarchy (it's a daily
artifact, not a project or area). But when the user mentions work related
to a specific Project or Area:

- Link to the relevant note using `[[Note Name]]` wikilink syntax.
- If a task belongs to a PARA project, tag it or link it:
  `- [ ] Finish proposal draft → [[Q3 Proposal]]`
- Don't reorganize the user's vault — just create the connections.

## Important Reminders

- **Don't over-ask.** Morning and evening should feel lightweight. 2–3
  focused questions max, then write.
- **Don't invent content.** Only add what the user tells you, what's
  carried from yesterday, or what comes from connected tools
  (calendar/email). Never fabricate agenda items or tasks.
- **Preserve existing content.** When updating a journal that already
  has entries, append — don't overwrite. The server already refuses
  `file_create` with `overwrite: true` and empty content, but you
  should avoid overwrite entirely unless the user explicitly asks.
- **Respect the user's style.** Read past journal entries to match
  their tone, level of detail, and conventions. If they write terse
  bullets, you write terse bullets.
