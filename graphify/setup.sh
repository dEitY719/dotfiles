#!/bin/bash
# graphify/setup.sh: install the graphify Claude Code skill once and link it
#                    into every enabled Claude account (issue #1844)
#
# PURPOSE: `graphify install` follows CLAUDE_CONFIG_DIR, which a plain terminal
#          does not export, so the skill lands in ~/.claude/skills/graphify and
#          the ~/.claude-<account> dirs never see it. This keeps that one copy
#          as the source and symlinks <cdir>/skills/graphify to it.
# WHEN TO RUN: Manually (opt-in). Not wired into root ./setup.sh — it depends on
#          a pip-installed CLI and network access.
# Idempotent. Soft-fail: every problem is a warning and the script exits 0.
# Help: graphify-help install | graphify-help accounts

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=../shell-common/lib/setup/link.sh
. "${SHELL_COMMON}/lib/setup/link.sh" || exit 1

ux_header "graphify Setup"

if ! command -v graphify >/dev/null 2>&1; then
	ux_warning "graphify CLI not on PATH — nothing to set up"
	ux_bullet "Install it first (Python 3.10+): pip install graphifyy   # or pipx / uv tool install graphifyy"
	ux_bullet "Then re-run: ./graphify/setup.sh"
	exit 0
fi

if [ -f "${GRAPHIFY_SKILL_SRC}/SKILL.md" ]; then
	ux_success "Skill already installed: ${GRAPHIFY_SKILL_SRC}"
else
	ux_info "Installing skill into ~/.claude/skills/graphify"
	if ! env -u CLAUDE_CONFIG_DIR graphify install --platform claude || [ ! -f "${GRAPHIFY_SKILL_SRC}/SKILL.md" ]; then
		ux_warning "graphify install failed — account links skipped"
		ux_bullet "Retry manually: env -u CLAUDE_CONFIG_DIR graphify install --platform claude"
		exit 0
	fi
	ux_success "Installed: ${GRAPHIFY_SKILL_SRC}"
fi

if [ "$(_dotfiles_setup_mode)" = "internal" ]; then
	ux_info "Internal mode (single account ~/.claude) — no account links needed"
	exit 0
fi

for acct in $(_claude_resolve_account --list); do
	cdir=$(_claude_resolve_account "$acct") || continue
	if [ ! -d "$cdir" ]; then
		ux_info "skip ${acct}: ${cdir} does not exist"
		continue
	fi
	link="${cdir}/skills/graphify"
	# keep: a link elsewhere or a real dir is the user's — warn, leave alone.
	if ! dotfiles_ensure_link "$GRAPHIFY_SKILL_SRC" "$link" --on-mismatch keep; then
		ux_warning "${acct}: could not create ${link}"
	elif [ -L "$link" ] && [ "$(cd -P "$link" && pwd)" = "$(cd -P "$GRAPHIFY_SKILL_SRC" && pwd)" ]; then
		ux_success "${acct}: link ok"
	fi
done

ux_info "Run /reload-skills in open Claude Code sessions to pick up the skill"
exit 0
