#!/bin/sh
# shell-common/functions/wsl_check.sh
# WSL & Docker environment health check — a single source of truth for the
# Windows host C: drive / WSL disk / memory / CPU / Docker reclaimable space.
#
# Motivation (issue #897): a full WSL crash (SIGBUS / E_UNEXPECTED) during a
# Docker build was caused by the *Windows host C: drive* — not the WSL disk —
# running out of space (the vhdx could not grow). So the host C: drive is the
# primary risk indicator and is always shown first.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# --- thresholds (SSOT: function-internal defaults, env-overridable) ----------
_wsl_check_thresholds() {
    : "${WSL_CHECK_DISK_WARN:=90}"        # disk / mem / cpu warn %
    : "${WSL_CHECK_CDRIVE_MIN_GB:=10}"    # host C: avail floor (GB) — #897 cause
    : "${WSL_CHECK_DOCKER_RECLAIM_GB:=5}" # docker reclaimable auto-prune trigger
    : "${WSL_CHECK_AUTO_PRUNE:=0}"        # 1 = auto-prune on --all over threshold
}

# timeout wrapper — degrades gracefully where coreutils `timeout` is absent.
_wsl_check_timeout() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$@"
    else
        shift
        "$@"
    fi
}

# True only when $1 is a real mountpoint. `/mnt/c` can exist as a bare
# directory without being mounted (automount off, or a non-WSL host), in
# which case `df /mnt/c` silently reports the root fs — the trailing-space
# match avoids substring false positives (e.g. /mnt/cd).
_wsl_check_is_mounted() { # $1 = mountpoint
    mount 2>/dev/null | grep -q " on $1 "
}

# --- metric gatherers (each prints digits-only, or empty on failure) ---------
# `command df/free` bypasses the `df -h` / `free -h` aliases defined in
# aliases/core.sh, so -P output stays machine-parseable.
_wsl_check_cdrive_pct() {
    _wsl_check_is_mounted /mnt/c || return 0
    command df -P /mnt/c 2>/dev/null | awk 'NR==2 { gsub(/%/, "", $5); print $5 }'
}

_wsl_check_cdrive_avail_gb() {
    _wsl_check_is_mounted /mnt/c || return 0
    # -P -k = POSIX-portable 1024-byte blocks (avoids the GNU-only -BG); the
    # explicit -k removes the 512-vs-1024 block ambiguity of bare -P, so the
    # /1048576 (1024^2) byte->GB conversion is correct everywhere.
    command df -P -k /mnt/c 2>/dev/null | awk 'NR==2 { printf "%d", $4 / 1048576 }'
}

_wsl_check_disk_pct() {
    command df -P / 2>/dev/null | awk 'NR==2 { gsub(/%/, "", $5); print $5 }'
}

# WSL root-fs used space in whole GB — the "real" occupancy inside the vhdx,
# compared against the host vhdx file size to estimate compaction headroom.
_wsl_check_disk_used_gb() {
    command df -P -k / 2>/dev/null | awk 'NR==2 { printf "%d", $3 / 1048576 }'
}

# Host-side ext4.vhdx path — the WSL virtual disk grows but never auto-shrinks.
# Single-distro assumption (#900): first ext4.vhdx under any user's Store-WSL
# package. Empty when /mnt/c is unmounted or no vhdx exists (non-WSL host).
_wsl_check_vhdx_path() {
    _wsl_check_is_mounted /mnt/c || return 0
    for _vh in /mnt/c/Users/*/AppData/Local/Packages/*/LocalState/ext4.vhdx; do
        [ -f "$_vh" ] && {
            printf '%s\n' "$_vh"
            return 0
        }
    done
    # No match: the loop's last command is a failed `[ -f ]` (exit 1); without
    # this the function would return 1 and trip a caller's `set -e` (#900).
    return 0
}

# Size of the host vhdx file in whole GB. `wc -c < file` fstat's a regular
# file on GNU/BSD (no full read) and is portable, unlike `ls -l` column
# parsing (locale / owner-name width can shift fields). Empty on failure.
_wsl_check_vhdx_size_gb() { # $1 = vhdx path
    [ -f "$1" ] || return 0
    wc -c <"$1" 2>/dev/null | awk '{ printf "%d", $1 / 1073741824 }'
}

_wsl_check_mem_pct() {
    awk '/^MemTotal:/ { t=$2 } /^MemAvailable:/ { a=$2 } \
         END { if (t > 0) printf "%d", (t - a) * 100 / t }' /proc/meminfo 2>/dev/null
}

_wsl_check_cpu_pct() {
    ncpu=$(nproc 2>/dev/null || echo 1)
    awk -v n="$ncpu" '{ p = $1 / n * 100; if (p > 100) p = 100; printf "%d", p }' \
        /proc/loadavg 2>/dev/null
}

_wsl_check_docker_img_pct() {
    command -v docker >/dev/null 2>&1 || return 0
    _wsl_check_timeout 1 docker system df 2>/dev/null |
        awk '/^Images/ { v=$NF; gsub(/[^0-9]/, "", v); if (v ~ /^[0-9]+$/) print v }'
}

# Total docker reclaimable space in whole GB (best-effort sum across types).
_wsl_check_docker_reclaim_gb() {
    command -v docker >/dev/null 2>&1 || return 0
    _wsl_check_timeout 2 docker system df --format '{{.Reclaimable}}' 2>/dev/null |
        awk '{ x=$1;
                 if (x ~ /GB/)      { sub(/GB/, "", x); s += x }
                 else if (x ~ /MB/) { sub(/MB/, "", x); s += x / 1024 } }
               END { printf "%d", s }'
}

# --- one-line summary (manual printf: a single line with per-field coloring
#     is not expressible via ux_bullet/ux_table_*; same sanctioned exception
#     gpu_status.sh uses for its custom layout) ----------------------------

# 256-color orange (setaf 214) with yellow fallback; empty when ANSI disabled
_WSL_CHECK_ORANGE=""
if [ -n "$UX_RESET" ]; then
    _WSL_CHECK_ORANGE=$(tput setaf 214 2>/dev/null || tput setaf 3 2>/dev/null || echo "")
fi

_wsl_check_seg() { # $1=label $2=value $3=severity(ok|mid|hi|warn|crit)
    color="$UX_MUTED"
    case "$3" in
    mid)  color="" ;;
    hi)   color="$_WSL_CHECK_ORANGE" ;;
    warn) color="$UX_WARNING" ;;
    crit) color="$UX_ERROR" ;;
    esac
    printf '%s%s:%s%s' "$color" "$1" "$2" "$UX_RESET"
}

# Maps a % to severity for _wsl_check_seg: <40=ok(dim) 40=mid(white) 60=hi(orange) 80=crit(red)
_wsl_check_pct_sev() { # $1 = pct (empty or non-numeric → ok)
    [ -z "${1:-}" ] && { echo ok; return 0; }
    case "${1:-}" in
        *[!0-9]*) echo ok; return 0 ;;
    esac
    if [ "${1:-0}" -ge 80 ]; then echo crit
    elif [ "${1:-0}" -ge 60 ]; then echo hi
    elif [ "${1:-0}" -ge 40 ]; then echo mid
    else echo ok
    fi
}

_wsl_check_oneline() {
    _wsl_check_thresholds

    # Each segment is built into its own variable so the _wsl_check_seg call
    # is never preceded by a quote on the line — the pre-commit naming check
    # greedily flags "<snake_func>" patterns, and a leading `line="` quote
    # would trip it (the call args are themselves quoted).

    # c-drive (Windows host) — primary risk indicator, shown first (#897)
    cd_pct=$(_wsl_check_cdrive_pct)
    if [ -z "$cd_pct" ]; then
        seg_cd=$(_wsl_check_seg c-drive "n/a" ok)
    else
        cd_av=$(_wsl_check_cdrive_avail_gb)
        sev=$(_wsl_check_pct_sev "$cd_pct")
        [ -n "$cd_av" ] && [ "$cd_av" -lt "$WSL_CHECK_CDRIVE_MIN_GB" ] && sev=crit
        seg_cd=$(_wsl_check_seg c-drive "${cd_pct}%" "$sev")
    fi

    # WSL root disk
    d_pct=$(_wsl_check_disk_pct)
    sev=$(_wsl_check_pct_sev "$d_pct")
    seg_disk=$(_wsl_check_seg disk "${d_pct:-?}%" "$sev")

    # CPU (1-min loadavg vs cores — instant, non-blocking)
    c_pct=$(_wsl_check_cpu_pct)
    sev=$(_wsl_check_pct_sev "$c_pct")
    seg_cpu=$(_wsl_check_seg cpu "${c_pct:-?}%" "$sev")

    # Memory
    m_pct=$(_wsl_check_mem_pct)
    sev=$(_wsl_check_pct_sev "$m_pct")
    seg_mem=$(_wsl_check_seg mem "${m_pct:-?}%" "$sev")

    # Docker images reclaimable % — hint shown when value is unavailable
    dk=""
    dk_hint=""
    if ! command -v docker >/dev/null 2>&1; then
        dk_hint="no docker"
    else
        dk=$(_wsl_check_docker_img_pct)
        [ -z "$dk" ] && dk_hint="daemon off"
    fi
    if [ -z "$dk" ]; then
        seg_docker=$(_wsl_check_seg docker "?(${dk_hint})" ok)
    else
        sev=ok
        [ "$dk" -ge 50 ] && sev=warn
        seg_docker=$(_wsl_check_seg docker "${dk}%" "$sev")
    fi

    printf '%s %s %s %s %s\n' "$seg_cd" "$seg_disk" "$seg_cpu" "$seg_mem" "$seg_docker"
}

# --- detailed report ---------------------------------------------------------
_wsl_check_df_section() { # $1=title $2=mountpoint
    ux_section "$1"
    if [ ! -d "$2" ]; then
        ux_warning "$2 not mounted (non-WSL host?)"
        return 0
    fi
    # `/` is always a mountpoint; any other target must be really mounted,
    # else df silently reports the root fs and C: mirrors the WSL disk.
    if [ "$2" != "/" ]; then
        _wsl_check_is_mounted "$2" || {
            ux_warning "$2 not mounted (non-WSL host?)"
            return 0
        }
    fi
    # shellcheck disable=SC2046  # intentional word-split of the df row
    set -- $(command df -h -P "$2" 2>/dev/null | awk 'NR==2 { print $2, $3, $4, $5 }')
    ux_table_row "Size" "${1:-?}"
    ux_table_row "Used" "${2:-?}"
    ux_table_row "Avail" "${3:-?}"
    ux_table_row "Use%" "${4:-?}"
}

# vhdx compaction advisory: the host C: drive only reclaims space when the
# vhdx is compacted from the Windows host (see `wsl-check -h`) — pruning inside
# WSL frees the fs but leaves the vhdx file just as large. Silently skipped on
# a non-WSL host or when no vhdx is found (graceful, no warning row).
_wsl_check_vhdx_report() {
    vpath=$(_wsl_check_vhdx_path)
    [ -n "$vpath" ] || return 0
    vsize=$(_wsl_check_vhdx_size_gb "$vpath")
    [ -n "$vsize" ] || return 0
    vused=$(_wsl_check_disk_used_gb)

    ux_section "[2b] WSL vhdx Compaction"
    ux_table_row "vhdx file (host)" "${vsize}G allocated"
    if [ -n "$vused" ] && [ "$vsize" -gt "$vused" ]; then
        ux_table_row "Reclaimable" "~$((vsize - vused))G by compaction"
        ux_info "Compact from the Windows host — see 'wsl-check -h'."
    else
        ux_table_row "Reclaimable" "compaction unnecessary"
    fi
}

_wsl_check_full() {
    _wsl_check_thresholds
    ux_header "WSL & Docker Environment Health"

    _wsl_check_df_section "[1] Windows C: Drive (host)" /mnt/c
    _wsl_check_df_section "[2] WSL Virtual Disk (/)" /
    _wsl_check_vhdx_report

    ux_section "[3] Memory & Swap"
    # shellcheck disable=SC2046
    set -- $(command free -h 2>/dev/null | awk 'NR==2 { print $2, $3, $7 }')
    ux_table_row "Total" "${1:-?}"
    ux_table_row "Used" "${2:-?}"
    ux_table_row "Available" "${3:-?}"

    ux_section "[4] Docker Reclaimable"
    if ! command -v docker >/dev/null 2>&1; then
        ux_warning "docker not installed"
    elif ! _wsl_check_timeout 2 docker info >/dev/null 2>&1; then
        ux_warning "docker daemon not running"
    else
        _wsl_check_timeout 3 docker system df \
            --format '{{.Type}}|{{.Size}}|{{.Reclaimable}}' 2>/dev/null |
            while IFS='|' read -r dtype dsize drec; do
                ux_table_row "$dtype" "$dsize  (reclaimable $drec)"
            done
    fi

    # auto-prune guard (opt-in, build-cache + dangling only, never destructive
    # beyond that; the interactive guard lives in _wsl_check_prune)
    if [ "$WSL_CHECK_AUTO_PRUNE" = "1" ]; then
        rec=$(_wsl_check_docker_reclaim_gb)
        if [ -n "$rec" ] && [ "$rec" -ge "$WSL_CHECK_DOCKER_RECLAIM_GB" ]; then
            ux_info ""
            ux_warning "Docker reclaimable ${rec}GB >= ${WSL_CHECK_DOCKER_RECLAIM_GB}GB — auto-pruning"
            _wsl_check_prune builder
        fi
    fi
}

# --- prune (destructive — single chokepoint with the interactive guard) ------
_wsl_check_prune() { # $1 = builder | system
    case $- in *i*) ;; *)
        ux_warning "non-interactive shell — refusing destructive prune"
        return 0
        ;;
    esac
    if ! command -v docker >/dev/null 2>&1; then
        ux_warning "docker not installed — nothing to prune"
        return 0
    fi
    if ! _wsl_check_timeout 2 docker info >/dev/null 2>&1; then
        ux_warning "docker daemon not running — skip prune"
        return 0
    fi
    case "$1" in
    system)
        ux_warning "FULL prune: stopped containers + unused networks + dangling images + build cache"
        docker system prune -f
        ;;
    *)
        ux_info "Pruning build cache + dangling images (safe set)"
        docker builder prune -f
        docker image prune -f
        ;;
    esac
    ux_success "Prune complete"
}

# --- dispatcher --------------------------------------------------------------
wsl_check() {
    _wsl_check_thresholds
    case "${1:-}" in
    "") _wsl_check_oneline ;;
    --all | all) _wsl_check_full ;;
    --prune)
        _wsl_check_full
        _wsl_check_prune builder
        ;;
    --prune-all)
        _wsl_check_full
        _wsl_check_prune system
        ;;
    -h | --help | help)
        if command -v wsl_check_help >/dev/null 2>&1; then
            wsl_check_help
        else
            ux_info "wsl-check [--all|--prune|--prune-all|-h]"
        fi
        ;;
    *)
        ux_error "wsl-check: unknown option '$1'"
        ux_info "Try: wsl-check -h"
        return 1
        ;;
    esac
}

alias wsl-check='wsl_check'
