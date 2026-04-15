#!/usr/bin/env bash
#
# mock_obsidian.sh — drop-in replacement for the `obsidian` CLI used by
# obsidian-mcp.sh during testing.
#
# Invocation matches the real CLI:
#   mock_obsidian.sh vault=<name> <command> [key=value ...] [flags]

set -u

# Drop the leading vault=... arg.
shift || true

cmd="${1:-}"
shift || true

# Detect format=json among remaining args.
is_json=0
for a in "$@"; do
    case "$a" in
        format=json) is_json=1 ;;
    esac
done

case "$cmd" in
    read)
        printf '# Note title\n\nBody text.\n'
        ;;
    files)
        printf 'note1.md\nnote2.md\n'
        ;;
    file)
        printf 'size\t1024\nmtime\t2026-01-01\n'
        ;;
    folder)
        printf 'files\t3\nfolders\t1\nsize\t4096\n'
        ;;
    folders)
        printf 'Daily\nInbox\n'
        ;;
    daily:read)
        printf '# %s\n- task\n' "$(date +%F)"
        ;;
    daily:path)
        printf 'Daily/%s.md\n' "$(date +%F)"
        ;;
    search|search:context)
        if [ "$is_json" -eq 1 ]; then
            printf '[{"path":"note.md","matches":1}]\n'
        else
            printf 'note.md: 1 match\n'
        fi
        ;;
    properties)
        if [ "$is_json" -eq 1 ]; then
            printf '[{"name":"tags","type":"list","count":5}]\n'
        else
            printf 'tags\tlist\t5\n'
        fi
        ;;
    property:read)
        printf 'value\n'
        ;;
    tags)
        if [ "$is_json" -eq 1 ]; then
            printf '[{"name":"todo","count":3}]\n'
        else
            printf '#todo\t3\n'
        fi
        ;;
    tag)
        printf 'files: note1.md\n'
        ;;
    tasks)
        if [ "$is_json" -eq 1 ]; then
            printf '[{"text":"Buy groceries","status":" ","path":"todo.md","line":3}]\n'
        else
            printf -- '- [ ] Buy groceries\n'
        fi
        ;;
    backlinks)
        if [ "$is_json" -eq 1 ]; then
            printf '[{"path":"other.md","count":2}]\n'
        else
            printf 'other.md\n'
        fi
        ;;
    links)
        printf 'link1.md\n'
        ;;
    unresolved)
        if [ "$is_json" -eq 1 ]; then
            printf '[]\n'
        fi
        ;;
    orphans)
        printf 'lonely.md\n'
        ;;
    deadends)
        printf 'end.md\n'
        ;;
    bookmarks)
        if [ "$is_json" -eq 1 ]; then
            printf '[{"title":"Note","path":"note.md"}]\n'
        else
            printf 'Note\tnote.md\n'
        fi
        ;;
    outline)
        if [ "$is_json" -eq 1 ]; then
            printf '[{"level":1,"text":"Title"}]\n'
        else
            printf '# Title\n'
        fi
        ;;
    wordcount)
        printf 'words\t42\nchars\t210\n'
        ;;
    templates)
        printf 'Daily.md\n'
        ;;
    template:read)
        printf '# Template\n'
        ;;
    aliases)
        printf 'alias1\n'
        ;;
    create|append|prepend|move|rename|delete|\
    daily:append|daily:prepend|\
    property:set|property:remove|\
    task|bookmark)
        # Silent success for write operations. If MOCK_ARGS_LOG is set,
        # record the command and each received argv element (one per line)
        # so tests can inspect what obsidian-mcp.sh passed through.
        if [ -n "${MOCK_ARGS_LOG:-}" ]; then
            {
                printf 'cmd=%s\n' "$cmd"
                for a in "$@"; do printf 'arg=%s\n' "$a"; done
                printf -- '---\n'
            } >> "$MOCK_ARGS_LOG"
        fi
        :
        ;;
    *)
        printf 'Error: Unknown command: %s\n' "$cmd"
        ;;
esac

exit 0
