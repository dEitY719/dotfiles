# obsidian/

Single `obsidian` command (issue #1023) — a **standalone executable on PATH**,
not a shell function.

## Why an executable (not a function)

The real goal is letting **AI agents / skills drive the vault** (~90% of use).
AI coding agents run commands in **non-interactive** shells (`bash -c "..."`),
and shell functions are NOT inherited across the process boundary — only
exported env like `PATH` is. So `obsidian` is a real executable symlinked into
`~/.local/bin` (which `shell-common/env/path.sh` prepends to PATH, ahead of the
Windows `/mnt/c` entries). That single file resolves in **both**:

| Caller | Resolves? |
|--------|-----------|
| Interactive terminal (`obsidian search ...`) | ✅ PATH |
| AI agent `bash -c "obsidian search ..."` (non-interactive) | ✅ PATH inherited |

One executable = one SSOT. No loader wiring, no interactive guard, no function.

## What it does

`bin/obsidian` routes to the right backend for the environment:

| Environment | Backend | Behavior |
|-------------|---------|----------|
| WSL | `Obsidian.com` CLI redirector | forwards subcommands (`search`/`read`/`create`/...) |
| native Linux | latest `Obsidian-*.AppImage` | launches the GUI |

## Wiring

`obsidian/setup.sh` (called from the top-level `setup.sh`) symlinks
`obsidian/bin/obsidian` → `~/.local/bin/obsidian`. SSOT for the link is declared
in `shell-common/config/symlinks.conf`.

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
   registration.
3. The CLI needs the Obsidian app **running** (the first command auto-launches it).
4. DrvFs note: the redirector on `/mnt/c` may lack the Linux `-x` bit, but WSL
   interop runs it anyway — so the launcher tests existence (`-f`), not `-x`.

## Related (optional, not required)

The `obsidian` command only wraps the app CLI — it does **not** depend on the
`kepano/obsidian-skills` plugin. Those skills tell an AI agent *how* to use this
CLI, so they pair well with it:

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

`tests/bats/tools/obsidian.bats` — black-box checks (help, WSL/Linux routing,
env overrides, exit codes) run against the executable. Run:
`./tests/bats/lib/bats-core/bin/bats tests/bats/tools/obsidian.bats`
