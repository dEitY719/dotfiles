#!/bin/bash
# graphify/uninstall.sh: remove the per-account graphify skill links that
#                        graphify/setup.sh created (issue #1844)
#
# Removes <cdir>/skills/graphify only when it is a symlink to
# ~/.claude/skills/graphify. Real directories and foreign links are never
# touched. Removing the source skill / hook is left to graphify itself —
# this script only prints those commands, it does not run them.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ux_header "graphify Uninstall"

for acct in $(_claude_resolve_account --list); do
	cdir=$(_claude_resolve_account "$acct") || continue
	link="${cdir}/skills/graphify"
	if [ -L "$link" ] && [ "$(readlink "$link")" = "$GRAPHIFY_SKILL_SRC" ]; then
		if rm "$link"; then
			ux_success "${acct}: removed ${link}"
		else
			ux_warning "${acct}: could not remove ${link}"
		fi
	elif [ -e "$link" ] || [ -L "$link" ]; then
		ux_warning "${acct}: ${link} is not our link — left alone"
	fi
done

ux_section "Next (run by hand if you want graphify gone entirely)"
ux_bullet "graphify claude uninstall      # CLAUDE.md section + PreToolUse hook"
ux_bullet "graphify uninstall             # skill from every detected platform"
ux_bullet "graphify uninstall --purge     # ...and delete graphify-out/"
ux_bullet "pip uninstall graphifyy        # the CLI itself"
exit 0
