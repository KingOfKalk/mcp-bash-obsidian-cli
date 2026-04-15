#!/usr/bin/env bash
#
# obsidian-mcp.sh — Single-file MCP server (stdio transport) wrapping the
# Obsidian CLI for one pinned vault.
#
# Usage (typically from mcp.json):
#   obsidian-mcp.sh <vault-name>
#
# Env vars:
#   OBSIDIAN_BIN      path to the obsidian binary (default: obsidian)
#   OBSIDIAN_MCP_LOG  log file (default: /tmp/obsidian-mcp.log)
#
# Compatibility: bash 3.2+, BSD/GNU coreutils, jq.

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Version (managed by release-please)
# ---------------------------------------------------------------------------
VERSION="1.1.0" # x-release-please-version

print_version() {
    printf 'obsidian-mcp.sh %s\n' "$VERSION"
}

print_usage() {
    cat <<EOF
obsidian-mcp.sh ${VERSION} — MCP server (stdio) wrapping the Obsidian CLI.

Usage:
  obsidian-mcp.sh <vault-name>
  obsidian-mcp.sh --help | -h
  obsidian-mcp.sh --version | -v

Arguments:
  <vault-name>      Name of the Obsidian vault to pin this server to.

Environment:
  OBSIDIAN_BIN      Path to the obsidian binary (default: obsidian).
  OBSIDIAN_MCP_LOG  Log file path (default: /tmp/obsidian-mcp.log).

The server speaks MCP over stdin/stdout and is normally launched by an MCP
client (e.g. via mcp.json), not run interactively.
EOF
}

# ---------------------------------------------------------------------------
# 1. Config from argv + env
# ---------------------------------------------------------------------------

case "${1:-}" in
    -h|--help)
        print_usage
        exit 0
        ;;
    -v|--version)
        print_version
        exit 0
        ;;
    ""|-*)
        print_usage >&2
        exit 2
        ;;
esac

OBSIDIAN_VAULT="$1"
shift

OBSIDIAN_BIN="${OBSIDIAN_BIN:-obsidian}"
OBSIDIAN_MCP_LOG="${OBSIDIAN_MCP_LOG:-/tmp/obsidian-mcp.log}"

# ---------------------------------------------------------------------------
# 2. Logging helper (never writes to stdout)
# ---------------------------------------------------------------------------

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$OBSIDIAN_MCP_LOG" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 3. JSON-RPC response helpers
# ---------------------------------------------------------------------------

# send_result <id-as-json> <result-as-json>
send_result() {
    local id="$1" result="$2"
    jq -nc --argjson id "$id" --argjson result "$result" \
        '{jsonrpc:"2.0", id:$id, result:$result}'
}

# send_error <id-as-json> <code> <message>
send_error() {
    local id="$1" code="$2" msg="$3"
    jq -nc --argjson id "$id" --argjson code "$code" --arg msg "$msg" \
        '{jsonrpc:"2.0", id:$id, error:{code:$code, message:$msg}}'
}

# mcp_content <text> -> {"content":[{"type":"text","text":...}]}
mcp_content() {
    jq -nc --arg t "$1" '{content:[{type:"text", text:$t}]}'
}

# mcp_error_content <text> -> tool error result per MCP spec:
#   {"content":[{"type":"text","text":...}], "isError": true}
# Used for tool *execution* failures (the tool ran but errored), so the
# model can see what went wrong and recover. Protocol-level errors
# (unknown method, bad params) still go through send_error.
mcp_error_content() {
    jq -nc --arg t "$1" '{content:[{type:"text", text:$t}], isError:true}'
}

# ---------------------------------------------------------------------------
# 4. Tool registry (heredoc)
# ---------------------------------------------------------------------------

TOOLS_JSON=$(cat <<'JSON_EOF'
{
  "tools": [
    {
      "name": "file_info",
      "description": "Get file metadata (size, dates) for a note in the vault. Defaults to the active file if no file/path is given — use this to inspect whatever the user is currently viewing.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string", "description": "File name (with or without .md)"},
          "path": {"type": "string", "description": "Full path inside the vault"}
        }
      }
    },
    {
      "name": "file_list",
      "description": "List files in the vault or a folder.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "folder": {"type": "string"},
          "ext": {"type": "string", "description": "Filter by extension (e.g. md)"},
          "sort": {"type": "string"},
          "limit": {"type": "number"},
          "total": {"type": "boolean"}
        }
      }
    },
    {
      "name": "file_read",
      "description": "Read the full contents of a file in the vault. Defaults to the currently active file in Obsidian if no file/path is given — use this to read whatever note the user is looking at right now.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"}
        }
      }
    },
    {
      "name": "folder_info",
      "description": "Get info about a folder (file/folder/size counts).",
      "inputSchema": {
        "type": "object",
        "properties": {
          "path": {"type": "string"},
          "info": {"type": "string", "enum": ["files", "folders", "size"]}
        },
        "required": ["path"]
      }
    },
    {
      "name": "folder_list",
      "description": "List folders in the vault.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "folder": {"type": "string"},
          "total": {"type": "boolean"}
        }
      }
    },
    {
      "name": "search",
      "description": "Full-text search across the vault. Returns JSON results. Set context=true for surrounding lines.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "query": {"type": "string"},
          "path": {"type": "string"},
          "limit": {"type": "number"},
          "context": {"type": "boolean", "default": false},
          "case_sensitive": {"type": "boolean"}
        },
        "required": ["query"]
      }
    },
    {
      "name": "daily_read",
      "description": "Read today's daily note.",
      "inputSchema": {"type": "object", "properties": {}}
    },
    {
      "name": "daily_path",
      "description": "Get the path to today's daily note.",
      "inputSchema": {"type": "object", "properties": {}}
    },
    {
      "name": "properties_list",
      "description": "List frontmatter properties (vault-wide or per-file). Defaults to the active file if no file/path is given. Note: vault-wide listings may be empty on some CLI versions; pass a file or path for reliable results.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "name": {"type": "string"},
          "sort": {"type": "string"},
          "total": {"type": "boolean"},
          "counts": {"type": "boolean"},
          "active": {"type": "boolean"}
        }
      }
    },
    {
      "name": "property_read",
      "description": "Read a single frontmatter property value from a file.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "file": {"type": "string"},
          "path": {"type": "string"}
        },
        "required": ["name"]
      }
    },
    {
      "name": "tags_list",
      "description": "List tags. Note: vault-wide listings may be empty on some CLI versions; pass a file for reliable results.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "sort": {"type": "string"},
          "total": {"type": "boolean"},
          "counts": {"type": "boolean"}
        }
      }
    },
    {
      "name": "tag_info",
      "description": "Get info about a single tag (files using it).",
      "inputSchema": {
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "total": {"type": "boolean"},
          "verbose": {"type": "boolean"}
        },
        "required": ["name"]
      }
    },
    {
      "name": "tasks_list",
      "description": "List tasks. Defaults to the active file if no file/path is given. Note: without file scope, may return empty on some CLI versions; pass file or path for reliable results.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "status": {"type": "string"},
          "total": {"type": "boolean"},
          "done": {"type": "boolean"},
          "todo": {"type": "boolean"},
          "verbose": {"type": "boolean"},
          "active": {"type": "boolean"},
          "daily": {"type": "boolean"}
        }
      }
    },
    {
      "name": "backlinks",
      "description": "List incoming links to a file. Defaults to the active file if no file/path is given.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "counts": {"type": "boolean"},
          "total": {"type": "boolean"}
        }
      }
    },
    {
      "name": "links_outgoing",
      "description": "List outgoing links from a file. Defaults to the active file if no file/path is given.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "total": {"type": "boolean"}
        }
      }
    },
    {
      "name": "links_unresolved",
      "description": "List unresolved (broken) links across the vault.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "total": {"type": "boolean"},
          "counts": {"type": "boolean"},
          "verbose": {"type": "boolean"}
        }
      }
    },
    {
      "name": "links_orphans",
      "description": "List files with no incoming links.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "total": {"type": "boolean"}
        }
      }
    },
    {
      "name": "links_deadends",
      "description": "List files with no outgoing links.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "total": {"type": "boolean"}
        }
      }
    },
    {
      "name": "bookmarks_list",
      "description": "List vault bookmarks.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "total": {"type": "boolean"},
          "verbose": {"type": "boolean"}
        }
      }
    },
    {
      "name": "outline",
      "description": "Get the heading outline of a file. Defaults to the active file if no file/path is given.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "total": {"type": "boolean"}
        }
      }
    },
    {
      "name": "wordcount",
      "description": "Get word and character counts for a file. Defaults to the active file if no file/path is given.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"}
        }
      }
    },
    {
      "name": "templates_list",
      "description": "List available templates in the vault.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "total": {"type": "boolean"}
        }
      }
    },
    {
      "name": "template_read",
      "description": "Read template contents.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "resolve": {"type": "boolean"}
        },
        "required": ["name"]
      }
    },
    {
      "name": "aliases_list",
      "description": "List aliases for a file (or vault-wide).",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "total": {"type": "boolean"},
          "verbose": {"type": "boolean"},
          "active": {"type": "boolean"}
        }
      }
    },
    {
      "name": "file_create",
      "description": "Create a new file. Always runs with 'silent' so the GUI is not opened. If overwrite=true, content must be non-empty (otherwise the file would be truncated to 0 bytes).",
      "inputSchema": {
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "path": {"type": "string"},
          "content": {"type": "string"},
          "template": {"type": "string"},
          "overwrite": {"type": "boolean"}
        },
        "required": ["name"]
      }
    },
    {
      "name": "file_append",
      "description": "Append content to a file.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "content": {"type": "string"},
          "inline": {"type": "boolean"}
        },
        "required": ["content"]
      }
    },
    {
      "name": "file_prepend",
      "description": "Prepend content after frontmatter.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "content": {"type": "string"},
          "inline": {"type": "boolean"}
        },
        "required": ["content"]
      }
    },
    {
      "name": "file_move",
      "description": "Move a file to another folder (updates links).",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "to": {"type": "string"}
        },
        "required": ["to"]
      }
    },
    {
      "name": "file_rename",
      "description": "Rename a file in place (updates links).",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "name": {"type": "string"}
        },
        "required": ["name"]
      }
    },
    {
      "name": "file_delete",
      "description": "Delete a file (moves to system trash by default; pass permanent=true to skip the trash).",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "permanent": {"type": "boolean"}
        }
      }
    },
    {
      "name": "daily_append",
      "description": "Append content to today's daily note.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "content": {"type": "string"},
          "inline": {"type": "boolean"}
        },
        "required": ["content"]
      }
    },
    {
      "name": "daily_prepend",
      "description": "Prepend content to today's daily note (after frontmatter).",
      "inputSchema": {
        "type": "object",
        "properties": {
          "content": {"type": "string"},
          "inline": {"type": "boolean"}
        },
        "required": ["content"]
      }
    },
    {
      "name": "property_set",
      "description": "Set a frontmatter property. Note: may no-op if the file was modified externally and Obsidian's cache is stale.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "value": {"type": "string"},
          "type": {"type": "string", "enum": ["text", "list", "number", "checkbox", "date", "datetime"]},
          "file": {"type": "string"},
          "path": {"type": "string"}
        },
        "required": ["name", "value"]
      }
    },
    {
      "name": "property_remove",
      "description": "Remove a frontmatter property from a file.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "file": {"type": "string"},
          "path": {"type": "string"}
        },
        "required": ["name"]
      }
    },
    {
      "name": "task_update",
      "description": "Update a task's status. Reference the task by ref ('path:line') or by file+line.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "ref": {"type": "string", "description": "path:line"},
          "file": {"type": "string"},
          "path": {"type": "string"},
          "line": {"type": "number"},
          "status": {"type": "string"},
          "toggle": {"type": "boolean"},
          "done": {"type": "boolean"},
          "todo": {"type": "boolean"}
        }
      }
    },
    {
      "name": "bookmark_add",
      "description": "Add a bookmark to a file, search, or URL.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "subpath": {"type": "string"},
          "search": {"type": "string"},
          "url": {"type": "string"},
          "title": {"type": "string"}
        }
      }
    },
    {
      "name": "file_open",
      "description": "Open a file in the Obsidian UI for the user. Defaults to the active file if no file/path is given. Use newtab=true to open in a new tab.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "newtab": {"type": "boolean"}
        }
      }
    },
    {
      "name": "file_unique",
      "description": "Create a note with a collision-free name (auto-suffixes if the name already exists). Optionally open it in the UI.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "name": {"type": "string"},
          "content": {"type": "string"},
          "paneType": {"type": "string"},
          "open": {"type": "boolean"}
        }
      }
    },
    {
      "name": "random_open",
      "description": "Open a random note in the Obsidian UI.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "folder": {"type": "string"},
          "newtab": {"type": "boolean"}
        }
      }
    },
    {
      "name": "random_read",
      "description": "Read a random note (without opening it in the UI).",
      "inputSchema": {
        "type": "object",
        "properties": {
          "folder": {"type": "string"}
        }
      }
    },
    {
      "name": "recents_list",
      "description": "List recently opened files. Useful for awareness of what the user has been working on.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "total": {"type": "boolean"}
        }
      }
    },
    {
      "name": "web_open",
      "description": "Open a URL in Obsidian's web viewer.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "url": {"type": "string"},
          "newtab": {"type": "boolean"}
        },
        "required": ["url"]
      }
    },
    {
      "name": "search_open",
      "description": "Open the Obsidian search panel, optionally prefilled with a query.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "query": {"type": "string"}
        }
      }
    },
    {
      "name": "daily_open",
      "description": "Open today's daily note in the Obsidian UI (the 'daily_read' tool only returns its text).",
      "inputSchema": {
        "type": "object",
        "properties": {
          "paneType": {"type": "string"}
        }
      }
    },
    {
      "name": "workspace_tree",
      "description": "Show the live workspace layout tree: every pane, split, and tab the user currently has open. The most complete 'what is the user looking at' signal.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "ids": {"type": "boolean"}
        }
      }
    },
    {
      "name": "tabs_list",
      "description": "List currently open tabs (and which tab is active).",
      "inputSchema": {
        "type": "object",
        "properties": {
          "ids": {"type": "boolean"}
        }
      }
    },
    {
      "name": "tab_open",
      "description": "Open a file in a new tab, optionally in a specific pane group or view type.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "group": {"type": "string"},
          "view": {"type": "string"}
        }
      }
    },
    {
      "name": "workspaces_list",
      "description": "List saved workspaces.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "total": {"type": "boolean"}
        }
      }
    },
    {
      "name": "workspace_save",
      "description": "Save the current pane layout as a named workspace.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        },
        "required": ["name"]
      }
    },
    {
      "name": "workspace_load",
      "description": "Switch to a saved workspace by name.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        },
        "required": ["name"]
      }
    },
    {
      "name": "workspace_delete",
      "description": "Delete a saved workspace by name.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        },
        "required": ["name"]
      }
    },
    {
      "name": "commands_list",
      "description": "List available Obsidian command ids (optionally filtered). Pair with command_run to execute one.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "filter": {"type": "string"}
        }
      }
    },
    {
      "name": "command_run",
      "description": "Execute any Obsidian command by its id (e.g. 'editor:toggle-source', 'graph:open', 'app:go-back'). One tool covers every action in the command palette.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "id": {"type": "string"}
        },
        "required": ["id"]
      }
    },
    {
      "name": "hotkeys_list",
      "description": "List hotkeys for all Obsidian commands.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "verbose": {"type": "boolean"}
        }
      }
    },
    {
      "name": "hotkey_get",
      "description": "Look up the hotkey bound to a specific command id.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "id": {"type": "string"},
          "verbose": {"type": "boolean"}
        },
        "required": ["id"]
      }
    },
    {
      "name": "template_insert",
      "description": "Insert a template into the active file.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        },
        "required": ["name"]
      }
    },
    {
      "name": "file_diff",
      "description": "List or compare versions of a file from local recovery or sync history.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "from": {"type": "string"},
          "to": {"type": "string"},
          "filter": {"type": "string"}
        }
      }
    },
    {
      "name": "file_history",
      "description": "List local recovery versions for a file.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"}
        }
      }
    },
    {
      "name": "file_history_list",
      "description": "List all files that have local recovery history.",
      "inputSchema": {"type": "object", "properties": {}}
    },
    {
      "name": "file_history_read",
      "description": "Read a specific local recovery version of a file.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "version": {"type": "number"}
        }
      }
    },
    {
      "name": "file_history_restore",
      "description": "Restore a file to a specific local recovery version.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "version": {"type": "number"}
        },
        "required": ["version"]
      }
    },
    {
      "name": "bases_list",
      "description": "List all .base files in the vault.",
      "inputSchema": {"type": "object", "properties": {}}
    },
    {
      "name": "base_views",
      "description": "List views in a base file.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"}
        }
      }
    },
    {
      "name": "base_query",
      "description": "Query a base and return its results.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "view": {"type": "string"}
        }
      }
    },
    {
      "name": "base_create",
      "description": "Create a new item in a base.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "file": {"type": "string"},
          "path": {"type": "string"},
          "view": {"type": "string"},
          "name": {"type": "string"},
          "content": {"type": "string"}
        }
      }
    },
    {
      "name": "debug",
      "description": "Return the environment values the server is currently running with (vault, binary path, log path, version). Useful for troubleshooting — these are the knobs you can set via env vars before launching the server.",
      "inputSchema": {"type": "object", "properties": {}}
    },
    {
      "name": "date_time",
      "description": "Return the current date/time. With no args, returns a JSON object (iso, date, time, weekday, timezone, unix, utc). With 'format', returns a single formatted string using strftime conversion specifiers (see 'man date'). Useful for daily-note and journaling workflows.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "format": {"type": "string", "description": "strftime format string, e.g. '%Y-%m-%d %H:%M'. When present, return a plain string instead of the default JSON object."},
          "utc": {"type": "boolean", "description": "Use UTC instead of local time (default: false)."}
        }
      }
    }
  ]
}
JSON_EOF
)

# ---------------------------------------------------------------------------
# 5. CLI argument builder
# ---------------------------------------------------------------------------
#
# build_args <args-json> [--skip key1 key2 ...]
# Populates the global ARGS_OUT array with CLI tokens like "key=value" or
# bare flag tokens for boolean-true keys. Skips null/false values and any
# keys passed after --skip.
#
# Implemented with a read loop (no mapfile, for bash 3.2 compat).

ARGS_OUT=()

build_args() {
    local json="$1"
    shift
    local skip_filter='.'
    if [ "${1:-}" = "--skip" ]; then
        shift
        local k
        for k in "$@"; do
            skip_filter="$skip_filter | del(.\"$k\")"
        done
    fi

    ARGS_OUT=()
    local line
    # NUL-delimited records so values containing newlines (e.g. multiline
    # `content`) stay in a single argv element.
    while IFS= read -r -d '' line; do
        [ -z "$line" ] && continue
        ARGS_OUT+=("$line")
    done < <(printf '%s' "$json" | jq -j "
        $skip_filter
        | to_entries[]
        | select(.value != null and .value != false)
        | if (.value == true) then .key
          else \"\(.key)=\(.value|tostring)\"
          end
        | . + \"\u0000\"
    ")
}

# ---------------------------------------------------------------------------
# 6. Core CLI executor
# ---------------------------------------------------------------------------
#
# run_obsidian <command> [args...]
# Calls $OBSIDIAN_BIN with vault=$OBSIDIAN_VAULT prepended. Captures stderr
# to the log. Treats a single-line stdout starting with "Error:" as failure
# (the CLI returns 0 even on errors). On failure, the error text is printed
# to stdout and the function returns 1 so the caller can surface it to the
# MCP client.
#
# The single-line restriction matters: commands like `orphans`, `files`,
# and `deadends` emit newline-separated file lists, and a perfectly valid
# path (e.g. `Error: retry logic.md`) would otherwise trip a mid-stream
# `Error:` match and fail the whole tool call with no diagnostic. Real CLI
# errors are always a single "Error: <message>" line on stdout.

run_obsidian() {
    local cmd="$1"
    shift
    local stderr_file
    stderr_file=$(mktemp)
    local out=""
    set +e
    out=$("$OBSIDIAN_BIN" vault="$OBSIDIAN_VAULT" "$cmd" "$@" 2>"$stderr_file")
    local rc=$?
    set -e

    local err=""
    if [ -s "$stderr_file" ]; then
        err=$(cat "$stderr_file")
        log "stderr($cmd): $err"
    fi
    rm -f "$stderr_file"

    if [ $rc -ne 0 ]; then
        log "non-zero rc=$rc for $cmd"
    fi

    # Detect CLI-reported errors. The real CLI returns exit 0 even on
    # failure and prints "Error: <message>" to stdout. Only treat output
    # as an error when it is a single line with that prefix, so multi-line
    # file listings (orphans, deadends, files) aren't misclassified when a
    # path legitimately starts with "Error:".
    case "$out" in
        *$'\n'*) : ;;
        Error:*)
            log "cli-error($cmd): $out"
            printf '%s' "$out"
            return 1
            ;;
    esac

    if [ $rc -ne 0 ]; then
        # CLI exited non-zero without an "Error:" line on stdout — surface
        # whatever diagnostic we have (stderr, or a generic fallback) so
        # the caller can return it to the MCP client.
        if [ -n "$err" ]; then
            printf '%s' "$err"
        else
            printf 'CLI command %s exited with code %s' "$cmd" "$rc"
        fi
        return 1
    fi

    printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# 7. Output normalizers
# ---------------------------------------------------------------------------
#
# kv_to_json — read "key  value" lines from stdin and emit a JSON object.

kv_to_json() {
    awk '
        NF >= 2 {
            k = $1
            $1 = ""
            sub(/^[ \t]+/, "")
            printf "%s\t%s\n", k, $0
        }
    ' | jq -Rs '
        split("\n")
        | map(select(length > 0))
        | map(split("\t"))
        | map({(.[0]): .[1]})
        | add // {}
    '
}

# ---------------------------------------------------------------------------
# 8. Tool handlers
# ---------------------------------------------------------------------------
#
# Each handler takes the JSON arguments object as $1 and prints the tool's
# textual result to stdout. Failure is signalled via non-zero exit.

# ----- read tools -----

tool_file_info() {
    build_args "$1"
    run_obsidian file "${ARGS_OUT[@]}" | kv_to_json
}

tool_file_list() {
    build_args "$1"
    run_obsidian files "${ARGS_OUT[@]}"
}

tool_file_read() {
    build_args "$1"
    run_obsidian read "${ARGS_OUT[@]}"
}

tool_folder_info() {
    build_args "$1"
    run_obsidian folder "${ARGS_OUT[@]}"
}

tool_folder_list() {
    build_args "$1"
    run_obsidian folders "${ARGS_OUT[@]}"
}

tool_search() {
    local cmd="search"
    if printf '%s' "$1" | jq -e '.context == true' >/dev/null 2>&1; then
        cmd="search:context"
    fi
    # case_sensitive -> bare 'case' flag
    local args_json
    args_json=$(printf '%s' "$1" | jq -c '
        if .case_sensitive == true then . + {"case": true} else . end
        | del(.case_sensitive, .context)
    ')
    build_args "$args_json"
    ARGS_OUT+=("format=json")
    run_obsidian "$cmd" "${ARGS_OUT[@]}"
}

tool_daily_read() {
    run_obsidian daily:read
}

tool_daily_path() {
    run_obsidian daily:path
}

tool_properties_list() {
    build_args "$1"
    ARGS_OUT+=("format=json")
    run_obsidian properties "${ARGS_OUT[@]}"
}

tool_property_read() {
    build_args "$1"
    run_obsidian property:read "${ARGS_OUT[@]}"
}

tool_tags_list() {
    build_args "$1"
    ARGS_OUT+=("format=json")
    run_obsidian tags "${ARGS_OUT[@]}"
}

tool_tag_info() {
    build_args "$1"
    run_obsidian tag "${ARGS_OUT[@]}"
}

tool_tasks_list() {
    build_args "$1"
    ARGS_OUT+=("format=json")
    run_obsidian tasks "${ARGS_OUT[@]}"
}

tool_backlinks() {
    build_args "$1"
    ARGS_OUT+=("format=json")
    run_obsidian backlinks "${ARGS_OUT[@]}"
}

tool_links_outgoing() {
    build_args "$1"
    run_obsidian links "${ARGS_OUT[@]}"
}

tool_links_unresolved() {
    build_args "$1"
    ARGS_OUT+=("format=json")
    run_obsidian unresolved "${ARGS_OUT[@]}"
}

tool_links_orphans() {
    build_args "$1"
    run_obsidian orphans "${ARGS_OUT[@]}"
}

tool_links_deadends() {
    build_args "$1"
    run_obsidian deadends "${ARGS_OUT[@]}"
}

tool_bookmarks_list() {
    build_args "$1"
    ARGS_OUT+=("format=json")
    run_obsidian bookmarks "${ARGS_OUT[@]}"
}

tool_outline() {
    build_args "$1"
    ARGS_OUT+=("format=json")
    run_obsidian outline "${ARGS_OUT[@]}"
}

tool_wordcount() {
    build_args "$1"
    run_obsidian wordcount "${ARGS_OUT[@]}" | kv_to_json
}

tool_templates_list() {
    build_args "$1"
    run_obsidian templates "${ARGS_OUT[@]}"
}

tool_template_read() {
    build_args "$1"
    run_obsidian template:read "${ARGS_OUT[@]}"
}

tool_aliases_list() {
    build_args "$1"
    run_obsidian aliases "${ARGS_OUT[@]}"
}

# ----- write tools -----

tool_file_create() {
    # Safety: refuse `overwrite` without content (would truncate file to 0 bytes).
    if printf '%s' "$1" | jq -e '.overwrite == true and ((.content // "") == "")' >/dev/null 2>&1; then
        log "file_create refused: overwrite=true requires non-empty content"
        printf '%s' "refusing overwrite=true with empty content (would truncate file to 0 bytes)"
        return 1
    fi
    build_args "$1"
    ARGS_OUT+=("silent")
    run_obsidian create "${ARGS_OUT[@]}"
    echo "ok"
}

tool_file_append() {
    build_args "$1"
    run_obsidian append "${ARGS_OUT[@]}"
    echo "ok"
}

tool_file_prepend() {
    build_args "$1"
    run_obsidian prepend "${ARGS_OUT[@]}"
    echo "ok"
}

tool_file_move() {
    build_args "$1"
    run_obsidian move "${ARGS_OUT[@]}"
    echo "ok"
}

tool_file_rename() {
    build_args "$1"
    run_obsidian rename "${ARGS_OUT[@]}"
    echo "ok"
}

tool_file_delete() {
    build_args "$1"
    run_obsidian delete "${ARGS_OUT[@]}"
    echo "ok"
}

tool_daily_append() {
    build_args "$1"
    run_obsidian daily:append "${ARGS_OUT[@]}"
    echo "ok"
}

tool_daily_prepend() {
    build_args "$1"
    run_obsidian daily:prepend "${ARGS_OUT[@]}"
    echo "ok"
}

tool_property_set() {
    build_args "$1"
    run_obsidian property:set "${ARGS_OUT[@]}"
    echo "ok"
}

tool_property_remove() {
    build_args "$1"
    run_obsidian property:remove "${ARGS_OUT[@]}"
    echo "ok"
}

tool_task_update() {
    build_args "$1"
    run_obsidian task "${ARGS_OUT[@]}"
    echo "ok"
}

tool_bookmark_add() {
    build_args "$1"
    run_obsidian bookmark "${ARGS_OUT[@]}"
    echo "ok"
}

# ----- UI / navigation / awareness tools -----

tool_file_open() {
    build_args "$1"
    run_obsidian open "${ARGS_OUT[@]}"
    echo "ok"
}

tool_file_unique() {
    build_args "$1"
    run_obsidian unique "${ARGS_OUT[@]}"
    echo "ok"
}

tool_random_open() {
    build_args "$1"
    run_obsidian random "${ARGS_OUT[@]}"
    echo "ok"
}

tool_random_read() {
    build_args "$1"
    run_obsidian random:read "${ARGS_OUT[@]}"
}

tool_recents_list() {
    build_args "$1"
    run_obsidian recents "${ARGS_OUT[@]}"
}

tool_web_open() {
    build_args "$1"
    run_obsidian web "${ARGS_OUT[@]}"
    echo "ok"
}

tool_search_open() {
    build_args "$1"
    run_obsidian search:open "${ARGS_OUT[@]}"
    echo "ok"
}

tool_daily_open() {
    build_args "$1"
    run_obsidian daily "${ARGS_OUT[@]}"
    echo "ok"
}

tool_workspace_tree() {
    build_args "$1"
    ARGS_OUT+=("format=json")
    run_obsidian workspace "${ARGS_OUT[@]}"
}

tool_tabs_list() {
    build_args "$1"
    ARGS_OUT+=("format=json")
    run_obsidian tabs "${ARGS_OUT[@]}"
}

tool_tab_open() {
    build_args "$1"
    run_obsidian tab:open "${ARGS_OUT[@]}"
    echo "ok"
}

tool_workspaces_list() {
    build_args "$1"
    run_obsidian workspaces "${ARGS_OUT[@]}"
}

tool_workspace_save() {
    build_args "$1"
    run_obsidian workspace:save "${ARGS_OUT[@]}"
    echo "ok"
}

tool_workspace_load() {
    build_args "$1"
    run_obsidian workspace:load "${ARGS_OUT[@]}"
    echo "ok"
}

tool_workspace_delete() {
    build_args "$1"
    run_obsidian workspace:delete "${ARGS_OUT[@]}"
    echo "ok"
}

tool_commands_list() {
    build_args "$1"
    run_obsidian commands "${ARGS_OUT[@]}"
}

tool_command_run() {
    build_args "$1"
    run_obsidian command "${ARGS_OUT[@]}"
    echo "ok"
}

tool_hotkeys_list() {
    build_args "$1"
    run_obsidian hotkeys "${ARGS_OUT[@]}"
}

tool_hotkey_get() {
    build_args "$1"
    run_obsidian hotkey "${ARGS_OUT[@]}"
}

tool_template_insert() {
    build_args "$1"
    run_obsidian template:insert "${ARGS_OUT[@]}"
    echo "ok"
}

tool_file_diff() {
    build_args "$1"
    run_obsidian diff "${ARGS_OUT[@]}"
}

tool_file_history() {
    build_args "$1"
    run_obsidian history "${ARGS_OUT[@]}"
}

tool_file_history_list() {
    run_obsidian history:list
}

tool_file_history_read() {
    build_args "$1"
    run_obsidian history:read "${ARGS_OUT[@]}"
}

tool_file_history_restore() {
    build_args "$1"
    run_obsidian history:restore "${ARGS_OUT[@]}"
    echo "ok"
}

tool_bases_list() {
    run_obsidian bases
}

tool_base_views() {
    build_args "$1"
    run_obsidian base:views "${ARGS_OUT[@]}"
}

tool_base_query() {
    build_args "$1"
    ARGS_OUT+=("format=json")
    run_obsidian base:query "${ARGS_OUT[@]}"
}

tool_base_create() {
    build_args "$1"
    ARGS_OUT+=("silent")
    run_obsidian base:create "${ARGS_OUT[@]}"
    echo "ok"
}

# ----- utility tools -----

tool_debug() {
    # Report the effective runtime configuration so clients can see which
    # env-var knobs are active. OBSIDIAN_VAULT is fixed from argv at startup;
    # OBSIDIAN_BIN and OBSIDIAN_MCP_LOG come from the environment with
    # fallbacks. Intended as a troubleshooting aid.
    jq -nc \
        --arg vault     "$OBSIDIAN_VAULT" \
        --arg bin       "$OBSIDIAN_BIN" \
        --arg log       "$OBSIDIAN_MCP_LOG" \
        --arg version   "$VERSION" \
        '{
            version: $version,
            env: {
                OBSIDIAN_VAULT:   $vault,
                OBSIDIAN_BIN:     $bin,
                OBSIDIAN_MCP_LOG: $log
            }
        }'
}

tool_date_time() {
    local args_json="$1"
    local fmt utc_flag=""
    fmt=$(printf '%s' "$args_json" | jq -r '.format // empty')
    if printf '%s' "$args_json" | jq -e '.utc == true' >/dev/null 2>&1; then
        utc_flag="-u"
    fi

    if [ -n "$fmt" ]; then
        date $utc_flag +"$fmt"
        return
    fi

    local iso d t wd tz unx utc_bool
    iso=$(date $utc_flag +"%Y-%m-%dT%H:%M:%S%z")
    d=$(date $utc_flag +"%Y-%m-%d")
    t=$(date $utc_flag +"%H:%M:%S")
    wd=$(date $utc_flag +"%A")
    tz=$(date $utc_flag +"%Z")
    unx=$(date $utc_flag +"%s")
    if [ -n "$utc_flag" ]; then utc_bool=true; else utc_bool=false; fi

    jq -nc \
        --arg iso "$iso" \
        --arg date "$d" \
        --arg time "$t" \
        --arg weekday "$wd" \
        --arg timezone "$tz" \
        --argjson unix "$unx" \
        --argjson utc "$utc_bool" \
        '{iso:$iso, date:$date, time:$time, weekday:$weekday, timezone:$timezone, unix:$unix, utc:$utc}'
}

# ---------------------------------------------------------------------------
# 9. Dispatcher for tools/call
# ---------------------------------------------------------------------------

dispatch_tool_call() {
    local id="$1" line="$2"
    local name args
    name=$(printf '%s' "$line" | jq -r '.params.name // ""')
    args=$(printf '%s' "$line" | jq -c '.params.arguments // {}')

    if [ -z "$name" ]; then
        send_error "$id" -32602 "Missing params.name"
        return
    fi

    local fn="tool_${name}"
    if ! declare -F "$fn" >/dev/null 2>&1; then
        send_error "$id" -32601 "Unknown tool: $name"
        return
    fi

    local out rc
    set +e
    out=$("$fn" "$args" 2>>"$OBSIDIAN_MCP_LOG")
    rc=$?
    set -e

    if [ $rc -eq 0 ]; then
        send_result "$id" "$(mcp_content "$out")"
    else
        local msg="Tool failed: $name"
        if [ -n "$out" ]; then
            msg="$msg: $out"
        fi
        send_result "$id" "$(mcp_error_content "$msg")"
    fi
}

# ---------------------------------------------------------------------------
# 10. Main loop
# ---------------------------------------------------------------------------

INIT_RESULT=$(jq -nc --arg v "$VERSION" '{
  protocolVersion: "2024-11-05",
  serverInfo: {name: "obsidian-mcp", version: $v},
  capabilities: {tools: {}}
}')

log "obsidian-mcp.sh starting; vault=$OBSIDIAN_VAULT bin=$OBSIDIAN_BIN"

while IFS= read -r line; do
    [ -z "$line" ] && continue

    # Validate JSON; emit parse error on failure.
    if ! printf '%s' "$line" | jq -e . >/dev/null 2>&1; then
        log "parse error: $line"
        send_error "null" -32700 "Parse error"
        continue
    fi

    method=$(printf '%s' "$line" | jq -r '.method // ""')
    id=$(printf '%s' "$line" | jq -c '.id // null')

    # Notifications have no id (or id is null) and must not be replied to.
    is_notification=0
    if [ "$id" = "null" ]; then
        is_notification=1
    fi

    case "$method" in
        initialize)
            send_result "$id" "$INIT_RESULT"
            ;;
        notifications/*)
            : # silent
            ;;
        tools/list)
            send_result "$id" "$TOOLS_JSON"
            ;;
        tools/call)
            dispatch_tool_call "$id" "$line"
            ;;
        ping)
            send_result "$id" '{}'
            ;;
        "")
            if [ "$is_notification" -eq 0 ]; then
                send_error "$id" -32600 "Invalid request"
            fi
            ;;
        *)
            if [ "$is_notification" -eq 0 ]; then
                send_error "$id" -32601 "Method not found: $method"
            fi
            ;;
    esac
done

log "obsidian-mcp.sh exiting"
