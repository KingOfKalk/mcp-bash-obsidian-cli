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
/plugin install obsidian@kingofkalk-obsidian
```

or in your terminal:

```bash
claude plugin marketplace add KingOfKalk/mcp-bash-obsidian-cli
claude plugin install obsidian@kingofkalk-obsidian
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

#### Configuring the vault and other env vars (Claude Code)

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

#### Bundled skills

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
  [Configuring the vault and other env vars](#configuring-the-vault-and-other-env-vars-claude-code)
  above.
- **Claude Code (plugin env, global default):** top-level `env` block in
  `$HOME/.claude/settings.json`. See the same section.
- **Claude Desktop:** `claude_desktop_config.json`
  - macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
  - Windows: `%APPDATA%\Claude\claude_desktop_config.json`

Restart your MCP client after editing the config so it picks up the new
server.

## Limitations

- **One vault per server instance.** This MCP server is pinned to a
  single Obsidian vault at startup (via the positional `<vault-name>`
  argument or the `OBSIDIAN_VAULT` env var). It does not switch vaults
  at runtime and does not expose multiple vaults from one instance. To
  access more than one vault in parallel, register multiple `mcpServers`
  entries — one per vault — each pointing at `obsidian-mcp.sh` with a
  different `OBSIDIAN_VAULT`.

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
