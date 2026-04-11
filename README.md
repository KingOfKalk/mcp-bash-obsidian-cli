# MCP Bash Obsidian CLI

A slim MCP for Obsidian CLI running in Bash

## Why?

A bash-based MCP server using stdio transport is one of the simplest ways
to give a local LLM access to an Obsidian vault — no runtime dependencies, no HTTP overhead,
just a lightweight script that speaks MCP over stdin/stdout and wraps the Obsidian CLI.
