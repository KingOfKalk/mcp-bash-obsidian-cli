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
VERSION="0.1.0" # x-release-please-version

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

# ---------------------------------------------------------------------------
# 4. Tool registry (heredoc)
# ---------------------------------------------------------------------------

TOOLS_JSON=$(cat <<'JSON_EOF'
{
  "tools": [
    {
      "name": "file_info",
      "description": "Get file metadata (size, dates) for a note in the vault.",
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
      "description": "Read the full contents of a file in the vault.",
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
      "description": "List frontmatter properties (vault-wide or per-file). Note: vault-wide listings may be empty on some CLI versions; pass a file or path for reliable results.",
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
      "description": "List tasks. Note: without file scope, may return empty on some CLI versions; pass file or path for reliable results.",
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
      "description": "List incoming links to a file.",
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
      "description": "List outgoing links from a file.",
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
      "description": "Get the heading outline of a file.",
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
      "description": "Get word and character counts for a file.",
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
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        ARGS_OUT+=("$line")
    done < <(printf '%s' "$json" | jq -r "
        $skip_filter
        | to_entries[]
        | select(.value != null and .value != false)
        | if (.value == true) then .key
          else \"\(.key)=\(.value|tostring)\"
          end
    ")
}

# ---------------------------------------------------------------------------
# 6. Core CLI executor
# ---------------------------------------------------------------------------
#
# run_obsidian <command> [args...]
# Calls $OBSIDIAN_BIN with vault=$OBSIDIAN_VAULT prepended. Captures stderr
# to the log. Treats "Error:" prefix in stdout as failure (the CLI returns
# 0 even on errors).

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

    if [ -s "$stderr_file" ]; then
        log "stderr($cmd): $(cat "$stderr_file")"
    fi
    rm -f "$stderr_file"

    if [ $rc -ne 0 ]; then
        log "non-zero rc=$rc for $cmd"
    fi

    case "$out" in
        Error:*|*$'\n'Error:*)
            log "cli-error($cmd): $out"
            return 1
            ;;
    esac

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
        echo "file_create: refusing overwrite=true with empty content (would truncate file to 0 bytes)" >&2
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
        send_error "$id" -32603 "Tool failed: $name"
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
