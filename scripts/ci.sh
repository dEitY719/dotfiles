#!/usr/bin/env bash
# scripts/ci.sh — local CI for the dEitY719/* repos (GitHub Actions is billing-locked)
#
# Ported from dEitY719/harness-skills .github/workflows/skill-check.yml at
# c982208fbb2cf33a41a4c7f114b35c38b7db08cd (last commit touching it; harness-skills HEAD 5394118).
# harness-skills' skill-check.yml remains the upstream for check logic: re-port, never fork here.
#
# Usage: ci.sh [--repo <path>] [--only validate|bats] [--post] [--sha <sha>] [--context-prefix local-ci]
#
# Suites, each run in a throwaway `git clone --shared` of <sha> (default HEAD), so
# only committed content is measured, like actions/checkout:
#   validate  scripts/ci/validate/NN_*.sh — one file per skill-check.yml step, its
#             run: body verbatim. Inputs come from the `with:` block of the job in
#             .github/workflows/*.yml whose `uses:` names skill-check.yml; inputs it
#             omits take skill-check.yml's defaults. No caller: plugin-name falls back
#             to .claude-plugin/plugin.json `name`; neither -> suite skipped.
#   bats      `bats -r tests/bats` with dotfiles' vendored bats-core/support/assert
#             (tests/bats/lib), no network. No tests/bats -> suite skipped.
# Every step runs (upstream stops a job at its first failing step); the gate verdict
# is the same. A skipped suite is reported as skipped and never posted as success.
#
# --post: publish one commit status per measured suite on <sha>:
#   GH_HOST=<host> gh api repos/<owner>/<repo>/statuses/<sha> -f state=... -f context=<prefix>/<suite>
# owner/repo/host come from the origin URL (ssh host aliases resolved with `ssh -G`).
# Without --post nothing touches the network; the would-be statuses are printed.
#
# Exit: 0 every measured suite passed (or all skipped), 1 a suite or a post failed,
#       2 usage / setup error.

set -uo pipefail

DOTFILES_ROOT="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
STEPS_DIR="${DOTFILES_ROOT}/scripts/ci/validate"
BATS_LIB="${DOTFILES_ROOT}/tests/bats/lib"

usage() {
    cat <<'EOF'
Usage: ci.sh [--repo <path>] [--only validate|bats] [--post] [--sha <sha>] [--context-prefix local-ci]

  --repo <path>            target repo (default: git toplevel of cwd)
  --only validate|bats     run one suite
  --post                   publish results as GitHub commit statuses (network)
  --sha <sha>              commit to test and post on (default: HEAD of the repo)
  --context-prefix <name>  status context prefix (default: local-ci)
EOF
}

die() {
    printf 'ci: %s\n' "$*" >&2
    exit 2
}

repo="" only="" post=0 sha="" prefix="local-ci"
while [ $# -gt 0 ]; do
    case "$1" in
    --repo) repo=${2-} && shift ;;
    --only) only=${2-} && shift ;;
    --post) post=1 ;;
    --sha) sha=${2-} && shift ;;
    --context-prefix) prefix=${2-} && shift ;;
    -h | --help) usage && exit 0 ;;
    *) usage >&2 && exit 2 ;;
    esac
    shift
done
case "$only" in "" | validate | bats) ;; *) die "--only takes validate or bats (got '$only')" ;; esac
[ -n "$prefix" ] || die "--context-prefix must not be empty"

[ -n "$repo" ] || repo=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repo; pass --repo"
repo=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || die "not a git repo: $repo"
sha=$(git -C "$repo" rev-parse --verify --quiet "${sha:-HEAD}^{commit}") || die "unknown commit: ${sha:-HEAD}"

work=$(mktemp -d "${TMPDIR:-/tmp}/local-ci.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$work"' EXIT
if ! git clone --quiet --shared --no-checkout "$repo" "$work/src" ||
    ! git -C "$work/src" checkout --quiet --detach "$sha"; then
    die "could not check out $sha in a clean clone"
fi
src="$work/src"

printf 'ci: %s @ %s\n' "$repo" "${sha:0:12}"
[ -z "$(git -C "$repo" status --porcelain 2>/dev/null)" ] ||
    printf 'note  %s has uncommitted changes; only the committed %s is tested\n' "$repo" "${sha:0:12}"

# result_<suite> = success | failure | skipped; desc_<suite> = status description
declare -A result desc

# run_step <suite> <label> <cmd...> — run in the clone, one summary line; output only on failure.
run_step() {
    local suite=$1 label=$2 log="$work/step.log"
    shift 2
    if (cd "$src" && "$@") >"$log" 2>&1; then
        printf 'ok    %s: %s\n' "$suite" "$label"
        return 0
    fi
    printf 'FAIL  %s: %s\n' "$suite" "$label"
    sed 's/^/        /' "$log"
    return 1
}

# read_inputs — NUL-separated: source, plugin-name, then the six optional inputs.
read_inputs() (
    cd "$src" || exit 1
    python3 - <<'PY'
import json, pathlib, sys, yaml
DEFAULTS = {"max-skill-lines": 100, "description-budget": 5440,
            "shellcheck-exclude-paths": "lib/vendor/", "allow-emoji-paths": "",
            "consistency-checks": "", "license-exceptions": ""}
src, inputs = "", {}
for wf in sorted(pathlib.Path(".github/workflows").glob("*.y*ml")):
    doc = yaml.safe_load(wf.read_text(encoding="utf-8")) or {}
    for job in (doc.get("jobs") or {}).values():
        if isinstance(job, dict) and "skill-check.yml" in str(job.get("uses", "")):
            src, inputs = str(wf), job.get("with") or {}
            break
    if src:
        break
name = inputs.get("plugin-name", "")
if not src:
    manifest = pathlib.Path(".claude-plugin/plugin.json")
    if manifest.is_file():
        src, name = "fallback: .claude-plugin/plugin.json name", json.loads(manifest.read_text())["name"]
out = [src, str(name)] + [str(inputs.get(k, v)) for k, v in DEFAULTS.items()]
sys.stdout.write("\0".join(out) + "\0")
PY
)

suite_validate() {
    local -a v
    local listing="$work/inputs" step label n=0 bad=()
    read_inputs >"$listing" || {
        printf 'FAIL  validate: could not read skill-check inputs\n'
        result[validate]=failure desc[validate]="could not read skill-check inputs"
        return
    }
    mapfile -t -d '' v <"$listing"
    if [ -z "${v[0]}" ] || [ -z "${v[1]}" ]; then
        printf 'skip  validate: no skill-check.yml caller and no .claude-plugin/plugin.json\n'
        result[validate]=skipped
        return
    fi
    printf 'note  validate inputs from %s (plugin-name=%s)\n' "${v[0]}" "${v[1]}"
    export PLUGIN_NAME="${v[1]}" MAX_SKILL_LINES="${v[2]}" DESCRIPTION_BUDGET="${v[3]}" \
        SHELLCHECK_EXCLUDE_PATHS="${v[4]}" ALLOW_EMOJI_PATHS="${v[5]}" \
        CONSISTENCY_CHECKS="${v[6]}" LICENSE_EXCEPTIONS="${v[7]}"
    for step in "$STEPS_DIR"/[0-9][0-9]_*.sh; do
        label=$(sed -n 's/^# skill-check step: //p' "$step")
        n=$((n + 1))
        run_step validate "$label" bash "$step" || bad+=("$(basename "$step" .sh)")
    done
    if [ "${#bad[@]}" -eq 0 ]; then
        result[validate]=success desc[validate]="$n/$n skill-check steps passed"
    else
        result[validate]=failure desc[validate]="${#bad[@]}/$n steps failed: ${bad[*]}"
    fi
}

suite_bats() {
    if [ ! -d "$src/tests/bats" ]; then
        printf 'skip  bats: no tests/bats\n'
        result[bats]=skipped
        return
    fi
    local lib
    for lib in bats-core/bin/bats bats-support/load.bash bats-assert/load.bash; do
        [ -e "$BATS_LIB/$lib" ] && continue
        printf 'FAIL  bats: dotfiles vendored lib missing: %s (git submodule update --init)\n' "$BATS_LIB/$lib"
        result[bats]=failure desc[bats]="vendored bats libs missing (not measured)"
        return
    done
    if BATS_LIB_PATH="$BATS_LIB" run_step bats "bats -r tests/bats" "$BATS_LIB/bats-core/bin/bats" -r tests/bats; then
        result[bats]=success desc[bats]="bats -r tests/bats passed"
    else
        result[bats]=failure desc[bats]="bats -r tests/bats failed"
    fi
}

# origin_slug — prints "<host> <owner>/<repo>" from the origin URL.
origin_slug() {
    local url host path h
    url=$(git -C "$repo" remote get-url origin 2>/dev/null) || return 1
    case "$url" in
    *://*) host=${url#*://} && host=${host#*@} && path=${host#*/} && host=${host%%/*} && host=${host%%:*} ;;
    *:*) host=${url%%:*} && host=${host#*@} && path=${url#*:} ;;
    *) return 1 ;;
    esac
    path=${path%.git} && path=${path%/}
    case "$url" in
    *://*) ;;
    *) h=$(ssh -G "$host" 2>/dev/null | sed -n 's/^hostname //p' | head -1) && host=${h:-$host} ;;
    esac
    # GitHub's ssh-over-443 endpoint is not an API host; gh maps it the same way.
    [ "$host" != ssh.github.com ] || host=github.com
    [ -n "$host" ] && [[ "$path" == */* ]] || return 1
    printf '%s %s\n' "$host" "$path"
}

[ "$only" = bats ] || suite_validate
[ "$only" = validate ] || suite_bats

rc=0 measured=0
for s in validate bats; do
    [ -n "${result[$s]-}" ] || continue
    printf 'suite %-8s %s\n' "$s" "${result[$s]}"
    case "${result[$s]}" in failure) rc=1 measured=1 ;; success) measured=1 ;; esac
done
[ "$measured" -eq 1 ] || printf 'note  nothing measured: every selected suite was skipped\n'

slug=$(origin_slug) || slug=""
for s in validate bats; do
    case "${result[$s]-}" in success | failure) ;; *) continue ;; esac
    d=${desc[$s]:0:140}
    if [ "$post" -eq 0 ]; then
        printf 'post  (dry) %s/%s=%s on %s@%s; pass --post to publish\n' \
            "$prefix" "$s" "${result[$s]}" "${slug:+${slug#* }}" "${sha:0:12}"
        continue
    fi
    [ -n "$slug" ] || die "--post: cannot derive host/owner/repo from origin of $repo"
    if GH_HOST="${slug%% *}" gh api --silent "repos/${slug#* }/statuses/$sha" \
        -f state="${result[$s]}" -f context="$prefix/$s" -f description="$d"; then
        printf 'post  %s/%s=%s on %s@%s\n' "$prefix" "$s" "${result[$s]}" "${slug#* }" "${sha:0:12}"
    else
        printf 'FAIL  post %s/%s to %s\n' "$prefix" "$s" "${slug#* }"
        rc=1
    fi
done
exit "$rc"
