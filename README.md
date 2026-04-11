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

Clone the repo:

```sh
git clone https://github.com/KingOfKalk/mcp_bash_obsidian_cli.git
cd mcp_bash_obsidian_cli
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
