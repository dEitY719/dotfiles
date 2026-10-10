# global-packages/

Keeps global CLI tools in sync across the 5 WSL PCs. Currently uv tools only.

## Files

| File | Role |
| --- | --- |
| `uv-tools.txt` | SSOT list: `<spec> [uv tool install options...]` per line, whitespace-separated; `#` comments and blank lines ignored |
| `setup.sh` | Installs listed tools that are missing, force-reinstalls option drift (called by root `./setup.sh`, step `global-packages`, optional) |

Tests: `tests/bats/setup/global_packages_setup.bats` (stubbed `uv`, no network).

## Behavior

1. Resolve `uv` from PATH. If missing, run `mise install uv` in the repo root
   (version pinned in `mise.toml`) and use `mise which uv`. If neither works:
   `ux_warning` and exit 0.
2. For each line, the first token is the spec, the rest are options. Derive
   the package name from the spec: strip `[extras]`, version specifiers
   (`==`, `>=`, ...) and markers, lowercase, `_`/`.` -> `-`.
   - Not in `uv tool list` -> `uv tool install --native-tls <options...>
     "<spec>"` (spec always last). A failure is a `ux_warning`; the loop
     continues.
   - Installed, no options -> skip (`ux_info`).
   - Installed, with options -> drift check against
     `$(uv tool dir)/<name>/uv-receipt.toml`: `--python V` needs a line
     `python = "V"`; each `--with X` needs `name = "<spec_name X>"`. All
     match -> skip. Missing receipt or any mismatch -> same install with
     `--force` added (`ux_info` names the options).
3. Installed tools not in the list are reported in one `ux_warning`.
4. Always exits 0 — it must never fail the root setup. Root `setup.sh`
   surfaces the `⚠` lines in its step summary.

`GLOBAL_PACKAGES_LIST` overrides the list path (used by tests).

## Adding a package

Append the spec to `uv-tools.txt` (e.g. `markitdown[all]`, `ruff>=0.5`) and
run `./global-packages/setup.sh` or `./setup.sh`. Other PCs pick it up on
their next `./setup.sh`.

Option syntax: only the space-separated `--python V` and `--with X` forms are
drift-checked (`--with=X` / `--python=V` are passed to uv but never checked).
Other options are passed through with no drift check.

Note: a tool without options is never upgraded or re-installed with new
extras/version. To change those on a PC, run `uv tool install --native-tls
--force <options...> "<spec>"` there manually.

### Why markitdown has `--python 3.12 --with pip-system-certs`

The internal proxy (TLS interception, issuer `CN=samsungsemi-prx.com`)
breaks `markitdown <https url>` twice:

- `requests` uses `certifi`, which lacks the proxy CA -> "unable to get
  local issuer certificate". `pip-system-certs` makes it use the OS store.
- Python 3.13+ with urllib3 2.x sets `VERIFY_X509_STRICT` itself, and the
  proxy CA has no Authority Key Identifier -> "Missing Authority Key
  Identifier". Pinning Python 3.12 avoids the strict flag.

## Rules

- **Never uninstall.** Removing a line from `uv-tools.txt` does not remove
  the tool anywhere; unlisted tools only produce a warning. Uninstall
  manually with `uv tool uninstall <name>` on each PC.
- **Always `--native-tls`.** Internal PCs sit behind a proxy with a private
  CA in the system trust store; uv's bundled roots reject it. `--native-tls`
  makes uv use the OS store and is harmless on external PCs.
- Output only through `ux_lib` (`ux_info` / `ux_success` / `ux_warning`).
