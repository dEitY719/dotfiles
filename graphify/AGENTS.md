# graphify Module

Installs the [graphify](https://discuss.pytorch.kr/t/graphify-ai-knowledge-graph/9652)
Claude Code skill once and exposes it to every Claude account (issue #1844).
Not to be confused with `graphify-out/` at the repo root — that is the graph
output directory, this is the setup module.

## Files

| File | Role |
|------|------|
| `setup.sh` | Idempotent: install skill to `~/.claude/skills/graphify`, link it into each account |
| `uninstall.sh` | Remove only the account links `setup.sh` made; print graphify's own uninstall commands |
| `lib.sh` | Shared bootstrap (ux_lib, `_claude_resolve_account`, `GRAPHIFY_SKILL_SRC`) — sourced, not run |

Help: `graphify-help` (`shell-common/functions/graphify_help.sh`, category `ai`).
Vault export: `graphify-vault` (`shell-common/functions/graphify_vault.sh`) writes `~/vaults/<repo>-graph` from the current repo's `graphify-out/`.
Tests: `tests/bats/setup/graphify_setup.bats`.

## Why links

`graphify install` follows `CLAUDE_CONFIG_DIR`, which a plain terminal does not
export, so the skill lands in `~/.claude/skills/graphify` and the
`~/.claude-<account>` dirs never see it. One source + a symlink per account
means a graphify upgrade updates every account at once.

`graphify claude install` (CLAUDE.md section + PreToolUse hook) does not
install the skill — it is a separate step and not run by `setup.sh`.

## Rules

- **Manual opt-in**: not called from root `./setup.sh` — the CLI comes from
  `pip install graphifyy` (needs network / proxy), which `setup.sh` never runs.
- **Soft-fail**: every problem is a warning, exit status is always 0.
- **Never clobber**: a real directory or a link pointing elsewhere at
  `<cdir>/skills/graphify` is reported and left alone, by both scripts.
- **Internal mode** (`~/.dotfiles-setup-mode` = internal): single account
  `~/.claude`, so the link step is skipped.
- Account list comes from `_claude_resolve_account --list`
  (`shell-common/tools/integrations/claude.sh`); missing account dirs are skipped.
- The links survive `claude/setup.sh`: `_claude_compose_workspace_skills` only
  prunes links into the skills workspace root.
