# skill:write-release-note — Help

## Synopsis

```
/write:release-note [<anchor-ref>] [<head-ref>]
```

## Description

Generate structured Korean release notes from git history between two
releases. Finds anchor commits, collects commits in the `<anchor>..HEAD`
range, categorizes by conventional-commit prefix, groups related commits
into user-facing themes, and writes the result in the project's existing
release-notes format (or the default template if none exists).

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `<anchor-ref>` | Previous release boundary (tag, commit hash, or branch). | Auto-detect: latest tag → previous release-note commit → ask user |
| `<head-ref>` | Upper bound of the commit range. | `HEAD` |
| `-h` / `--help` / `help` | Print this help and stop. | — |

## Examples

```
/write:release-note
/write:release-note v1.2.0
/write:release-note v1.2.0 v1.3.0
```

## Stop conditions

- No git tags and no prior release notes — ask the user for the start commit before collecting.
- Non-conventional commits present — call them out (do not silently drop) and group them under a fallback section.
