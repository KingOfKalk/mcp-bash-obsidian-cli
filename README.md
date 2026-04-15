# MCP Bash Obsidian CLI

A slim MCP for Obsidian CLI running in Bash

## Why?

A bash-based MCP server using stdio transport is one of the simplest ways
to give a local LLM access to an Obsidian vault — no runtime dependencies, no HTTP overhead,
just a lightweight script that speaks MCP over stdin/stdout and wraps the Obsidian CLI.

## Requirements

- `bash` 3.2 or newer
- coreutils
- `jq`
- The [Obsidian CLI](https://github.com/Yakitrak/obsidian-cli) on your `PATH`
  (or pointed to via the `OBSIDIAN_BIN` environment variable)

## Installation

You have two options: install as a **Claude Code plugin** from the bundled
marketplace (recommended for Claude Code users), or clone the repo and wire
the script into your MCP client manually.

### Option 1: Claude Code plugin marketplace

This repo ships a [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces)
manifest under `.claude-plugin/`, so you can install it directly inside Claude
Code:

```text
/plugin marketplace add KingOfKalk/mcp-bash-obsidian-cli
/plugin install mcp-bash-cli@kingofkalk-obsidian
```

Before starting Claude Code, export the vault name (and optionally override
the Obsidian binary path or log file) so the plugin's MCP server knows which
vault to pin to:

```sh
export OBSIDIAN_VAULT=MyVault
# optional:
export OBSIDIAN_BIN=/usr/local/bin/obsidian
export OBSIDIAN_MCP_LOG=/tmp/obsidian-mcp.log
```

The plugin registers a single MCP server (`obsidian`) that runs
`obsidian-mcp.sh` out of the plugin cache. To pin to a different vault,
change `OBSIDIAN_VAULT` and restart Claude Code. For multiple vaults in
parallel, prefer the manual configuration in Option 2.

#### Per-project vault overrides (Claude Code)

If you'd rather not re-export shell vars every time you switch projects,
Claude Code can inject MCP env vars on a per-project basis via
`~/.claude/settings.json`. This is the recommended path for pinning a
different vault to each project:

```json
{
  "projects": {
    "/path/to/project": {
      "mcpServers": {
        "plugin:mcp-bash-cli:obsidian": {
          "env": {
            "OBSIDIAN_VAULT": "Notes"
          }
        }
      }
    }
  }
}
```

Restart Claude Code after editing the file so the override is picked up.
Verify with `/mcp`, and/or call the server's debug tool to confirm the
effective env configuration.

**Gotchas** — all three of these fail *silently*, with no warning from
Claude Code or the server, so double-check the key format:

- **The server key must exactly match the name shown by `/mcp`**, colons
  and all (`plugin:mcp-bash-cli:obsidian`). Underscore variants such as
  `plugin_mcp-bash-cli_obsidian` are silently ignored.
- **`mcpServers` in `.claude/settings.local.json` is not honored** for MCP
  env overrides — put the block in `~/.claude/settings.json` instead.
- **A top-level `env` block in `.claude/settings.local.json`** only sets
  Claude Code's own session env vars; it does *not* propagate into the MCP
  server process, so `OBSIDIAN_VAULT` set there won't reach the plugin.

### Option 2: Manual clone

Clone the repo:

```sh
git clone https://github.com/KingOfKalk/mcp-bash-obsidian-cli.git
cd mcp-bash-obsidian-cli
```

Note the absolute path to `obsidian-mcp.sh` — you'll need it for your MCP
client config below.

## Configure your MCP client

MCP clients launch stdio servers via an `mcp.json` (or equivalent) config
file. Add an entry for this server under `mcpServers`:

```json
{
  "mcpServers": {
    "obsidian": {
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

- Replace `MyVault` with the exact name of an existing Obsidian vault. The
  server is pinned to a single vault per entry — register multiple
  `mcpServers` entries if you want access to more than one.
- `command` should be an **absolute path**; most MCP clients don't resolve
  binaries against your shell `PATH`.
- The `env` block is optional. Only set `OBSIDIAN_BIN` if the `obsidian`
  binary isn't already on the launching client's `PATH`. `OBSIDIAN_MCP_LOG`
  defaults to `/tmp/obsidian-mcp.log`.

### Where to put the snippet

- **Claude Code (project scope):** `.mcp.json` at the repo root, or run
  `claude mcp add obsidian /absolute/path/to/obsidian-mcp.sh MyVault`.
- **Claude Code (user scope):** the `mcpServers` section of `~/.claude.json`.
- **Claude Code (plugin env overrides, per project):** use the
  `projects.<path>.mcpServers.<server>.env` block in
  `~/.claude/settings.json`. See
  [Per-project vault overrides](#per-project-vault-overrides-claude-code)
  above.
- **Claude Desktop:** `claude_desktop_config.json`
  - macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
  - Windows: `%APPDATA%\Claude\claude_desktop_config.json`

Restart your MCP client after editing the config so it picks up the new
server.

## Verifying

Confirm the script runs:

```sh
./obsidian-mcp.sh --version
```

Run the bundled test suite (uses `mock_obsidian.sh`, so it doesn't touch a
real vault):

```sh
./test.sh
```
