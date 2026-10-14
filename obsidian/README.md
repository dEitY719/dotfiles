# obsidian/ — details

> Summary and routing table: [`AGENTS.md`](./AGENTS.md) (split out in #2151).

## REST backend

For the PC whose vault is a single unified copy opened by a Linux AppImage
**inside WSL** (WSLg), not the Windows-native app: there is no `Obsidian.com`
redirector to forward to, so agent access goes through the community plugin
**"Local REST API with MCP"** (`obsidian-local-rest-api`, v5.1.0+) instead.
Credentials come from the environment first, then
`~/.config/obsidian-rest-api/env` fills any gap:

```
OBSIDIAN_REST_API_KEY=<hex key from the plugin's settings tab>
OBSIDIAN_REST_API_URL=https://127.0.0.1:27124
```

A missing, empty, or unreadable file is not an error — routing just falls
through to the legacy rows of the routing table in `AGENTS.md`. Needs `curl` + `jq` on PATH; the plugin's
cert is self-signed, so requests go out with `curl -sk` (no validation, no
pinning). The key is never printed, not even in error output.

### What it covers

| Subcommand | REST call |
|------------|-----------|
| `read` | `GET /vault/<path>` (or `/active/` with no target) |
| `create` | `GET` existence probe, then `PUT /vault/<path>` (`text/markdown`) |
| `search` | `POST /search/simple/?query=…` |
| `property:set` | `PATCH /vault/<path>` — a v2 JSON frontmatter `replace` instruction |

- `path=` is vault-root-relative; `.md` is appended when the basename has no
  extension.
- `file=` resolves like a wikilink. The API has no link resolver, so one
  JsonLogic query lists every note's path and the basename is matched against
  it. Zero matches and multiple matches are both errors — never a silent write
  to the wrong note.
- No `file=`/`path=` targets the active note, matching the native CLI.
- Bare flags (`silent`, `total`, `--copy`, …) only steer the native GUI, which
  the REST backend has no hand in: accepted and ignored. `overwrite` is real —
  without it `create` refuses to clobber an existing note.
- An unknown `key=value` parameter (e.g. `template=`) is a loud error, because
  silently dropping it would write a note the caller did not ask for.

### What it does NOT cover

`append`, `backlinks`, `daily:*`, `tags`, `tasks`, `plugin:*`, `dev:*`, `eval`,
and `vault=` targeting all exit nonzero with a one-line reason. This is
deliberate: the REST API has no equivalent endpoint for them (and talks to
exactly one vault — whichever its Obsidian instance has open), and a
partial emulation would be worse than a refusal. Windows-native Obsidian
(`OBSIDIAN_CLI_BIN`) still implements the full first-party CLI — unset
`OBSIDIAN_REST_API_URL` to route back to it on a PC that has both.

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

`tests/bats/tools/obsidian.bats` — black-box checks (help, WSL/Linux/REST
routing, env overrides, exit codes) run against the executable. Run:
`./tests/bats/lib/bats-core/bin/bats tests/bats/tools/obsidian.bats`

The REST cases mock at the network boundary: a fake `curl` first on `PATH`
records each request and replays canned statuses/bodies, so the assertions are
on the real method/URL/headers/body the script built. Two things stay
untested, for the same reason as before: the native-Linux `_ob_is_wsl` false
branch (the test host *is* WSL) and any behavior of the Obsidian server
itself. Every test isolates `$HOME` — the developer's own
`~/.config/obsidian-rest-api/env` would otherwise reroute the legacy-path
tests into the REST backend.
