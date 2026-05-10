# write:rca — Help

## Synopsis

```
/write:rca [--commit] [--audience <blog|private|internal>] [--private]
```

Generate a publication-ready Root Cause Analysis (RCA) markdown document from
the current conversation context. Output is written to
`${RCA_REPO_PATH:-~/para/archive/rca-knowledge}/docs/analysis/YYYY-MM-DD-{slug}.md`
with YAML frontmatter and 9 fixed sections. Optional media goes in `_assets/`.

## Options

| Option                  | Description                                            | Default     |
|-------------------------|--------------------------------------------------------|-------------|
| `--commit`              | Run `git -C $RCA_REPO_PATH add && commit` after write  | off         |
| `--audience <name>`     | Audience preset: `blog`, `private`, `internal`         | (all four)  |
| `--private`             | Shortcut for `--audience private` (sensitive incident) | off         |
| `-h`, `--help`, `help`  | Print this help and stop                               | —           |

See `references/options.md` for the full flag matrix and the `RCA_REPO_PATH`
env var (SSOT for the repository path).

## Examples

```bash
# Default — interactive, all four audiences, no commit
/write:rca

# Auto-commit after writing
/write:rca --commit

# Blog-first optimization (narrative voice, conclusion+CTA)
/write:rca --audience blog

# Sensitive incident — strip secrets, internal-only
/write:rca --private
```

## Stop conditions

The skill halts (no document written, no commit) when:

1. `RCA_REPO_PATH` resolves to a path that does not exist and cannot be created.
2. The conversation has no extractable problem / root-cause / solution triple.
3. Any Step (1–6) in the workflow reports `[FAIL]` — the chain stops there.
4. `--commit` is set but the repo path is not a git working tree.

On stop, the skill prints a single `[FAIL] write-rca — Step <n>: <reason>`
line and exits without partial side effects.

## See also

- `references/document-template.md` — 9-section RCA spec
- `references/phases-detail.md` — Step 1..6 detailed instructions
- `references/audience-policies.md` — audience-specific rules
- `references/examples.md` — small / medium / large RCA shapes
