# Project Context

- **Objective**: Opinionated Bash dotfiles for reproducible terminal environments (WSL, Linux, macOS).
- **Stack**: Bash 5.x+, Python 3.10+, mise, Ruff, Mypy.
- **Structure**: Modular Bash (`bash/`), Zsh (`zsh/`), shared shell (`shell-common/`), Tests (`tests/`), Docs (`docs/`), Git hooks (`git/`), Claude Code (`claude/`), Windows Terminal Shift+Enter merge (`windows/setup.sh`, WSL only).

# Package Manager Configuration

All managed by `shell-common/setup.sh` (environment menu: public / internal / external).

| Manager | Config Dir | Target | Method | Gate |
|---------|-----------|--------|--------|------|
| npm | `npm/` | `~/.npmrc` | symlink | -- |
| pip | `pip/` | `~/.config/pip/pip.conf` | symlink | -- |
| uv | `uv/` | `~/.config/uv/uv.toml` | symlink | -- |
| Cargo | `cargo/` | `~/.cargo/config.toml` | symlink | -- |
| NuGet | `nuget/` | `~/.nuget/NuGet/` + `~/.config/NuGet/` | symlink (dual) | -- |
| RPM | `rpm/` | `/etc/yum.repos.d/ds.repo` | sudo copy | RHEL 8.x + yum/dnf |
| APT | `apt/` | `/etc/apt/sources.list` | sudo copy | Ubuntu + codename match |

- **User-level** (npm/pip/uv/cargo/nuget): symlink to `{dir}/{config}.internal`, backup+restore on switch.
- **System-level** (rpm/apt): sudo copy with 3-gate safety (tool exists, OS match, privilege), `MANAGED_BY_DOTFILES` marker.
- **Adding new manager**: create `{dir}/{config}.internal`, add `setup_{name}()`, wire into `main()` 3 menu cases.

# Golden Rules

## Immutable Constraints

- **100-Line Limit**: Every AGENTS.md file must be under 100 lines — use nested AGENTS.md files for detail.
- **No Emojis**: Strictly prohibited to save tokens.
- **Interactive Guards**: Bash files must guard execution: `[[ $- == *i* ]]`.
- **Loading Order**: Respect `bash/main.bash` priority (Env -> UX -> Alias -> App).
- **No Direct Writes**: Do not write to `~/.bashrc` directly; use symlinks via `setup.sh`.

## Do's & Don'ts

- **DO**: Use `ux_lib` functions (`ux_header`, `ux_success`) for ALL output.
- **DO**: Use snake_case for all Bash functions and filenames.
- **DO**: Run `mise run lint && mise run test` before committing.
- **DO**: Use environment variables (e.g., `$SHELL_COMMON`) for sourcing files across shell contexts.
- **DO**: Test scripts in both bash and zsh for cross-shell compatibility.
- **DO**: Follow directory placement rules — see **[Shell Common](./shell-common/AGENTS.md)**.
- **DON'T**: Use raw `echo` or `printf` (violates UX consistency).
- **DON'T**: Hardcode paths; use `$HOME` or relative paths.
- **DON'T**: Commit secrets or sensitive data.
- **DON'T**: Use `${BASH_SOURCE[0]%/*}` for sourcing (bash-only, fails in zsh); use `${SHELL_COMMON}/path`.

See **[Shell Common](./shell-common/AGENTS.md)** for directory placement guide (aliases/ vs functions/ vs tools/),
Direct-Exec Guard pattern, Bash/Zsh compatibility rules, and diagnostic design standards.

# Standards & References

- **Coding Style**: See `shell-common/tools/ux_lib/UX_GUIDELINES.md`, `pyproject.toml`, and `mise.toml`.
- **Git Strategy**: Semantic commits (`Type: Summary`).
- **Known Pitfalls**: `Agent({ isolation: "worktree" })` is blocked by git-crypt smudge filter in this repo — see `claude/AGENTS.md` ("Known Pitfall: Agent isolation + git-crypt") and `docs/guide/learnings/git-crypt-worktree-bootstrap.md`.
- **Maintenance**: Update AGENTS.md when adding new modules.

# Context Map

- **[Bash Module](./bash/AGENTS.md)** — Bash-specific configuration and utilities
- **[Zsh Module](./zsh/AGENTS.md)** — Zsh-specific configuration and applications
- **[Shell Common](./shell-common/AGENTS.md)** — POSIX-compatible shared utilities (env, aliases, functions, tools, projects)
- **[Git Hooks & Config](./git/AGENTS.md)** — Hook system, git config, and hook documentation
- **[Claude Code](./claude/AGENTS.md)** — Claude Code configuration, settings, skills, and automation
- **[graphify](./graphify/AGENTS.md)** — graphify knowledge-graph skill install + per-account links (manual opt-in)
- **[Python Tests](./tests/AGENTS.md)** — pytest suite and cross-shell compatibility checks
- **[Documentation](./docs/AGENTS.md)** — Project docs, AGENTS.md master prompt, SOLID reviews

See **[Claude Code](./claude/AGENTS.md)** for skills management, multi-CLI registry, and commands.

<!-- my-share:changelog:begin -->
## 변경 기록 (changelog)

- 현재 OFF. changelog 를 갱신하지 않는다(허브 수집 일시 중단).
- 재활성화는 my-share 에서 `python3 scripts/changelog_toggle.py on`.
<!-- my-share:changelog:end -->

- 상세와 재개 조건은 `CLAUDE.md` → "변경 기록 (changelog)" 참고.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
