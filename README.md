# MCP Bash Obsidian CLI

A slim MCP server for the Obsidian CLI, written in Bash — no runtime
dependencies beyond `bash`, coreutils, and `jq`.

## Why?

A bash-based MCP server using stdio transport is one of the simplest ways
to give a local LLM access to an Obsidian vault — no HTTP overhead, just a
lightweight script that speaks MCP over stdin/stdout and wraps the Obsidian
CLI.

## Quick start

Install as a Claude Code plugin:

```text
/plugin marketplace add KingOfKalk/mcp-bash-obsidian-cli
/plugin install obsidian@kingofkalk-obsidian
```

Set your vault and start Claude Code:

```sh
export OBSIDIAN_VAULT=MyVault
```

For manual installation, alternative MCP clients, or detailed
configuration see the guides below.

## Documentation

| Guide | Contents |
|-------|----------|
| [Installation](docs/Installation.md) | Requirements, plugin install, manual clone, verification |
| [Configuration](docs/Config.md) | Environment variables, MCP client setup, tool limiting |
| [MCP Integration](docs/MCP.md) | Protocol details, bundled skills, tool inventory |
| [Testing](docs/Test.md) | Running tests, test coverage, mock setup, CI |

## Limitations

This MCP server is pinned to a single Obsidian vault per instance. To
access multiple vaults, register multiple `mcpServers` entries. See
[Configuration](docs/Config.md#limitations) for details.

## External references

- [Obsidian CLI — Help](https://obsidian.md/help/cli)
- [Obsidian CLI — source (GitHub)](https://github.com/obsidianmd/obsidian-help/blob/master/en/Extending%20Obsidian/Obsidian%20CLI.md)
