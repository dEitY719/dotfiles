# Output & report formats — dry-run plan + final report

Used by Step 3 (dry-run plan) and Step 5 (final report). Print these
verbatim, substituting the `<...>` fields.

## Dry-run plan block (Step 3, `--dry-run` default)

After printing all four artifacts, end with this block and stop — mutate
nothing:

```
Plan ready: <path> (backend=<backend>, py=<ver>, tasks=<n>, stale=<s>)
Run with --apply to write mise.toml, rewrite pyproject, and uv sync.
```

## Final report (Step 5)

Always emit the success line:

```
[OK] devx:mise-migrate path=<path> backend=<backend> py=<ver> tasks=<n>
```

### On `--apply`, append the apply fields

```
synced=yes cleaned=<.venv,egg-info|kept> docs=<rewrote-N|scan-only>
```

After a successful apply, hint:

```
Next: mise run test
```

### On `--dry-run`, append the next-step hint

```
Next: review the plan, then re-run with --apply
```

## Carried-over notes (both modes)

Always re-print any `[WARN]` / `[INFO]` notes so they survive into the
final surface:

- PEP 735 silent-regression `[WARN]` (dev extra lifted to
  `[dependency-groups]`) — `references/pyproject-rewrite.md`.
- Stale legacy references found by the scan — `references/stale-scan.md`.
- Pin-is-floor `[INFO]` (Python pin came from `requires-python`, no
  `pyvenv.cfg`) — `references/extraction.md`.
