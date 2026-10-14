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
| Interactive terminal (`obsidian search ...`) | yes — PATH |
| AI agent `bash -c "obsidian search ..."` (non-interactive) | yes — PATH inherited |

One executable = one SSOT. No loader wiring, no interactive guard, no function.

## What it does

`bin/obsidian` routes to the right backend for the environment. The first
matching row wins:

| Condition | Backend | Behavior |
|-----------|---------|----------|
| REST configured + a subcommand | Local REST API (HTTPS) | `read`/`create`/`search`/`property:set` only — everything else is a loud error |
| REST configured + no args | latest `Obsidian-*.AppImage` | launches the GUI (WSLg window under WSL) |
| WSL | `Obsidian.com` CLI redirector | forwards subcommands (`search`/`read`/`create`/...) |
| native Linux | latest `Obsidian-*.AppImage` | launches the GUI |

"REST configured" = both `OBSIDIAN_REST_API_KEY` and `OBSIDIAN_REST_API_URL`
are non-empty. No network probe is involved — reachability is the request's
problem, not the router's. On a PC that never sets them, behavior is
byte-for-byte what it was before the REST backend existed.

REST backend 상세(자격증명 파일, 지원/미지원 서브커맨드), WSL 전제조건, 관련 스킬,
테스트 설계는 [`README.md`](./README.md).

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
| `OBSIDIAN_REST_API_KEY` | REST auth | — (falls back to `~/.config/obsidian-rest-api/env`) |
| `OBSIDIAN_REST_API_URL` | REST base URL | — (ditto; e.g. `https://127.0.0.1:27124`) |

## Usage

```bash
obsidian search query="PARA" limit=5
obsidian read file="My Note"
obsidian property:set name="status" value="done" file="My Task"
obsidian create name="New Note" path="folder/New Note.md" content="# Hello" silent
obsidian backlinks file="My Note"   # native CLI only — refused by the REST backend
obsidian            # no args -> launch / focus the app
obsidian -h         # wrapper help
```

## Tests

`./tests/bats/lib/bats-core/bin/bats tests/bats/tools/obsidian.bats` (mock 설계: README.md).
