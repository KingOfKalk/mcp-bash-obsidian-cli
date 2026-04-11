# CLAUDE.md

Guidance for Claude Code when working in this repo.

## Project

A slim MCP server for the Obsidian CLI, written in Bash and speaking MCP over
stdio. Entry point: `obsidian-mcp.sh`. Runtime deps: `bash`, coreutils, `jq`.

## Commands

- Run the server: `./obsidian-mcp.sh <vault-name>`
- Run tests: `./test.sh` (uses `mock_obsidian.sh` as a stub for the real CLI)

## Conventions

- **Conventional Commits** are required (`feat:`, `fix:`, `chore:`, `docs:`,
  `refactor:`, `test:`, etc.). release-please parses commit messages to drive
  version bumps and changelogs, so message quality matters.
- **No AI attribution** in commits: do not add `Co-Authored-By: Claude`,
  "Generated with Claude Code" footers, or similar. Plain conventional commit
  messages only.

## Releases

Releases are automated by [release-please](https://github.com/googleapis/release-please).
Do **not** manually edit the version in `obsidian-mcp.sh` (the
`# x-release-please-version` marker) or hand-write `CHANGELOG.md`; release-please
owns both.

## CI

CI runs via a GitHub Actions workflow. Don't try to reproduce CI locally beyond
running `./test.sh`.
