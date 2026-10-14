#!/bin/bash
# shell-common/tools/custom/gh_pr_review.sh
# gh-pr-review — synchronous PR review delegation to an external AI CLI.
#
# PATH executable since #2195 (~/.local/bin/gh-pr-review via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'gh-pr-review ...'` resolve it. The logic
# stays in functions/gh_pr_review.sh (also a helper library, #2154); this sources it and
# calls _gh_pr_review_main. functions/gh_pr_review.sh keeps the `gh_pr_review` / `gh-pr-review` names as a
# thin wrapper.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1

# shellcheck source=/dev/null
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/gh_pr_review.sh" || exit 1

main() {
    _gh_pr_review_main "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
