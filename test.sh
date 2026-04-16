#!/usr/bin/env bash
#
# test.sh — self-contained test harness for obsidian-mcp.sh.
# Uses mock_obsidian.sh as a stand-in for the real Obsidian CLI.

set -u

cd "$(dirname "$0")" || exit 1

export OBSIDIAN_BIN=./mock_obsidian.sh
export OBSIDIAN_MCP_LOG=/tmp/obsidian-mcp-test.log
: >"$OBSIDIAN_MCP_LOG"

VAULT=TestVault

PASS=0
FAIL=0

assert_eq() {
    # name expected actual
    if [ "$2" = "$3" ]; then
        printf 'PASS: %s\n' "$1"
        PASS=$((PASS + 1))
    else
        printf 'FAIL: %s\n' "$1"
        printf '  expected: %s\n' "$2"
        printf '  actual:   %s\n' "$3"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    # name needle haystack
    case "$3" in
        *"$2"*)
            printf 'PASS: %s\n' "$1"
            PASS=$((PASS + 1))
            ;;
        *)
            printf 'FAIL: %s (missing: %s)\n' "$1" "$2"
            printf '  actual: %s\n' "$3"
            FAIL=$((FAIL + 1))
            ;;
    esac
}

rpc() {
    # Send one JSON-RPC line, capture first line of response.
    printf '%s\n' "$1" | ./obsidian-mcp.sh "$VAULT" 2>/dev/null | head -n1
}

# ---------------------------------------------------------------------------
# 1. initialize
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
assert_eq "initialize id" "1" "$(printf '%s' "$r" | jq -r '.id')"
assert_contains "initialize has serverInfo.name" "obsidian-mcp" "$r"
assert_contains "initialize has capabilities" "tools" "$r"

# ---------------------------------------------------------------------------
# 2. tools/list — structure
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
assert_eq "tools/list result.tools is array" "array" \
    "$(printf '%s' "$r" | jq -r '.result.tools | type')"

names=$(printf '%s' "$r" | jq -r '.result.tools[].name' | tr '\n' ' ')

# 3. tools/list — required tools present (core + new UI/awareness set)
for t in file_read search file_create daily_read tasks_list wordcount file_append property_set date_time \
         file_open tabs_list workspace_tree recents_list command_run commands_list hotkeys_list \
         search_open tab_open workspace_save workspace_load template_insert file_history_restore base_query \
         bases_list web_open daily_open; do
    case " $names" in
        *" $t "*)
            printf 'PASS: tools/list contains %s\n' "$t"
            PASS=$((PASS + 1))
            ;;
        *)
            printf 'FAIL: tools/list missing %s\n' "$t"
            FAIL=$((FAIL + 1))
            ;;
    esac
done

# ---------------------------------------------------------------------------
# 5. tools/call — file_read
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"file_read","arguments":{"file":"note.md"}}}')
text=$(printf '%s' "$r" | jq -r '.result.content[0].text')
assert_contains "file_read returns markdown" "Note title" "$text"

# ---------------------------------------------------------------------------
# 6. tools/call — search returns valid JSON in content
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"search","arguments":{"query":"foo"}}}')
text=$(printf '%s' "$r" | jq -r '.result.content[0].text')
assert_eq "search content is JSON array" "array" \
    "$(printf '%s' "$text" | jq -r 'type')"

# ---------------------------------------------------------------------------
# 7. tools/call — wordcount kv->json normalization
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"wordcount","arguments":{"file":"note.md"}}}')
text=$(printf '%s' "$r" | jq -r '.result.content[0].text')
assert_eq "wordcount.words = 42" "42" "$(printf '%s' "$text" | jq -r '.words')"
assert_eq "wordcount.chars = 210" "210" "$(printf '%s' "$text" | jq -r '.chars')"

# ---------------------------------------------------------------------------
# 8. tools/call — unknown tool -> error
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"nope","arguments":{}}}')
assert_eq "unknown tool error.code" "-32601" \
    "$(printf '%s' "$r" | jq -r '.error.code')"

# ---------------------------------------------------------------------------
# 9. unknown method -> -32601
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":7,"method":"bogus/method"}')
assert_eq "unknown method code" "-32601" \
    "$(printf '%s' "$r" | jq -r '.error.code')"

# ---------------------------------------------------------------------------
# 10. file_create overwrite without content -> safety guard error
# Tool-execution failures are returned as isError content (per MCP spec)
# so the model can see the diagnostic, not as a JSON-RPC error code.
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"file_create","arguments":{"name":"x.md","overwrite":true}}}')
assert_eq "create overwrite guard isError" "true" \
    "$(printf '%s' "$r" | jq -r '.result.isError')"
assert_contains "create overwrite guard message" "refusing overwrite" \
    "$(printf '%s' "$r" | jq -r '.result.content[0].text')"

# ---------------------------------------------------------------------------
# 11. file_create happy path -> ok
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"file_create","arguments":{"name":"new.md","content":"hello"}}}')
assert_eq "file_create success text" "ok" \
    "$(printf '%s' "$r" | jq -r '.result.content[0].text')"

# ---------------------------------------------------------------------------
# 11b. file_create / file_append preserve multiline content (#11)
# ---------------------------------------------------------------------------
MOCK_ARGS_LOG=$(mktemp)
export MOCK_ARGS_LOG
: >"$MOCK_ARGS_LOG"

r=$(rpc '{"jsonrpc":"2.0","id":91,"method":"tools/call","params":{"name":"file_create","arguments":{"name":"ml.md","content":"---\ntags:\n  - Test\n---\n# Title\n- item"}}}')
assert_eq "file_create multiline ok" "ok" \
    "$(printf '%s' "$r" | jq -r '.result.content[0].text')"
log_body=$(cat "$MOCK_ARGS_LOG")
assert_contains "file_create multiline: frontmatter open" "arg=content=---" "$log_body"
assert_contains "file_create multiline: tags line"        "tags:"             "$log_body"
assert_contains "file_create multiline: heading"          "# Title"           "$log_body"
assert_contains "file_create multiline: list item"        "- item"            "$log_body"

: >"$MOCK_ARGS_LOG"
r=$(rpc '{"jsonrpc":"2.0","id":92,"method":"tools/call","params":{"name":"file_append","arguments":{"file":"ml.md","content":"line1\nline2\nline3"}}}')
assert_eq "file_append multiline ok" "ok" \
    "$(printf '%s' "$r" | jq -r '.result.content[0].text')"
log_body=$(cat "$MOCK_ARGS_LOG")
assert_contains "file_append multiline: line1" "arg=content=line1" "$log_body"
assert_contains "file_append multiline: line2" "line2"             "$log_body"
assert_contains "file_append multiline: line3" "line3"             "$log_body"

rm -f "$MOCK_ARGS_LOG"
unset MOCK_ARGS_LOG

# ---------------------------------------------------------------------------
# 12. notification -> no response on stdout
# ---------------------------------------------------------------------------
out=$(printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    | ./obsidian-mcp.sh "$VAULT" 2>/dev/null)
assert_eq "notification produces no output" "" "$out"

# ---------------------------------------------------------------------------
# 13. malformed JSON -> -32700
# ---------------------------------------------------------------------------
r=$(rpc 'not-json')
assert_eq "parse error code" "-32700" \
    "$(printf '%s' "$r" | jq -r '.error.code')"

# ---------------------------------------------------------------------------
# 14. missing vault arg -> exit 2 with usage message
# ---------------------------------------------------------------------------
out=$(./obsidian-mcp.sh </dev/null 2>&1; printf 'rc=%s' "$?")
assert_contains "missing vault arg prints usage" "Usage:" "$out"
assert_contains "missing vault arg rc=2" "rc=2" "$out"

# ---------------------------------------------------------------------------
# 15. ping -> empty result
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":10,"method":"ping"}')
assert_eq "ping returns object result" "object" \
    "$(printf '%s' "$r" | jq -r '.result | type')"

# ---------------------------------------------------------------------------
# 16. tasks_list with file scope -> JSON array
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"tasks_list","arguments":{"file":"todo.md"}}}')
text=$(printf '%s' "$r" | jq -r '.result.content[0].text')
assert_eq "tasks_list returns array" "array" \
    "$(printf '%s' "$text" | jq -r 'type')"

# ---------------------------------------------------------------------------
# 17. tools/call — date_time default returns structured JSON
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"date_time","arguments":{}}}')
text=$(printf '%s' "$r" | jq -r '.result.content[0].text')
d=$(printf '%s' "$text" | jq -r '.date')
case "$d" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
        printf 'PASS: date_time default .date is YYYY-MM-DD\n'
        PASS=$((PASS + 1))
        ;;
    *)
        printf 'FAIL: date_time default .date bad format: %s\n' "$d"
        FAIL=$((FAIL + 1))
        ;;
esac
assert_eq "date_time default .unix is number" "number" \
    "$(printf '%s' "$text" | jq -r '.unix | type')"
assert_eq "date_time default .utc is false" "false" \
    "$(printf '%s' "$text" | jq -r '.utc')"

# ---------------------------------------------------------------------------
# 18. tools/call — date_time custom format passthrough
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"date_time","arguments":{"format":"FIXED-STRING"}}}')
text=$(printf '%s' "$r" | jq -r '.result.content[0].text')
assert_eq "date_time format passthrough" "FIXED-STRING" "$text"

# ---------------------------------------------------------------------------
# 19. tools/call — date_time utc flag yields UTC timezone
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"date_time","arguments":{"utc":true,"format":"%Z"}}}')
text=$(printf '%s' "$r" | jq -r '.result.content[0].text')
assert_eq "date_time utc %Z is UTC" "UTC" "$text"

# ---------------------------------------------------------------------------
# 20. tools/call — debug reports effective env values
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":15,"method":"tools/call","params":{"name":"debug","arguments":{}}}')
text=$(printf '%s' "$r" | jq -r '.result.content[0].text')
assert_eq "debug .env.OBSIDIAN_VAULT" "$VAULT" \
    "$(printf '%s' "$text" | jq -r '.env.OBSIDIAN_VAULT')"
assert_eq "debug .env.OBSIDIAN_BIN" "./mock_obsidian.sh" \
    "$(printf '%s' "$text" | jq -r '.env.OBSIDIAN_BIN')"
assert_eq "debug .env.OBSIDIAN_MCP_LOG" "/tmp/obsidian-mcp-test.log" \
    "$(printf '%s' "$text" | jq -r '.env.OBSIDIAN_MCP_LOG')"
assert_contains "debug .version looks like semver" "." \
    "$(printf '%s' "$text" | jq -r '.version')"

# ---------------------------------------------------------------------------
# 21. file_open with no args — active-file UI open path
# ---------------------------------------------------------------------------
MOCK_ARGS_LOG=$(mktemp)
export MOCK_ARGS_LOG
: >"$MOCK_ARGS_LOG"

r=$(rpc '{"jsonrpc":"2.0","id":21,"method":"tools/call","params":{"name":"file_open","arguments":{}}}')
assert_eq "file_open returns ok" "ok" \
    "$(printf '%s' "$r" | jq -r '.result.content[0].text')"
assert_contains "file_open invoked 'open' command" "cmd=open" "$(cat "$MOCK_ARGS_LOG")"

: >"$MOCK_ARGS_LOG"
r=$(rpc '{"jsonrpc":"2.0","id":22,"method":"tools/call","params":{"name":"file_open","arguments":{"file":"note.md","newtab":true}}}')
log_body=$(cat "$MOCK_ARGS_LOG")
assert_contains "file_open passes file arg" "arg=file=note.md" "$log_body"
assert_contains "file_open passes newtab flag" "arg=newtab" "$log_body"

# ---------------------------------------------------------------------------
# 22. tabs_list returns JSON array with active tab
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":23,"method":"tools/call","params":{"name":"tabs_list","arguments":{}}}')
text=$(printf '%s' "$r" | jq -r '.result.content[0].text')
assert_eq "tabs_list is JSON array" "array" \
    "$(printf '%s' "$text" | jq -r 'type')"
assert_eq "tabs_list has active tab" "active.md" \
    "$(printf '%s' "$text" | jq -r '.[] | select(.active==true) | .file')"

# ---------------------------------------------------------------------------
# 23. workspace_tree returns JSON
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":24,"method":"tools/call","params":{"name":"workspace_tree","arguments":{}}}')
text=$(printf '%s' "$r" | jq -r '.result.content[0].text')
assert_eq "workspace_tree is JSON object" "object" \
    "$(printf '%s' "$text" | jq -r 'type')"

# ---------------------------------------------------------------------------
# 24. command_run passes id through
# ---------------------------------------------------------------------------
: >"$MOCK_ARGS_LOG"
r=$(rpc '{"jsonrpc":"2.0","id":25,"method":"tools/call","params":{"name":"command_run","arguments":{"id":"app:go-back"}}}')
assert_eq "command_run returns ok" "ok" \
    "$(printf '%s' "$r" | jq -r '.result.content[0].text')"
log_body=$(cat "$MOCK_ARGS_LOG")
assert_contains "command_run invoked 'command'" "cmd=command" "$log_body"
assert_contains "command_run passes id" "arg=id=app:go-back" "$log_body"

# ---------------------------------------------------------------------------
# 25. recents_list returns text
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":27,"method":"tools/call","params":{"name":"recents_list","arguments":{}}}')
text=$(printf '%s' "$r" | jq -r '.result.content[0].text')
assert_contains "recents_list has today.md" "today.md" "$text"

# ---------------------------------------------------------------------------
# 27. commands_list returns command ids
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":28,"method":"tools/call","params":{"name":"commands_list","arguments":{}}}')
text=$(printf '%s' "$r" | jq -r '.result.content[0].text')
assert_contains "commands_list contains editor:toggle-source" "editor:toggle-source" "$text"

# ---------------------------------------------------------------------------
# 28. file_history_restore with version
# ---------------------------------------------------------------------------
: >"$MOCK_ARGS_LOG"
r=$(rpc '{"jsonrpc":"2.0","id":29,"method":"tools/call","params":{"name":"file_history_restore","arguments":{"file":"note.md","version":3}}}')
assert_eq "file_history_restore returns ok" "ok" \
    "$(printf '%s' "$r" | jq -r '.result.content[0].text')"
log_body=$(cat "$MOCK_ARGS_LOG")
assert_contains "file_history_restore invoked history:restore" "cmd=history:restore" "$log_body"
assert_contains "file_history_restore passes version" "arg=version=3" "$log_body"

# ---------------------------------------------------------------------------
# 29. base_query returns JSON
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":30,"method":"tools/call","params":{"name":"base_query","arguments":{"file":"projects.base"}}}')
text=$(printf '%s' "$r" | jq -r '.result.content[0].text')
assert_eq "base_query is JSON array" "array" \
    "$(printf '%s' "$text" | jq -r 'type')"

# ---------------------------------------------------------------------------
# 30. bases_list returns base files
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":31,"method":"tools/call","params":{"name":"bases_list","arguments":{}}}')
text=$(printf '%s' "$r" | jq -r '.result.content[0].text')
assert_contains "bases_list has projects.base" "projects.base" "$text"

# ---------------------------------------------------------------------------
# 31. daily_open invokes 'daily' (distinct from daily:read)
# ---------------------------------------------------------------------------
: >"$MOCK_ARGS_LOG"
r=$(rpc '{"jsonrpc":"2.0","id":32,"method":"tools/call","params":{"name":"daily_open","arguments":{}}}')
assert_eq "daily_open returns ok" "ok" \
    "$(printf '%s' "$r" | jq -r '.result.content[0].text')"
assert_contains "daily_open invoked 'daily'" "cmd=daily" "$(cat "$MOCK_ARGS_LOG")"

rm -f "$MOCK_ARGS_LOG"
unset MOCK_ARGS_LOG

# ---------------------------------------------------------------------------
# 32. links_orphans happy path — single orphan returned as plain text.
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":33,"method":"tools/call","params":{"name":"links_orphans","arguments":{}}}')
assert_eq "links_orphans returns orphan" "lonely.md" \
    "$(printf '%s' "$r" | jq -r '.result.content[0].text')"
assert_eq "links_orphans happy path has no isError" "null" \
    "$(printf '%s' "$r" | jq -r '.result.isError')"

# ---------------------------------------------------------------------------
# 33. links_orphans regression for issue #31: a multi-line orphans listing
# whose first path happens to start with "Error:" must NOT be misclassified
# as a CLI error. The file list should pass through unchanged.
# ---------------------------------------------------------------------------
export MOCK_ORPHANS_OUTPUT=$'Error: retry logic.md\nfoo.md\nbar.md\n'
r=$(rpc '{"jsonrpc":"2.0","id":34,"method":"tools/call","params":{"name":"links_orphans","arguments":{}}}')
text=$(printf '%s' "$r" | jq -r '.result.content[0].text')
assert_eq "links_orphans multi-line not flagged as error" "null" \
    "$(printf '%s' "$r" | jq -r '.result.isError')"
assert_contains "links_orphans preserves Error:-prefixed path" "Error: retry logic.md" "$text"
assert_contains "links_orphans preserves other paths"          "foo.md"                 "$text"
unset MOCK_ORPHANS_OUTPUT

# ---------------------------------------------------------------------------
# 34. A genuine CLI error (single-line "Error: ..." on stdout) is surfaced
# as an isError content result carrying the real message, so the model can
# diagnose it — not as an opaque -32603 JSON-RPC error.
# ---------------------------------------------------------------------------
export MOCK_ORPHANS_OUTPUT='Error: Unknown command: orphans'
r=$(rpc '{"jsonrpc":"2.0","id":35,"method":"tools/call","params":{"name":"links_orphans","arguments":{}}}')
assert_eq "cli error surfaces as isError" "true" \
    "$(printf '%s' "$r" | jq -r '.result.isError')"
assert_contains "cli error message preserved" "Unknown command: orphans" \
    "$(printf '%s' "$r" | jq -r '.result.content[0].text')"
unset MOCK_ORPHANS_OUTPUT

# ---------------------------------------------------------------------------
# 35. --features=all (default) exposes all tools
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":40,"method":"tools/list"}')
count_all=$(printf '%s' "$r" | jq '.result.tools | length')
assert_eq "default features=all exposes 67 tools" "67" "$count_all"

# ---------------------------------------------------------------------------
# 36. --features=files exposes only files-category tools
# ---------------------------------------------------------------------------
rpc_features() {
    # Send one JSON-RPC line with a custom --features flag.
    printf '%s\n' "$2" | ./obsidian-mcp.sh "$VAULT" --features="$1" 2>/dev/null | head -n1
}

r=$(rpc_features "files" '{"jsonrpc":"2.0","id":41,"method":"tools/list"}')
count=$(printf '%s' "$r" | jq '.result.tools | length')
assert_eq "--features=files exposes 16 tools" "16" "$count"

names=$(printf '%s' "$r" | jq -r '.result.tools[].name' | tr '\n' ' ')
assert_contains "--features=files has file_read" "file_read" " $names"
assert_contains "--features=files has search" "search" " $names"

# Verify excluded tool is missing
case " $names" in
    *" daily_read "*) printf 'FAIL: --features=files should not have daily_read\n'; FAIL=$((FAIL + 1)) ;;
    *) printf 'PASS: --features=files excludes daily_read\n'; PASS=$((PASS + 1)) ;;
esac

# ---------------------------------------------------------------------------
# 37. --features=files,dailies combines two categories
# ---------------------------------------------------------------------------
r=$(rpc_features "files,dailies" '{"jsonrpc":"2.0","id":42,"method":"tools/list"}')
count=$(printf '%s' "$r" | jq '.result.tools | length')
assert_eq "--features=files,dailies exposes 21 tools" "21" "$count"

names=$(printf '%s' "$r" | jq -r '.result.tools[].name' | tr '\n' ' ')
assert_contains "--features=files,dailies has daily_read" "daily_read" " $names"
assert_contains "--features=files,dailies has file_read" "file_read" " $names"

# ---------------------------------------------------------------------------
# 38. disabled tool call returns error
# ---------------------------------------------------------------------------
r=$(rpc_features "files" '{"jsonrpc":"2.0","id":43,"method":"tools/call","params":{"name":"daily_read","arguments":{}}}')
assert_eq "disabled tool error code" "-32601" \
    "$(printf '%s' "$r" | jq -r '.error.code')"
assert_contains "disabled tool error message" "not enabled" \
    "$(printf '%s' "$r" | jq -r '.error.message')"

# ---------------------------------------------------------------------------
# 39. unknown category exits with error
# ---------------------------------------------------------------------------
out=$(./obsidian-mcp.sh "$VAULT" --features=bogus </dev/null 2>&1; printf 'rc=%s' "$?")
assert_contains "unknown category prints error" "Unknown feature category" "$out"
assert_contains "unknown category rc=2" "rc=2" "$out"

# ---------------------------------------------------------------------------
# 40. --features=bases exposes only 4 base tools
# ---------------------------------------------------------------------------
r=$(rpc_features "bases" '{"jsonrpc":"2.0","id":44,"method":"tools/list"}')
count=$(printf '%s' "$r" | jq '.result.tools | length')
assert_eq "--features=bases exposes 4 tools" "4" "$count"

names=$(printf '%s' "$r" | jq -r '.result.tools[].name' | tr '\n' ' ')
assert_contains "--features=bases has bases_list" "bases_list" " $names"
assert_contains "--features=bases has base_query" "base_query" " $names"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
printf 'Passed: %d  Failed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
