# Configuration

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OBSIDIAN_VAULT` | *(required)* | Name of the Obsidian vault to pin to |
| `OBSIDIAN_BIN` | `obsidian` | Path to the `obsidian` binary |
| `OBSIDIAN_MCP_LOG` | `/tmp/obsidian-mcp.log` | Log file path |

The vault can also be passed as the first positional argument to
`obsidian-mcp.sh`; the positional argument takes precedence over the env
var.

## Claude Code settings files

If you'd rather not re-export shell vars every time you start Claude
Code, you can set `OBSIDIAN_VAULT` (and friends) via a top-level `env`
block in Claude Code's settings files. Two scopes are supported:

**Per-project — `$PROJECT_ROOT/.claude/settings.local.json`**

Pin a specific vault to a specific project/repo. Create (or edit) the
project-scope settings file and add a top-level `env` block:

```json
{
  "env": {
    "OBSIDIAN_VAULT": "Notes",
    "OBSIDIAN_MCP_LOG": ".obsidian_mcp_log.txt"
  }
}
```

This is the recommended path when you want different vaults for
different repos — add the file to `.gitignore` (or keep it locally
only) so each developer can point at their own vault.

**Global default — `$HOME/.claude/settings.json`**

Set a fallback that applies everywhere Claude Code runs. Same top-level
`env` shape, just in the user-scope settings file:

```json
{
  "env": {
    "OBSIDIAN_VAULT": "Notes",
    "OBSIDIAN_MCP_LOG": ".obsidian_mcp_log.txt"
  }
}
```

Precedence: the project `settings.local.json` overrides the user
`settings.json` when both are present.

Restart Claude Code after editing either file so the env is picked up.
Verify with `/mcp`, and/or call the server's debug tool to confirm the
effective env configuration.

## Configure your MCP client

MCP clients launch stdio servers via an `mcp.json` (or equivalent) config
file. Add an entry for this server under `mcpServers`:

```json
{
  "mcpServers": {
    "cli": {
      "command": "/absolute/path/to/obsidian-mcp.sh",
      "args": ["MyVault"],
      "env": {
        "OBSIDIAN_BIN": "/usr/local/bin/obsidian",
        "OBSIDIAN_MCP_LOG": "/tmp/obsidian-mcp.log"
      }
    }
  }
}
```

Notes:

- Replace `MyVault` with the exact name of an existing Obsidian vault.
  Each server instance is pinned to exactly one vault — see
  [Limitations](#limitations) for details on running multiple vaults.
- `command` should be an **absolute path**; most MCP clients don't resolve
  binaries against your shell `PATH`.
- The `env` block is optional. Only set `OBSIDIAN_BIN` if the `obsidian`
  binary isn't already on the launching client's `PATH`. `OBSIDIAN_MCP_LOG`
  defaults to `/tmp/obsidian-mcp.log`.

### Where to put the snippet

- **Claude Code (project scope):** `.mcp.json` at the repo root, or run
  `claude mcp add cli /absolute/path/to/obsidian-mcp.sh MyVault`.
- **Claude Code (user scope):** the `mcpServers` section of `~/.claude.json`.
- **Claude Code (plugin env, per project):** top-level `env` block in
  `$PROJECT_ROOT/.claude/settings.local.json`. See
  [Claude Code settings files](#claude-code-settings-files) above.
- **Claude Code (plugin env, global default):** top-level `env` block in
  `$HOME/.claude/settings.json`. See the same section.
- **Claude Desktop:** `claude_desktop_config.json`
  - macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
  - Windows: `%APPDATA%\Claude\claude_desktop_config.json`

Restart your MCP client after editing the config so it picks up the new
server.

## Limiting exposed tools

By default, the server exposes all 67 tools. If you're working with a
smaller context window, you can restrict the tool set with the `--features`
flag to reduce token overhead:

```sh
# Only file operations (16 tools instead of 67)
./obsidian-mcp.sh MyVault --features=files

# Typical daily workflow
./obsidian-mcp.sh MyVault --features=files,dailies,tasks

# Vault analysis
./obsidian-mcp.sh MyVault --features=files,metadata,links
```

In an `mcp.json` config, pass the flag via `args`:

```json
{
  "mcpServers": {
    "cli": {
      "command": "/absolute/path/to/obsidian-mcp.sh",
      "args": ["MyVault", "--features=files,dailies,tasks"]
    }
  }
}
```

Without `--features` (or with `--features=all`), every tool is available —
the same behavior as before this flag existed.

### Feature categories

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

Tools that are not enabled are hidden from `tools/list` and rejected on
`tools/call`, so the model never sees them.

## Limitations

**One vault per server instance.** This MCP server is pinned to a
single Obsidian vault at startup (via the positional `<vault-name>`
argument or the `OBSIDIAN_VAULT` env var). It does not switch vaults
at runtime and does not expose multiple vaults from one instance. To
access more than one vault in parallel, register multiple `mcpServers`
entries — one per vault — each pointing at `obsidian-mcp.sh` with a
different `OBSIDIAN_VAULT`.
