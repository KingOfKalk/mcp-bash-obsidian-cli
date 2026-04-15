---
name: vault
description: >-
  Interact with an Obsidian vault via the obsidian MCP server. Use this skill
  whenever the user wants to create, read, search, edit, move, restructure, or
  query notes in Obsidian. Also use when the user mentions daily notes,
  journals, PARA method, knowledge management, note-taking, vault organization,
  backlinks, tags, tasks, templates, or anything related to their Obsidian
  workflow. Trigger on mentions of "obsidian", "vault", "note", "daily note",
  "journal", "PARA", "projects folder", "areas folder", "resources folder",
  "archives folder", "zettelkasten", or any request to find, summarize, or
  restructure knowledge. Even casual requests like "add this to my notes",
  "what did I write about X", or "clean up my vault" should trigger this skill.
allowed-tools:
  - mcp__obsidian__date_time
  - mcp__obsidian__file_read
  - mcp__obsidian__file_list
  - mcp__obsidian__file_info
  - mcp__obsidian__file_create
  - mcp__obsidian__file_append
  - mcp__obsidian__file_prepend
  - mcp__obsidian__file_move
  - mcp__obsidian__file_rename
  - mcp__obsidian__file_delete
  - mcp__obsidian__folder_list
  - mcp__obsidian__folder_info
  - mcp__obsidian__search
  - mcp__obsidian__properties_list
  - mcp__obsidian__property_read
  - mcp__obsidian__property_set
  - mcp__obsidian__property_remove
  - mcp__obsidian__tags_list
  - mcp__obsidian__tag_info
  - mcp__obsidian__tasks_list
  - mcp__obsidian__task_update
  - mcp__obsidian__backlinks
  - mcp__obsidian__links_outgoing
  - mcp__obsidian__outline
  - mcp__obsidian__wordcount
  - mcp__obsidian__templates_list
  - mcp__obsidian__template_read
  - mcp__obsidian__aliases_list
---

# Obsidian Vault Skill

Interact with an Obsidian vault through the `obsidian` MCP server. The user's
vault follows the PARA method. The server is pinned to one vault at startup
via env, so **never pass a `vault` parameter** — it doesn't exist on any tool.

## Step 0 — Always Do First

Before any action, get the current date/time with `mcp__obsidian__date_time`.
Called with no arguments it returns a JSON object (`iso`, `date`, `time`,
`weekday`, `timezone`, `unix`, `utc`); pass `format` for a single strftime
string (e.g. `"%Y-%m-%d %H:%M:%S %A"`). Keep the result handy — you need it
for daily notes, timestamps, frontmatter, file naming, and contextual
awareness ("today", "this week", "yesterday").

## Step 1 — Read References As Needed

When classifying, organizing, or restructuring notes, read
`references/PARA_Method_Guide.md` for the classification rules. You don't
need to re-read it if you've already read it in this conversation.

Everything else you need about the tool surface is already in the
`mcp__obsidian__*` tool list — each tool ships its input schema, so lean on
that instead of guessing CLI-style parameter names.

## Step 2 — Gotchas

The MCP server handles the historical Obsidian CLI silent-failure traps for
you (it forces `silent` on creates, refuses `overwrite=true` with empty
content, injects `format=json` where the CLI silently drops it, and parses
stdout for `Error:`). A few residual caveats still apply:

1. **Scope `tags_list` / `properties_list` / `tasks_list`.** Without a
   `file` or `path`, these may return empty on some CLI versions because
   the underlying command scopes to the active file. Pass `file=` /
   `path=` when you need reliable results; for tasks you can also use
   `daily: true`.
2. **`property_set` stale cache.** If you just wrote a file externally,
   `property_set` can no-op for ~3 seconds. Wait briefly before setting
   properties on a freshly written file, or retry once.
3. **`file_create` overwrite.** The server refuses `overwrite: true` with
   empty `content` (it would truncate the file to 0 bytes). Always pass
   non-empty `content` when overwriting.

## Step 3 — PARA-Aware Vault Structure

The user's vault follows this structure:

```
0-Inbox/          ← capture buffer, unprocessed items
1-Projects/       ← active, time-bound work with deadlines
2-Areas/          ← ongoing responsibilities (no end date)
3-Resources/      ← reference material, interests
4-Archives/       ← inactive items from 1–3
```

### Classification Decision Tree

When creating or moving notes, classify by asking in order — stop at first
"yes":

1. Does it belong to an active project with a deadline? → `1-Projects/`
2. Does it relate to an ongoing area of responsibility? → `2-Areas/`
3. Is it a topic of interest or reference? → `3-Resources/`
4. None of the above / no longer active? → `4-Archives/`

### Project vs. Area — The Verb Test

- **Project verbs:** finalize, ship, deliver, publish, launch → has a
  deadline, has a finish line
- **Area verbs:** manage, maintain, ensure, oversee → ongoing, never "done"

If unsure, ask the user. Don't guess.

## Common Workflows

Each workflow points at the right tool and calls out the non-obvious bits.
The full input schema for every tool is already visible to you in the tool
list — don't re-derive it.

### Create a Note

Use `mcp__obsidian__file_create` with `name` (no extension — `.md` is
auto-appended), `path` (the PARA-folder path inside the vault), and
`content` including YAML frontmatter with at least `created` from
`date_time`. The server adds `silent` automatically; you never need to.
Place the note in the correct PARA folder — ask the user if classification
is ambiguous.

### Daily Journal

- `mcp__obsidian__daily_read` — read today's note.
- `mcp__obsidian__daily_append` / `daily_prepend` — add content. These
  auto-create today's note from the user's Daily Notes template if it
  doesn't exist yet.
- Use `daily_append` to add entries under a timestamped heading derived
  from `date_time`. Read first before appending if you need to avoid
  duplicating sections.

### Search / Find Information

- `mcp__obsidian__search` with a `query` returns matching file paths.
- Pass `context: true` for grep-style line context instead of just file
  names.
- Combine with `mcp__obsidian__file_read` (by `file` for fuzzy wikilink
  match, or `path` for an exact vault-relative path) to fetch a full
  note.
- For tag-based searches, use `mcp__obsidian__tag_info` with `name`.

### Restructure / Move Notes

- `mcp__obsidian__file_move` with `to=<dest-folder>` moves a note and
  updates all internal links automatically.
- When archiving a completed project, move the entire project folder
  content into `4-Archives/`.
- When restructuring, briefly state your PARA classification reasoning
  to the user.

### Read a Note

`mcp__obsidian__file_read` accepts either `file` (fuzzy wikilink match,
no path or extension) or `path` (exact vault-relative path including
`.md`).

### List & Explore

- `mcp__obsidian__file_list` with `folder`, optional `sort=modified`,
  `limit`.
- `mcp__obsidian__folder_list` with `folder`.
- `mcp__obsidian__tags_list` with `sort=count` — scope with a `file`
  or `path` for reliable vault-wide output (see Gotchas).
- `mcp__obsidian__tasks_list` with `todo: true` and either `file`,
  `path`, or `daily: true`.
- `mcp__obsidian__outline` with `file` for the heading tree of a note.
- `mcp__obsidian__wordcount`, `mcp__obsidian__backlinks`,
  `mcp__obsidian__links_outgoing` for additional structure queries.

### Properties / Metadata

- `mcp__obsidian__properties_list` with a `path` (scoping matters — see
  Gotchas). The server handles `format=json` for you.
- `mcp__obsidian__property_read` / `property_set` / `property_remove`
  for per-key reads and writes. `property_set` takes `name`, `value`,
  `type` (text / list / number / checkbox / date / datetime), and a
  file reference.

## Response Style

- When showing note contents to the user, format them cleanly.
- When creating or modifying notes, confirm what you did with the file
  path.
- When classifying into PARA, briefly state your reasoning.
- Keep responses concise — the user is busy.
