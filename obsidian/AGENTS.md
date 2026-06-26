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

## 비-인터랙티브 / AI 에이전트 사용

`obsidian` 은 **셸 함수**라서 인터랙티브 셸에서만 로드된다 (로더의
`should_skip_init` + 파일 상단 interactive 가드). 함수는 자식 프로세스로
상속되지 않으므로, AI 코딩 에이전트가 `bash -c "obsidian ..."` 처럼
**비-인터랙티브** 셸로 호출하면 함수가 잡히지 않는다.

비-인터랙티브 컨텍스트에서는 풀 경로 또는 `OBSIDIAN_CLI_BIN` 을 직접 쓴다:

```bash
"${OBSIDIAN_CLI_BIN:-/mnt/c/Program Files/Obsidian/Obsidian.com}" search query="PARA"
```

> 함수를 비-인터랙티브에서도 쓰게 하려면 PATH 위의 실행파일로 전환해야 한다
> (PATH 는 export env 라 자식 프로세스로 상속됨). 이는 #1023 범위 밖 —
> 필요 시 별도 이슈로 다룬다.

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
