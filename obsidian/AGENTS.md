# obsidian/

Single `obsidian` shell command (bash + zsh) — issue #1023.

## What it does

`obsidian_cli.sh` defines one `obsidian()` function that routes to the right
backend for the current environment:

| Environment | Backend | Behavior |
|-------------|---------|----------|
| WSL | `Obsidian.com` CLI redirector | forwards subcommands (`search`/`read`/`create`/...) |
| native Linux | latest `Obsidian-*.AppImage` | launches the GUI |

It is a **function**, not an `alias`, so it can validate prerequisites and emit
a useful error before the binary is invoked. SSOT for the `obsidian` command —
the former `shell-common/tools/integrations/obsidian.sh` was folded in here.

## Wiring

Not auto-sourced (this is a top-level dir, not `shell-common/`). It is sourced
explicitly by both loaders, right after the integrations phase:

- `bash/main.bash` — `safe_source "${DOTFILES_ROOT}/obsidian/obsidian_cli.sh"`
- `zsh/main.zsh` — same, via Phase 6.5

## Overrides

| Var | Scope | Default |
|-----|-------|---------|
| `OBSIDIAN_CLI_BIN` | WSL redirector | `/mnt/c/Program Files/Obsidian/Obsidian.com` |
| `OBSIDIAN_BIN` | explicit AppImage | — |
| `OBSIDIAN_HOME` | AppImage scan dir | `~/application` |

## Usage

```bash
obsidian search query="PARA" limit=5
obsidian read file="My Note"
obsidian property:set name="status" value="done" file="My Task"
obsidian create name="New Note" path="folder/New Note.md" content="# Hello" silent
obsidian backlinks file="My Note"
obsidian            # no args -> launch / focus the app
obsidian -h         # wrapper help
```

## WSL prerequisites

1. **Obsidian "installer" 1.12.7+** — the `Obsidian.com` redirector is created
   at *installer* time, not by the in-app (asar) auto-update.
   - Check: `powershell.exe -NoProfile -Command "(Get-Item 'C:\Program Files\Obsidian\Obsidian.exe').VersionInfo.ProductVersion"`
   - Update: `winget upgrade --id Obsidian.Obsidian --source winget` (Program Files install needs UAC).
2. App: **Settings -> General -> "Command line interface" toggle ON** + run
   registration (sets the Windows PATH).
3. Why a function and not an alias: registration only adds the redirector to the
   *Windows* PATH. WSL interop auto-runs `.exe` but **not `.com`**, so spelling
   out the full path in a function is the reliable route.
4. The CLI needs the Obsidian app **running** (the first command auto-launches it).

## Related (optional, not required)

The `obsidian` function only wraps the app CLI — it does **not** depend on the
`kepano/obsidian-skills` plugin. Those skills tell an AI agent *how* to use this
CLI, so they are recommended when driving the CLI with Claude Code / Codex:

```bash
# Claude Code (marketplace)
/plugin marketplace add kepano/obsidian-skills
/plugin install obsidian@obsidian-skills

# or npx skills
npx skills add git@github.com:kepano/obsidian-skills.git
npx skills add https://github.com/kepano/obsidian-skills
```

Bundled skills: `obsidian-markdown`, `obsidian-bases`, `json-canvas`,
`obsidian-cli`, `defuddle`.

> Note: the `defuddle` command comes from the **`defuddle-cli`** npm package
> (installing `defuddle` alone does not create the `defuddle` binary).

## Tests

`tests/bats/functions/obsidian_cli.bats` — function/help/resolver checks in
both bash and zsh. Run: `./tests/bats/lib/bats-core/bin/bats tests/bats/functions/obsidian_cli.bats`
