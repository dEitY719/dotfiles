#!/bin/bash

set -euo pipefail

# -----------------------------------------------------------------------------
# gh:label-bootstrap — sync a target repo's GitHub labels to the dotfiles SSOT.
#
# SSOT feed: docs/.ssot/gh-labels.md (plain-feed blocks). This script parses
# that file directly — it holds no second hardcoded copy of the label set.
#
# Behavior (see docs/.ssot/gh-labels.md for the authoritative spec):
#   1. Alias renames first  — PATCH old -> new_name (preserves issue/PR links).
#   2. SSOT 10 apply         — PATCH if exists (force color/description sync),
#                              POST if missing.
#   3. Prune (only --prune)  — DELETE labels outside SSOT ∪ alias-targets ∪
#                              allowlist, computed AFTER renames.
#
# --dry-run makes ZERO mutating gh api calls (no POST/PATCH/DELETE).
# --prune defaults OFF; without it no label is ever deleted.
# Per-label API failures warn on stderr and continue (never abort the run).
# -----------------------------------------------------------------------------

REPO=""
DRY_RUN=false
PRUNE=false

# Prune allowlist: GitHub default labels always preserved (SSOT).
# Newline-separated — entries like "good first issue" contain spaces.
ALLOWLIST=$'enhancement\nduplicate\ngood first issue\nhelp wanted\ninvalid\nquestion\nwontfix'

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

warn() { printf 'warning: %s\n' "$1" >&2; }

print_help() {
    cat <<'EOF'
gh:label-bootstrap — sync a repo's GitHub labels to the dotfiles SSOT.

Usage:
  bash claude/skills/gh-label-bootstrap/lib/label-bootstrap.sh [options]

Options:
  --repo <owner/repo>  Target repo (default: gh repo view of current repo).
  --dry-run            Print the plan; make no API mutations.
  --prune              DELETE non-SSOT custom labels (default: off).
  -h, --help, help     Show this help.

Full spec: docs/.ssot/gh-labels.md
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --repo)
            [ "${2-}" ] || die "--repo requires a value"
            REPO="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --prune)
            PRUNE=true
            shift
            ;;
        -h | --help | help)
            print_help
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
        esac
    done
}

# Resolve the dotfiles repo root from this script's own (symlink-resolved)
# location so the SSOT feed is found regardless of cwd or the entry-level
# skill symlink (~/.claude*/skills/<name> -> dotfiles/claude/skills/<name>).
# lib -> gh-label-bootstrap -> skills -> claude -> repo root (4 levels up).
resolve_ssot_file() {
    if [ -n "${GH_LABELS_SSOT:-}" ]; then
        printf '%s' "$GH_LABELS_SSOT"
        return 0
    fi
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd -P)"
    printf '%s' "${script_dir}/../../../../docs/.ssot/gh-labels.md"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required. Install it first."
}

resolve_repo() {
    [ -n "$REPO" ] && return 0
    REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
    [ -n "$REPO" ] || die "--repo omitted and 'gh repo view' failed (run inside a GitHub-linked repo or pass --repo)."
}

# gh api wrapper honoring --dry-run. Prints the planned action either way.
# Usage: api_mutate "<plan line>" <gh api args...>
api_mutate() {
    local plan="$1"
    shift
    if $DRY_RUN; then
        printf '[dry-run] %s\n' "$plan"
        return 0
    fi
    if gh api "$@" >/dev/null 2>&1; then
        printf '%s\n' "$plan"
    else
        warn "$plan FAILED (permission / rate-limit / API error) — skipped"
    fi
}

# Membership test against a newline-separated set on stdin-free vars.
in_set() {
    # $1 = needle, $2 = newline-separated haystack
    printf '%s\n' "$2" | grep -Fxq "$1"
}

main() {
    parse_args "$@"
    require_command gh

    local ssot_file
    ssot_file="$(resolve_ssot_file)"
    [ -r "$ssot_file" ] || die "SSOT feed not readable: $ssot_file"

    resolve_repo

    # --- Parse SSOT plain feeds -------------------------------------------
    # 10-label feed:  name|<6hex>|description
    # alias feed:     old|new     (two lowercase words)
    local feed alias_feed
    feed="$(grep -E '^[A-Za-z][A-Za-z0-9]*\|[0-9a-fA-F]{6}\|' "$ssot_file" || true)"
    alias_feed="$(grep -E '^[a-z]+\|[a-z]+$' "$ssot_file" || true)"
    [ -n "$feed" ] || die "no label feed found in $ssot_file"

    # SSOT label names (for keep-set membership).
    local ssot_names
    ssot_names="$(printf '%s\n' "$feed" | cut -d'|' -f1)"

    # Look up SSOT color/description by name.
    ssot_color() { printf '%s\n' "$feed" | awk -F'|' -v n="$1" '$1==n{print $2; exit}'; }
    ssot_desc() { printf '%s\n' "$feed" | awk -F'|' -v n="$1" '$1==n{sub(/^[^|]*\|[^|]*\|/,""); print; exit}'; }

    # --- Fetch existing labels --------------------------------------------
    local existing
    if ! existing="$(gh api "repos/${REPO}/labels?per_page=100" --jq '.[].name' 2>/dev/null)"; then
        warn "could not list labels on ${REPO} (permission?) — treating as empty"
        existing=""
    fi

    local mode=""
    $DRY_RUN && mode=" (dry-run)"
    printf 'Target repo: %s%s\n' "$REPO" "$mode"

    # effective = existing with aliases applied (old removed, new added).
    local effective="$existing"
    local renamed_targets="" # new names that were renamed this run

    # --- 1. Alias renames --------------------------------------------------
    local old new color desc
    while IFS='|' read -r old new; do
        [ -z "$old" ] && continue
        if in_set "$old" "$existing"; then
            color="$(ssot_color "$new")"
            desc="$(ssot_desc "$new")"
            api_mutate "rename label '${old}' -> '${new}' (sync color/desc)" \
                "repos/${REPO}/labels/${old}" -X PATCH \
                -f "new_name=${new}" -f "color=${color}" -f "description=${desc}"
            # Reflect in effective set: drop old, add new.
            effective="$(printf '%s\n' "$effective" | grep -Fxv "$old" || true)"
            in_set "$new" "$effective" || effective="$(printf '%s\n%s' "$effective" "$new")"
            renamed_targets="${renamed_targets}${new}"$'\n'
        fi
    done <<<"$alias_feed"

    # --- 2. SSOT 10 apply --------------------------------------------------
    local name
    while IFS='|' read -r name color desc; do
        [ -z "$name" ] && continue
        if in_set "$name" "$renamed_targets"; then
            continue # already synced by the rename above
        fi
        if in_set "$name" "$effective"; then
            api_mutate "PATCH label '${name}' (color=${color})" \
                "repos/${REPO}/labels/${name}" -X PATCH \
                -f "new_name=${name}" -f "color=${color}" -f "description=${desc}"
        else
            api_mutate "POST label '${name}' (color=${color})" \
                "repos/${REPO}/labels" -X POST \
                -f "name=${name}" -f "color=${color}" -f "description=${desc}"
            effective="$(printf '%s\n%s' "$effective" "$name")"
        fi
    done <<<"$feed"

    # --- 3. Prune (opt-in only) -------------------------------------------
    if ! $PRUNE; then
        printf 'Prune skipped (--prune not set) — no labels deleted.\n'
        return 0
    fi

    # keep = SSOT names ∪ alias new names ∪ allowlist
    local keep alias_targets allow_nl
    alias_targets="$(printf '%s\n' "$alias_feed" | cut -d'|' -f2)"
    allow_nl="$ALLOWLIST"
    keep="$(printf '%s\n%s\n%s\n' "$ssot_names" "$alias_targets" "$allow_nl" | grep -v '^$' | sort -u)"

    local label
    while IFS= read -r label; do
        [ -z "$label" ] && continue
        if in_set "$label" "$keep"; then
            continue
        fi
        api_mutate "DELETE label '${label}' (prune: not in SSOT/alias/allowlist)" \
            "repos/${REPO}/labels/${label}" -X DELETE
    done <<<"$effective"
}

main "$@"
