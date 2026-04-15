# Changelog

## [1.0.0](https://github.com/KingOfKalk/mcp-bash-obsidian-cli/compare/v0.5.1...v1.0.0) (2026-04-15)


### ⚠ BREAKING CHANGES

* the mcpServers key in .claude-plugin/plugin.json and in user MCP client configs (.mcp.json, ~/.claude.json, etc.) has been renamed from "obsidian" to "cli". Users must update their existing entries and restart their MCP client.

### Features

* rename mcp server key from "obsidian" to "cli" ([#26](https://github.com/KingOfKalk/mcp-bash-obsidian-cli/issues/26)) ([e291930](https://github.com/KingOfKalk/mcp-bash-obsidian-cli/commit/e2919304c5561c5eaf250ef1305bbff77e41bce3))

## [0.5.1](https://github.com/KingOfKalk/mcp-bash-obsidian-cli/compare/v0.5.0...v0.5.1) (2026-04-15)


### Bug Fixes

* rename plugin to obsidian for clearer slash-command labels ([#24](https://github.com/KingOfKalk/mcp-bash-obsidian-cli/issues/24)) ([4776273](https://github.com/KingOfKalk/mcp-bash-obsidian-cli/commit/4776273441e6b1ebb19393f786794491fdd34d59))

## [0.5.0](https://github.com/KingOfKalk/mcp-bash-obsidian-cli/compare/v0.4.0...v0.5.0) (2026-04-15)


### Features

* **skills:** bundle vault and daily skills using MCP tools ([#21](https://github.com/KingOfKalk/mcp-bash-obsidian-cli/issues/21)) ([989468f](https://github.com/KingOfKalk/mcp-bash-obsidian-cli/commit/989468f9ccf0425215fe378db3857e70a5afde7d))

## [0.4.0](https://github.com/KingOfKalk/mcp-bash-obsidian-cli/compare/v0.3.1...v0.4.0) (2026-04-15)


### Features

* add debug tool reporting effective env configuration ([#17](https://github.com/KingOfKalk/mcp-bash-obsidian-cli/issues/17)) ([01ec2b7](https://github.com/KingOfKalk/mcp-bash-obsidian-cli/commit/01ec2b7727a602909ca046990eab3ff7b1b63451))

## [0.3.1](https://github.com/KingOfKalk/mcp-bash-obsidian-cli/compare/v0.3.0...v0.3.1) (2026-04-15)


### Bug Fixes

* **plugin:** provide defaults for MCP env var expansion ([#15](https://github.com/KingOfKalk/mcp-bash-obsidian-cli/issues/15)) ([3973601](https://github.com/KingOfKalk/mcp-bash-obsidian-cli/commit/3973601dc819959f6763876727bb73fa612e0f51))

## [0.3.0](https://github.com/KingOfKalk/mcp_bash_obsidian_cli/compare/v0.2.0...v0.3.0) (2026-04-11)


### Features

* **mcp:** add date_time tool for current date/time lookups ([#9](https://github.com/KingOfKalk/mcp_bash_obsidian_cli/issues/9)) ([148f459](https://github.com/KingOfKalk/mcp_bash_obsidian_cli/commit/148f4594098649be52ba071dbf0112c734912a9d))

## [0.2.0](https://github.com/KingOfKalk/mcp_bash_obsidian_cli/compare/v0.1.0...v0.2.0) (2026-04-11)


### Features

* Add continuous integration workflow ([#3](https://github.com/KingOfKalk/mcp_bash_obsidian_cli/issues/3)) ([e46d912](https://github.com/KingOfKalk/mcp_bash_obsidian_cli/commit/e46d9129e5092874c040c2c48385ad6766323933))
