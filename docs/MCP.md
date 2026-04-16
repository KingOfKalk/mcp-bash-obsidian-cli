# MCP Integration

## Protocol

This server implements the
[Model Context Protocol](https://modelcontextprotocol.io/) (MCP) over
**stdio transport** using **JSON-RPC 2.0**.

- Protocol version: `2024-11-05`
- Server name: `obsidian-mcp`
- Transport: stdin/stdout (one JSON-RPC message per line)

The server is typically launched by an MCP client via an `mcp.json`
configuration file. See
[Configuration](Config.md#configure-your-mcp-client) for setup details.

## Server capabilities

The server advertises `tools` capability during `initialize`. It does not
currently advertise `resources` or `prompts`.

## Bundled skills (Claude Code plugin)

Installing the plugin also bundles two skills under `skills/` that Claude
Code auto-discovers:

- **`vault`** — general-purpose Obsidian interaction: create/read/search/
  edit notes, PARA-aware organization, tag and task queries. Triggers on
  mentions of Obsidian, vaults, notes, PARA, and similar.
- **`daily`** — morning planning and evening review workflows for the
  user's daily journal. Depends on `vault`.

Both skills drive the `mcp__obsidian__*` tools exposed by this server, so
they activate automatically whenever the plugin is installed — no extra
configuration required.

## Available tools

The server exposes **67 tools** across 11 feature categories. Each
category can be individually enabled or disabled via the `--features` flag
(see [Configuration — Limiting exposed tools](Config.md#limiting-exposed-tools)).

| Category | Tools | Description |
|----------|------:|-------------|
| `files` | 16 | File/folder CRUD, search, outline, wordcount |
| `dailies` | 5 | Daily notes (read, path, append, prepend, open) |
| `metadata` | 7 | Properties, tags, aliases |
| `tasks` | 2 | Task listing and updates |
| `bookmarks` | 2 | Bookmark listing and creation |
| `links` | 5 | Backlinks, outgoing, unresolved, orphans, dead-ends |
| `templates` | 3 | Template listing, reading, insertion |
| `navigate` | 12 | UI open, random notes, recents, web viewer, workspace, tabs |
| `develop` | 6 | Command palette, hotkeys, debug, date/time |
| `history` | 5 | File diff, local recovery versions |
| `bases` | 4 | Obsidian Bases (database views and queries) |

## External documentation

This MCP server wraps the official Obsidian CLI. Reference documentation:

- [Obsidian CLI — Help](https://obsidian.md/help/cli) — official command reference
- [Obsidian CLI — source (GitHub)](https://github.com/obsidianmd/obsidian-help/blob/master/en/Extending%20Obsidian/Obsidian%20CLI.md) — the same docs as browsable Markdown
