#!/bin/bash
# windows/setup.sh: Windows Terminal settings.json tweaks (WSL only)
#
# PURPOSE: Bind Shift+Enter to send ESC+CR so Claude Code's TUI inserts a
#          newline instead of submitting. Windows Terminal sends a bare CR for
#          Shift+Enter by default, indistinguishable from Enter.
#          (Ctrl+Enter arrives as LF = ctrl+j, which claude/keybindings.json
#          deliberately binds to chat:sendNow — so Shift+Enter is the newline key.)
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
#
# settings.json is owned by Windows Terminal (it rewrites it from its GUI), so
# this is a one-time idempotent merge, not a symlink. Any existing shift+enter
# binding is left untouched. Soft-fail throughout: never abort the parent
# setup.sh (set -e) — warn and move on.
#
# Override the target with WT_SETTINGS_FILE (used by tests).

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SCRIPT_DIR%/windows}/shell-common/tools/ux_lib/ux_lib.sh"

_wt_settings_file() {
	[ -n "${WT_SETTINGS_FILE-}" ] && { printf '%s\n' "$WT_SETTINGS_FILE"; return 0; }
	command -v cmd.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1 || return 1
	local win local_appdata
	win=$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r\n')
	[ -n "$win" ] || return 1
	local_appdata=$(wslpath -u "$win" 2>/dev/null) || return 1
	printf '%s\n' "${local_appdata}/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
}

ux_header "Windows Terminal Setup"

WT_SETTINGS=$(_wt_settings_file) || { ux_info "WSL/Windows Terminal 아님 — 건너뜀"; exit 0; }
[ -f "$WT_SETTINGS" ] || { ux_info "Windows Terminal settings.json 없음 — 건너뜀: $WT_SETTINGS"; exit 0; }

# Exit codes: 0 = added, 3 = already bound, other = failure (e.g. JSONC comments).
_rc=0
python3 - "$WT_SETTINGS" <<'EOF' || _rc=$?
import json, shutil, sys, time
p = sys.argv[1]
with open(p, encoding="utf-8-sig") as f:
    d = json.load(f)
binds = d.setdefault("keybindings", [])
if any(b.get("keys") == "shift+enter" for b in binds):
    sys.exit(3)
aid = "User.sendInput.ShiftEnterNewline"
d.setdefault("actions", []).append(
    {"command": {"action": "sendInput", "input": "\u001b\r"}, "id": aid})
binds.append({"id": aid, "keys": "shift+enter"})
shutil.copy2(p, p + time.strftime(".bak-%Y%m%d%H%M%S"))
with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f, indent=4, ensure_ascii=False)
    f.write("\n")
EOF

case $_rc in
	0) ux_success "Shift+Enter → ESC+CR (Claude Code 줄바꿈) 바인딩 추가: $WT_SETTINGS" ;;
	3) ux_info "Shift+Enter 바인딩 이미 있음 — 유지" ;;
	*) ux_warning "Windows Terminal settings.json 수정 실패 (주석 포함 JSONC 등). 수동 추가: actions 에 sendInput \"\\u001b\\r\", keybindings 에 shift+enter" ;;
esac
exit 0
