# Testing

## Running the tests

```sh
./test.sh
```

The test suite is self-contained and does **not** require a real Obsidian
vault or a running Obsidian instance.

## What the tests cover

The test harness (`test.sh`) exercises the server end-to-end by sending
JSON-RPC messages over stdin and asserting on the JSON responses. Test
areas include:

1. **Protocol compliance** — `initialize`, `ping`, notification handling,
   malformed JSON, unknown methods
2. **Tool registry** — `tools/list` returns the expected set of tools
3. **Core tools** — `file_read`, `search`, `wordcount`, `file_create`
   (including overwrite safety guard and multiline content preservation),
   `file_append`, `tasks_list`, `date_time`, `debug`
4. **UI / navigation tools** — `file_open`, `tabs_list`, `workspace_tree`,
   `command_run`, `recents_list`, `commands_list`
5. **Advanced tools** — `links_orphans` (regression test), `base_query`,
   `bases_list`, `daily_open`, `file_history_restore`
6. **`--features` flag** — verifying tool counts per category, combined
   categories, disabled tool rejection, unknown category error

## Mock setup

Tests use `mock_obsidian.sh` as a drop-in replacement for the real
`obsidian` CLI binary. The mock is set via:

```sh
export OBSIDIAN_BIN=./mock_obsidian.sh
```

The mock accepts the same `vault=<name> <command> [key=value...]` calling
convention and returns canned responses for each CLI command (`read`,
`files`, `search`, `tasks`, etc.). Write operations are silent successes.
When `MOCK_ARGS_LOG` is set, the mock logs the received arguments so tests
can verify correct argument passthrough.

## Continuous integration

CI runs via GitHub Actions on every push to `main` and on pull requests.
The pipeline runs:

1. **ShellCheck** — static analysis of `obsidian-mcp.sh`, `test.sh`, and
   `mock_obsidian.sh`
2. **Test** — installs `jq` and runs `bash test.sh`

There is no need to reproduce the full CI pipeline locally; running
`./test.sh` is sufficient for pre-commit validation.
