<!--
Thanks for contributing!

This project uses Conventional Commits and release-please. On merge, the PR
title is used as the squash-commit message and feeds the changelog / version
bump. Please make sure the PR title follows:

    <type>(<optional-scope>)!: <short description>

Examples:
    feat: add search tool
    fix(server): handle missing vault argument
    docs: clarify install steps
    feat!: rename config key (BREAKING CHANGE)
-->

## Type of change

Tick the one that matches your PR title:

- [ ] `feat` — new user-facing feature (minor version bump)
- [ ] `fix` — bug fix (patch version bump)
- [ ] `docs` — documentation only
- [ ] `refactor` — code change that is neither a feature nor a fix
- [ ] `test` — adding or updating tests
- [ ] `chore` — tooling, deps, housekeeping
- [ ] `ci` — CI/workflow changes
- [ ] Contains a `BREAKING CHANGE` (major version bump — use `!` in title and describe below)

## Summary

<!-- Why is this change needed? What problem does it solve? -->

## Changes

<!-- Bullet list of what this PR actually does. -->

-
-

## Testing

<!-- How did you verify this works? -->

- [ ] `./test.sh` passes locally

## Checklist

- [ ] PR title follows [Conventional Commits](https://www.conventionalcommits.org/)
- [ ] I did **not** hand-edit the version marker in `obsidian-mcp.sh` or `CHANGELOG.md` (release-please owns both)
- [ ] No AI attribution (`Co-Authored-By: Claude`, "Generated with …" footers, etc.) in commits
- [ ] If this is a breaking change, it is called out with `!` in the title and a `BREAKING CHANGE:` footer/section above
