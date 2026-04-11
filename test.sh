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

# 3. tools/list — required tools present
for t in file_read search file_create daily_read tasks_list wordcount file_append property_set date_time; do
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

# 4. tools/list — single-vault cuts must NOT be present
for t in vault_info commands_list hotkeys_list command_exec; do
    case " $names" in
        *" $t "*)
            printf 'FAIL: %s should be cut from registry\n' "$t"
            FAIL=$((FAIL + 1))
            ;;
        *)
            printf 'PASS: %s correctly absent\n' "$t"
            PASS=$((PASS + 1))
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
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"file_create","arguments":{"name":"x.md","overwrite":true}}}')
assert_eq "create overwrite guard code" "-32603" \
    "$(printf '%s' "$r" | jq -r '.error.code')"

# ---------------------------------------------------------------------------
# 11. file_create happy path -> ok
# ---------------------------------------------------------------------------
r=$(rpc '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"file_create","arguments":{"name":"new.md","content":"hello"}}}')
assert_eq "file_create success text" "ok" \
    "$(printf '%s' "$r" | jq -r '.result.content[0].text')"

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
# Summary
# ---------------------------------------------------------------------------
echo
printf 'Passed: %d  Failed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
