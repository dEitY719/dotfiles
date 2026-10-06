# global-packages/

Keeps global CLI tools in sync across the 5 WSL PCs. Currently uv tools only.

## Files

| File | Role |
| --- | --- |
| `uv-tools.txt` | SSOT list: one `uv tool install` spec per line; `#` comments and blank lines ignored |
| `setup.sh` | Installs listed tools that are missing (called by root `./setup.sh`, step `global-packages`, optional) |

Tests: `tests/bats/setup/global_packages_setup.bats` (stubbed `uv`, no network).

## Behavior

1. Resolve `uv` from PATH. If missing, run `mise install uv` in the repo root
   (version pinned in `mise.toml`) and use `mise which uv`. If neither works:
   `ux_warning` and exit 0.
2. For each spec, derive the package name: strip `[extras]`, version
   specifiers (`==`, `>=`, ...) and markers, lowercase, `_`/`.` -> `-`.
   - Name already in `uv tool list` -> skip (`ux_info`).
   - Otherwise `uv tool install --native-tls "<spec>"`. A failure is a
     `ux_warning`; the loop continues.
3. Installed tools not in the list are reported in one `ux_warning`.
4. Always exits 0 — it must never fail the root setup. Root `setup.sh`
   surfaces the `⚠` lines in its step summary.

`GLOBAL_PACKAGES_LIST` overrides the list path (used by tests).

## Adding a package

Append the spec to `uv-tools.txt` (e.g. `markitdown[all]`, `ruff>=0.5`) and
run `./global-packages/setup.sh` or `./setup.sh`. Other PCs pick it up on
their next `./setup.sh`.

Note: an existing install is never upgraded or re-installed with new extras.
To change extras/version on a PC, run `uv tool install --native-tls --force
"<spec>"` there manually.

## Rules

- **Never uninstall.** Removing a line from `uv-tools.txt` does not remove
  the tool anywhere; unlisted tools only produce a warning. Uninstall
  manually with `uv tool uninstall <name>` on each PC.
- **Always `--native-tls`.** Internal PCs sit behind a proxy with a private
  CA in the system trust store; uv's bundled roots reject it. `--native-tls`
  makes uv use the OS store and is harmless on external PCs.
- Output only through `ux_lib` (`ux_info` / `ux_success` / `ux_warning`).
