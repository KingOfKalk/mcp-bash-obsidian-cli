# Installation

## Requirements

- [Obsidian](https://obsidian.md) 1.12.7 or newer with the
  [Obsidian CLI](https://obsidian.md/help/cli) enabled
- `bash` 3.2 or newer
- coreutils
- `jq`

## Option 1: Claude Code plugin marketplace

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

See [Configuration](Config.md) for environment variable details and
persistent settings, and [MCP Integration](MCP.md) for bundled skills.

## Option 2: Manual clone

Clone the repo:

```sh
git clone https://github.com/KingOfKalk/mcp-bash-obsidian-cli.git
cd mcp-bash-obsidian-cli
```

Note the absolute path to `obsidian-mcp.sh` — you'll need it for your
[MCP client configuration](Config.md#configure-your-mcp-client).

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

For detailed test information, see [Testing](Test.md).
