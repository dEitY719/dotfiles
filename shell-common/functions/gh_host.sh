#!/bin/sh
# shell-common/functions/gh_host.sh
# Resolve the active GitHub host and parse owner/repo from remote URLs.
#
# SSOT for host routing based on `_dotfiles_setup_mode` (issue #703).
# `github.com` is hard-coded in several hooks and scripts; that breaks
# the `internal` PC where the real target is `github.samsungds.net`
# (GHE). Replacing those hard-coded literals with `_gh_resolve_host`
# keeps `external` / `public` / missing-file environments on
# `github.com` (regression-zero) while routing `internal` to GHE.
#
# Host mapping (from issue #703):
#
#   _dotfiles_setup_mode | Host
#   ---------------------+--------------------------
#   internal             | github.samsungds.net
#   external             | github.com
#   public               | github.com
#   "" (file missing)    | github.com
#   <anything else>      | github.com (fail-safe)
#
# When a future GHE domain appears, edit this file only — no other
# script should grow a second copy of the mapping.
#
# PR #704 review (gemini-code-assist) — no interactive guard.
# CLAUDE.md only mandates the guard for files that produce output at
# file scope; this file defines functions and exits, so the guard
# would have blocked non-interactive callers (`. gh_host.sh` inside
# hooks / one-shot scripts) from seeing the functions at all. Keeping
# the body pure-definitions makes the file safe to source from any
# context — interactive, non-interactive, or `bash -c`.

# _gh_resolve_host — print the active GitHub host on stdout.
#
# Reads `_dotfiles_setup_mode` (defined in
# shell-common/tools/integrations/claude.sh). When that function isn't
# in scope (sourcing order glitch or a non-interactive caller that
# hasn't loaded the integrations layer), fall back to `github.com` —
# external/public PCs stay on the public cloud regardless.
_gh_resolve_host() {
    _grh_mode=$(_dotfiles_setup_mode 2>/dev/null || echo "")
    case "$_grh_mode" in
        internal)           echo "github.samsungds.net" ;;
        external|public|"") echo "github.com" ;;
        *)                  echo "github.com" ;;
    esac
    unset _grh_mode
}

# _gh_parse_owner_repo_url — parse `owner/repo` out of a git remote URL.
#
# Accepts the common shapes:
#
#   https://github.com/owner/repo(.git)
#   git@github.com:owner/repo(.git)
#   ssh://git@github.com/owner/repo(.git)
#   git+https://github.com/owner/repo
#
# and the GHE equivalents at `github.samsungds.net`. Returns 0 with
# `owner/repo` on stdout, or 1 with an error message on stderr when
# the URL is empty, points at a non-github host, or doesn't yield a
# clean two-segment slug.
#
# Used by F-4 (gh_pr_review.sh URL parser) and F-5 (kanban setup).
# When a new GHE domain is added, extend BOTH the case-glob and the
# sed regex in this single function.
_gh_parse_owner_repo_url() {
    _gpu_url="${1:-}"
    if [ -z "$_gpu_url" ]; then
        echo "empty remote URL" >&2
        return 1
    fi
    case "$_gpu_url" in
        *github.com*|*github.samsungds.net*) ;;
        *)
            echo "remote URL is not a github remote: $_gpu_url" >&2
            return 1
            ;;
    esac
    _gpu_slug=$(printf '%s' "$_gpu_url" |
        sed -E 's#^.*(github\.com|github\.samsungds\.net)[:/]+##; s#\.git/?$##; s#/$##')
    if ! printf '%s' "$_gpu_slug" | grep -qE '^[^/[:space:]]+/[^/[:space:]]+$'; then
        echo "Could not parse owner/repo from remote URL: $_gpu_url" >&2
        unset _gpu_url _gpu_slug
        return 1
    fi
    printf '%s\n' "$_gpu_slug"
    unset _gpu_url _gpu_slug
}
