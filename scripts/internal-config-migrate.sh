#!/bin/bash

# scripts/internal-config-migrate.sh: seed gitignored *.internal.local siblings (#1968)
#
# PURPOSE: On internal PCs the package-manager configs are deployed from the
# tracked `*.internal` files (symlinks into this repo, or a copy for rpm).
# Their real values will later be swapped for placeholders in git. Run this
# BEFORE pulling that swap: it copies each tracked file's current content to
# its gitignored `<file>.local` sibling, which shell-common/setup.sh then
# prefers (`_internal_src`). Afterwards run ./setup.sh to re-point the links.
#
# SAFETY: dry-run by default; never overwrites an existing sibling; never
# prints file contents; verifies every copy is byte-identical (cmp).
#
# EXIT: 0 on success, 1 when a copy fails verification, 2 on bad usage.

_SCRIPT_PATH=$(cd "$(dirname "$0")" && pwd)
DOTFILES_ROOT="$(cd "$_SCRIPT_PATH/.." && pwd)"
UX_LIB="$DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh"
if [ ! -f "$UX_LIB" ]; then
    echo "CRITICAL ERROR: UX library not found at $UX_LIB. Exiting." >&2
    exit 1
fi
# shellcheck source=/dev/null
. "$UX_LIB"

# Tracked internal-mode configs holding real values. opencode is excluded:
# it is already a template rendered from env/internal.local.sh (#1967).
FILES="apt/sources.list.jammy.internal
bun/bunfig.toml.internal
cargo/config.toml.internal
npm/npmrc.internal
nuget/NuGet.Config.internal
pip/pip.conf.internal
rpm/ds.repo.internal
uv/uv.toml.internal"

usage() {
    ux_header "internal-config-migrate.sh"
    ux_info "Usage: scripts/internal-config-migrate.sh [--apply] [-h|--help]"
    ux_bullet "--dry-run  (default) dry-run: report what would be copied, write nothing"
    ux_bullet "--apply    copy each tracked *.internal to its absent *.internal.local sibling"
    ux_info "Internal PC order (before the placeholder swap lands): git pull -> --apply -> ./setup.sh"
}

apply=0
case "${1:-}" in
    "" | --dry-run) ;;
    --apply) apply=1 ;;
    -h | --help) usage; exit 0 ;;
    *) ux_error "Unknown option: $1"; usage; exit 2 ;;
esac

if [ "$apply" -eq 1 ]; then
    ux_header "Seed *.internal.local siblings (apply)"
else
    ux_header "Seed *.internal.local siblings (dry-run, nothing is written)"
fi

failed=0
while IFS= read -r rel; do
    src="$DOTFILES_ROOT/$rel"
    dst="$src.local"
    if [ ! -f "$src" ]; then
        ux_info "Skipped (tracked file missing): $rel"
    elif [ -e "$dst" ]; then
        if cmp -s "$src" "$dst"; then
            ux_info "Exists, identical: $rel.local"
        else
            ux_info "Exists, kept as-is (differs from tracked file): $rel.local"
        fi
    elif grep -Eq 'example\.invalid' "$src"; then
        # Tracked file already swapped to placeholders: copying would seed
        # fakes. Restore the real values into $rel.local by hand.
        ux_warning "Skipped (tracked file holds placeholders): $rel"
    elif [ "$apply" -eq 0 ]; then
        ux_info "Would copy: $rel -> $rel.local"
    elif cp -p "$src" "$dst" && cmp -s "$src" "$dst"; then
        ux_success "Copied and verified: $rel -> $rel.local"
    else
        ux_error "Copy failed verification: $rel.local"
        failed=1
    fi
done <<EOF
$FILES
EOF

if [ "$failed" -ne 0 ]; then
    exit 1
fi
if [ "$apply" -eq 0 ]; then
    ux_info "Dry-run only. Re-run with --apply to write."
else
    ux_info "Next: run ./setup.sh so the links point at the *.internal.local files."
fi
