#!/bin/bash
# shell-common/tools/custom/gh_issue_review.sh
# gh-issue-review — one GitHub issue reviewed by an external AI CLI (#2381).
#
# PATH executable (~/.local/bin/gh-issue-review via config/symlinks.conf), same
# #2195 pattern as gh_pr_review.sh: it never changes the parent shell's state,
# so AI agents' non-interactive `bash -c 'gh-issue-review ...'` resolve it. The
# logic stays in functions/gh_issue_review.sh (also a helper library); this
# sources it and calls _gh_issue_review_main.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1

# shellcheck source=/dev/null
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/gh_issue_review.sh" || exit 1

main() {
    _gh_issue_review_main "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
