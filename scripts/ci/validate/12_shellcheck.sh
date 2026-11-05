#!/usr/bin/env bash
# skill-check step: Shell scripts pass shellcheck (sh:check)
# Verbatim run: body of harness-skills .github/workflows/skill-check.yml@c982208fbb2c
# (upstream for check logic). Run by scripts/ci.sh with cwd = a clean clone.
set -euo pipefail
# Vendored trees are skipped: the repo is forbidden to edit them, so a
# finding there has no remedy it can apply — fix it at the SSOT instead.
#
# Neither half of discovery runs through `mapfile -t x < <(...)`: a
# process substitution's exit status is invisible to `set -e`, so a
# failed `git ls-files` — a malformed pathspec being the realistic
# trigger — left an empty array, printed "no shell scripts to check"
# and exited 0 with the gate off. Both now go through a file, so
# git's and sed's exit statuses are the step's. Same shape, and the
# same reason, as the self-checks step below.
listing=$(mktemp)
trap 'rm -f "$listing"' EXIT
printf '%s\n' "$SHELLCHECK_EXCLUDE_PATHS" | tr ',' '\n' |
    sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d' >"$listing"
skip=()
while IFS= read -r p; do
    # Trailing slashes are stripped so `lib/vendor/` and `lib/vendor`
    # select the same tree. An entry made only of slashes would strip
    # to `:(exclude)` over the repo root and silently disable the gate,
    # so reject it loudly rather than rely on a sanitiser to make a
    # caller's degenerate input disappear.
    p=${p%"${p##*[!/]}"}
    if [ -z "$p" ]; then
        echo "FAIL  shellcheck-exclude-paths: an entry of '/' would exclude the whole repo"
        exit 1
    fi
    skip+=(":(exclude)$p")
done <"$listing"
[ "${#skip[@]}" -eq 0 ] || echo "note  shellcheck skips: ${skip[*]}"
git ls-files -z -- '*.sh' "${skip[@]}" >"$listing"
mapfile -t -d '' scripts <"$listing"
if [ "${#scripts[@]}" -eq 0 ]; then
    echo "ok    no shell scripts to check"
    exit 0
fi
# local-ci: upstream apt-installs shellcheck here; locally a missing binary
# is a failure (unmeasured), never a pass.
command -v shellcheck >/dev/null || {
    echo "FAIL  shellcheck not installed (not measured)"
    exit 1
}
echo "note  $(shellcheck --version | sed -n 's/^version: /shellcheck /p')"
shellcheck --severity=warning "${scripts[@]}"
echo "ok    ${#scripts[@]} shell script(s) clean"
