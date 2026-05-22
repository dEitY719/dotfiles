#!/bin/bash

# scripts/setup-company-skills.sh: layer a private skills overlay into
# every active Claude Code config dir.
#
# PURPOSE: take entries from a user-supplied private skills repo
#   ($COMPANY_SKILLS_HOME, default ${HOME}/company-skills) and add them
#   as entry-level symlinks inside ~/.claude*/skills/, which
#   claude/setup.sh has just materialised as real directories of
#   entry-level symlinks (issue #707, F-8).
#
# WHEN TO RUN: via ./setup.sh, after claude/setup.sh. Safe to run on
#   hosts that do not have a private skills repo — when the source
#   directory is missing the script prints one info line and exits 0.
#
# DESIGN NOTES (issue #707):
#   - The dotfiles tree must never carry private skill content. The
#     symlinks created here point at $COMPANY_SKILLS_HOME, which lives
#     outside the dotfiles working tree. The .gitignore rule for
#     /company-skills/ guards against accidental clone-into-root.
#   - Collision policy (F-4): if a target ~/.claude*/skills/<name>
#     already exists (as a symlink, file, or directory) and is not
#     already pointing at the same private skill, dotfiles wins. The
#     overlay link is skipped and a one-line warning is emitted.
#   - Idempotent: re-running the script is a no-op when overlays are
#     already in place. Stale overlay links whose source was removed
#     from the private repo are cleaned up.

# --- Constants ---

_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"

COMPANY_SKILLS_HOME="${COMPANY_SKILLS_HOME:-${HOME}/company-skills}"

# Load UX library
UX_LIB="${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
if [ -f "$UX_LIB" ]; then
    # shellcheck source=/dev/null
    source "$UX_LIB"
else
    echo "Error: UX library not found at $UX_LIB" >&2
    exit 1
fi

log_info() { ux_info "$1"; }
log_warning() { ux_warning "$1"; }
log_error() { ux_error "$1"; }
log_dim() { echo "${UX_DIM}$1${UX_RESET}"; }

# --- Functions ---

# Emit one absolute path per ~/.claude*/skills/ directory that already
# exists as a real (non-symlink) directory. claude/setup.sh has just
# converted these from the legacy directory-symlink layout (#575) to the
# entry-composition layout (#707, F-8). If we can't find any real-dir
# targets, this is either a fresh install where setup.sh has not run
# yet or a host where the user opted out — either way, no-op.
_enumerate_target_skills_dirs() {
    # Single-account internal-PC layout.
    if [ -d "${HOME}/.claude/skills" ] && [ ! -L "${HOME}/.claude/skills" ]; then
        printf '%s\n' "${HOME}/.claude/skills"
    fi
    # Multi-account layouts (#287 / #571). Globs may not match — guard.
    for _esd in "${HOME}/.claude-"*/skills; do
        [ -d "$_esd" ] || continue
        [ -L "$_esd" ] && continue
        printf '%s\n' "$_esd"
    done
}

# Add overlay entries from $COMPANY_SKILLS_HOME into a single target dir.
# Collision policy: existing entry that is NOT already the desired
# overlay symlink → preserve and warn (dotfiles wins).
_overlay_one_target() {
    local target_dir="$1"
    local added=0
    local refreshed=0
    local skipped=0
    local pruned=0

    local entry name link want
    for entry in "$COMPANY_SKILLS_HOME"/*/; do
        [ -d "$entry" ] || continue
        name="${entry%/}"
        name="${name##*/}"
        # Defense against names that would break filesystem invariants
        # ("..", absolute path, "/", embedded slashes). A well-formed
        # private skills repo will not hit this, but a misconfigured
        # one shouldn't get to clobber arbitrary paths.
        case "$name" in
            "" | "." | ".." | */*)
                log_warning "  skip suspicious entry name: '$name'"
                continue
                ;;
        esac

        # Claude Code skill convention: a directory is a skill only if
        # it contains SKILL.md. Skip metadata directories that may live
        # alongside real skills in a marketplace-shaped overlay repo —
        # e.g. .claude-plugin/, plugins/, tests/, docs/ (issue #715).
        if [ ! -f "${entry}SKILL.md" ]; then
            continue
        fi

        link="${target_dir}/${name}"
        want="${COMPANY_SKILLS_HOME}/${name}"

        if [ -L "$link" ]; then
            if [ "$(readlink "$link")" = "$want" ]; then
                # already linked — no-op
                continue
            fi
            # Different symlink target. Two cases:
            #   1. Points into the dotfiles skills tree → dotfiles wins
            #      per F-4. Leave alone and warn.
            #   2. Points elsewhere (stale overlay, user-managed link)
            #      → refresh to the current private skill location.
            local existing_target
            existing_target="$(readlink "$link")"
            case "$existing_target" in
                "${DOTFILES_ROOT}"/claude/skills/*)
                    log_warning "  name conflict (dotfiles wins): $name"
                    skipped=$((skipped + 1))
                    continue
                    ;;
            esac
            rm -f "$link"
            refreshed=$((refreshed + 1))
        elif [ -e "$link" ]; then
            log_warning "  name conflict (existing file/dir, dotfiles wins): $name"
            skipped=$((skipped + 1))
            continue
        else
            added=$((added + 1))
        fi

        ln -s "$want" "$link" || {
            log_error "  symlink failed: $link -> $want"
            return 1
        }
    done

    # Cleanup: prune stale overlay symlinks whose source was removed
    # from the private repo. Only touch symlinks pointing into
    # $COMPANY_SKILLS_HOME so dotfiles entries and user-managed
    # symlinks are not affected.
    local existing target_path
    for existing in "$target_dir"/*; do
        [ -L "$existing" ] || continue
        target_path="$(readlink "$existing")"
        case "$target_path" in
            "${COMPANY_SKILLS_HOME}"/*)
                # Stale if the source dir vanished OR its SKILL.md is
                # gone — the overlay guard above no longer accepts it
                # either way, so keep both sides consistent (#715).
                if [ ! -d "$target_path" ] || [ ! -f "${target_path}/SKILL.md" ]; then
                    log_info "  removing stale overlay entry: $existing"
                    rm -f "$existing"
                    pruned=$((pruned + 1))
                fi
                ;;
        esac
    done

    log_dim "  $target_dir (added=$added refreshed=$refreshed skipped=$skipped pruned=$pruned)"
}

# --- Main ---

ux_section "Company skills overlay (issue #707)"
log_info "COMPANY_SKILLS_HOME=$COMPANY_SKILLS_HOME"

if [ ! -d "$COMPANY_SKILLS_HOME" ]; then
    log_info "private overlay dir not present — skipping (no-op on public PCs)"
    exit 0
fi

# Canonicalise to an absolute path so the readlink-prefix match in
# _overlay_one_target stays correct even when the caller passed a
# relative path or one with trailing slashes. POSIX-only (`cd && pwd`,
# no `realpath` dependency) to keep the script portable across the
# OS-X / Linux / busybox set of hosts dotfiles supports.
COMPANY_SKILLS_HOME="$(cd "$COMPANY_SKILLS_HOME" && pwd)"

# Empty private repo: no entries to layer. Not an error.
# Apply the same SKILL.md guard as _overlay_one_target so a repo that
# only carries metadata dirs (.claude-plugin/, plugins/, tests/, …) is
# treated as empty here too — otherwise the main loop runs to completion
# with all-zero counters and prints a misleading "overlay applied"
# success line. Suggested by gemini-code-assist on PR #717.
_has_entries=0
for _e in "$COMPANY_SKILLS_HOME"/*/; do
    [ -d "$_e" ] || continue
    [ -f "${_e}SKILL.md" ] || continue
    _has_entries=1
    break
done
if [ "$_has_entries" -eq 0 ]; then
    log_info "private overlay dir is empty — skipping"
    exit 0
fi

_target_dirs="$(_enumerate_target_skills_dirs)"
if [ -z "$_target_dirs" ]; then
    log_warning "no ~/.claude*/skills/ target found — has claude/setup.sh run yet?"
    exit 0
fi

_failed_count=0
while IFS= read -r _tgt; do
    [ -n "$_tgt" ] || continue
    if ! _overlay_one_target "$_tgt"; then
        _failed_count=$((_failed_count + 1))
    fi
done <<EOF
$_target_dirs
EOF

if [ "$_failed_count" -gt 0 ]; then
    log_warning "overlay failed for $_failed_count target(s) — see log above"
    log_info "rerun ./setup.sh once the cause is fixed; overlay is idempotent"
    exit 1
fi

ux_success "company-skills overlay applied"
