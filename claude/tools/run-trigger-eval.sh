#!/usr/bin/env bash
# claude/tools/run-trigger-eval.sh
#
# Trigger-accuracy regression harness for SKILL.md `description:` fields
# (issue #1417, verifying the #1411 description diet).
#
# It answers one question per skill: does the SHRUNK description still get the
# skill invoked as often as the ORIGINAL one did? The contract #1417 inherits
# from #1411 is
#
#     after_score >= before_score - 5 percentage points
#
# measured over that skill's `evals/trigger-eval.json` query set.
#
# WHY THIS WRAPPER EXISTS — probe twin-shadowing
#
#   The underlying runner is claude/skills/skill-create/scripts/run_eval.py.
#   It registers the description under test as a uuid-named temp slash command
#   and asks whether `claude -p <query>` calls THAT name. The measurement is
#   only valid while exactly ONE such twin is visible to the probe session. Any
#   second copy of the same skill — installed, left over, or concurrent — can
#   win the call instead, and the probe's own uuid then never appears, scoring
#   a correct trigger as a miss. The failure is silent: it looks exactly like
#   "the description is bad" (#1412).
#
#   Four separate things create a twin. This script suppresses all four:
#
#   1. INSTALLED twin. dotfiles exposes all 71 skills through ~/.claude*/skills/,
#      so the genuine skill under test is on the probe's menu.
#      -> CLAUDE_CONFIG_DIR points at a throwaway dir holding only a copy of
#         .credentials.json. Measured in #1412: 154 exposed slash commands ->
#         trigger_rate 0.0; 50 exposed -> trigger_rate 1.0, nothing else changed.
#
#   2. LEFTOVER twin. A probe file from an earlier run is still in the probe
#      project's .claude/commands/.
#      -> Every job gets a freshly created probe project, removed on exit.
#
#   3. CONCURRENT twins. run_eval's own --num-workers (default 10) writes N
#      uuid-named probes into ONE shared .claude/commands/, so N near-identical
#      twins are visible at once; Claude calls one of them and each worker only
#      recognises its own uuid. Measured during #1417 on one identical
#      sh:check query: --num-workers 3 -> 0/3 FAIL, --num-workers 1 -> 3/3 PASS
#      before b41dae08; re-measured after it, 1/3 FAIL vs 3/3 PASS — softened,
#      still broken, so the pin stays. See "WHAT b41dae08 CHANGED" below.
#      -> run_eval is ALWAYS invoked with --num-workers 1. Parallelism moves up
#         one level instead: --jobs runs several (skill, arm) measurements at
#         once, each in its OWN config dir and probe project, so no two probes
#         ever share a commands dir. Do not "optimise" this back into
#         --num-workers; that silently zeroes the results.
#
#   4. REAL-CHECKOUT twin. Without PYTHONPATH, run_eval only imports when cwd
#      is skill-create/, and then its find_project_root() walks up to
#      ~/dotfiles and writes probe files into the user's own
#      .claude/commands/ — case 2 aimed at the live checkout.
#      -> PYTHONPATH carries the skill-create dir; cwd is the probe project.
#
#   Every temp dir, copied credentials included, is removed via
#   trap ... EXIT INT TERM. The isolation cannot be forgotten, so it cannot
#   fail quietly.
#
# WHAT b41dae08 (#1412) CHANGED — and what it did not
#
#   #1412's fixes have since landed on main: run_eval.py no longer settles the
#   whole query at the first tool block (TriggerDetector inspects every block
#   and settles a negative only at end of stream), and errored runs now leave
#   the trigger-rate denominator. Registry:
#   claude/skills/skill-create/references/local-patches.md
#
#   Both pins below were RE-MEASURED against the fixed runner, because a pin
#   justified by a defect becomes folklore once the defect is gone:
#
#       --num-workers 1   still required.  3 workers -> 1/3 FAIL vs 3/3 serial
#                                          (was 0/3 before the fix)
#       --model sonnet    no longer a correctness requirement.
#                                          opus 3/3 PASS, sonnet 3/3 PASS
#                                          (was opus 0/2 vs sonnet 1/1)
#
# WHY --model DEFAULTS TO sonnet
#
#   The contract above is a DELTA between two descriptions, so the model only
#   has to be held constant across the two arms, not maximised. sonnet is the
#   default purely because it is roughly an order of magnitude cheaper per
#   query at equal diagnostic value. Override with --model when re-measuring
#   against a different tier, but use the same value for both arms or the
#   numbers mean nothing.
#
#   Note on provenance: the figures recorded in
#   docs/guide/learnings/skill-description-trigger-eval.md were taken BEFORE
#   b41dae08. They stay internally valid (both arms, one runner, and the
#   contract is a delta) but are not reproducible against today's run_eval.py,
#   which scores strictly more triggers.
#
# EXIT STATUS — a broken run must never read as a clean one
#
#   0  Every skill that was measured is within contract.
#
#   1  CONTRACT. At least one skill's after-score fell more than the margin
#      below its before-score. This is a real statement about a description.
#      The startup precondition failures (no SKILL.md, no eval set, no
#      readable credentials) also exit 1, but they print
#      `run-trigger-eval: <reason>` on stderr before a single measurement is
#      launched, so the two are never ambiguous in practice.
#
#   2  USAGE / ENVIRONMENT. Bad option, no skill named, bad --arm, or one of
#      the required commands (jq, python3, git, claude) is not on PATH.
#      Nothing was created and nothing was run.
#
#   3  HARNESS FAILURE. The harness itself broke: a measurement job produced
#      no data row, or no job produced one at all. This says NOTHING about
#      any description. It exists because the first version of this script
#      wrote only a header row into summary.tsv when every job errored, and
#      the verdict awk then reported "0 skill(s) below contract" and exited 0
#      — a total failure reading as a pass (agy/codex review, PR #1429).
#
# MANUAL diagnostic. It spends real API budget (one `claude -p` per query per
# run per arm) and needs live credentials, so it is deliberately NOT wired into
# `mise run test`. Run it by hand:
#
#   claude/tools/run-trigger-eval.sh gh-commit
#   claude/tools/run-trigger-eval.sh --arm after --runs 1 sh-check skill-check
#   claude/tools/run-trigger-eval.sh --description "$(cat variant.txt)" devx-restart
#
# The logic below is split into functions behind a BASH_SOURCE guard (the
# tests/test idiom from #1397) so the scheduling, aggregation and exit-status
# paths can be unit-tested without spending API budget:
# tests/bats/skills/run_trigger_eval.bats.
#
# References: #1417 (this harness), #1411 (the diet being verified), #1412
# (the run_eval defects being worked around), #1410 (downstream re-user).

set -u

# --- defaults ---------------------------------------------------------------

# The commit that shrank the descriptions (#1411). Its parent is the "before"
# state; the working tree is "after".
DIET_COMMIT="bd91d5dc"
BEFORE_REF="${DIET_COMMIT}^"

ARM="both"
MODEL="sonnet"
RUNS=3
JOBS=6
QUERY_TIMEOUT=200
OUT_DIR=""
DESC_OVERRIDE=""
REPO_ROOT=""
CONTRACT_MARGIN=5.0

# See "EXIT STATUS" in the header. Named so the difference between "a
# description regressed" and "the harness broke" survives every refactor.
EXIT_CONTRACT=1
EXIT_USAGE=2
EXIT_HARNESS=3

# Commands without which nothing below can work. Checked up front (D5) rather
# than discovered halfway through a run that has already copied credentials.
REQUIRED_CMDS="jq python3 git claude"

# Rows this run produced, in schedule order. The verdict reads ONLY these
# paths. A glob over the out-dir would fold in <skill>.<arm>.tsv files left by
# an EARLIER run that shared the same --out-dir, silently mixing unrelated
# numbers into the contract table. Callers legitimately reuse an out-dir, so
# the fix is to track this run's own outputs, not to refuse a non-empty
# directory (codex review, PR #1429).
JOB_TSVS=()

# Arms that never got as far as a measurement (description extraction failed).
# Jobs that DID launch and then errored are detected after `wait` by their
# missing .tsv, so the two counts add up to "did not complete".
SCHED_FAILURES=0

SKILLS=()

_die() {
    printf 'run-trigger-eval: %s\n' "$1" >&2
    exit "${2:-1}"
}

_usage() {
    cat <<EOF
Usage: run-trigger-eval.sh [options] <skill-name> [<skill-name>...]

  <skill-name>        Directory name under claude/skills/ (e.g. gh-commit).
                      Each must have evals/trigger-eval.json.

  --arm <a>           before | after | both   (default: both)
  --before-ref <ref>  Git ref holding the pre-diet SKILL.md
                      (default: ${BEFORE_REF}, i.e. the #1411 parent).
  --model <id>        Model for \`claude -p\` (default: ${MODEL}). Must be the
                      same for both arms. See the header for why not opus.
  --runs <n>          Runs per query (default: ${RUNS}).
  --jobs <n>          Concurrent (skill, arm) measurements (default: ${JOBS}).
                      Each job is internally SERIAL on purpose — see the
                      twin-shadowing note in the header.
  --timeout <s>       Per-query timeout in seconds (default: ${QUERY_TIMEOUT}).
  --out-dir <dir>     Where to write per-arm JSON + summary.tsv
                      (default: a fresh mktemp -d, path printed). Safe to
                      reuse: only the files THIS run writes are aggregated.
  --description <txt> Override the description under test. Single skill only;
                      forces --arm after. This is how the negative control
                      (trigger phrases deliberately removed) is measured.
  --repo <path>       Repo root (default: git rev-parse --show-toplevel).
  -h, --help          Print this help.

Requires ${REQUIRED_CMDS} on PATH.

Prints per-skill pass/total and, when both arms ran, the delta and a
PASS/FAIL verdict against  after >= before - ${CONTRACT_MARGIN}%p.

Exit status:
  0  every measured skill is within contract
  ${EXIT_CONTRACT}  CONTRACT — a skill fell below the margin. Also used by the startup
     precondition failures, which print 'run-trigger-eval: <reason>' first.
  ${EXIT_USAGE}  USAGE — bad option, no skill named, or a required command is missing.
  ${EXIT_HARNESS}  HARNESS — a measurement did not complete, or none produced a data
     row. Says nothing about any description; the run itself broke.
EOF
}

# --- preflight --------------------------------------------------------------

# Fail fast, and BEFORE any temp dir or credential copy exists, so a missing
# tool cannot leave a copy of live credentials behind (agy review, PR #1429).
_preflight() {
    local missing="" cmd
    for cmd in $REQUIRED_CMDS; do
        command -v "$cmd" > /dev/null 2>&1 || missing="${missing} ${cmd}"
    done
    [ -z "$missing" ] || _die "missing required command(s):${missing}
  This harness needs ${REQUIRED_CMDS} on PATH." "$EXIT_USAGE"
}

# --- arg parsing ------------------------------------------------------------

_parse_args() {
    SKILLS=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --arm) ARM="${2:-}"; shift 2 ;;
            --before-ref) BEFORE_REF="${2:-}"; shift 2 ;;
            --model) MODEL="${2:-}"; shift 2 ;;
            --runs) RUNS="${2:-}"; shift 2 ;;
            --jobs) JOBS="${2:-}"; shift 2 ;;
            --timeout) QUERY_TIMEOUT="${2:-}"; shift 2 ;;
            --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
            --description) DESC_OVERRIDE="${2:-}"; shift 2 ;;
            --repo) REPO_ROOT="${2:-}"; shift 2 ;;
            -h | --help) _usage; exit 0 ;;
            -*) printf 'run-trigger-eval: unknown option: %s\n' "$1" >&2; _usage >&2; exit "$EXIT_USAGE" ;;
            *) SKILLS+=("$1"); shift ;;
        esac
    done

    if [ "${#SKILLS[@]}" -eq 0 ]; then
        printf 'run-trigger-eval: no skill named.\n' >&2
        _usage >&2
        exit "$EXIT_USAGE"
    fi

    case "$ARM" in
        before | after | both) ;;
        *) _die "--arm must be before|after|both, got ${ARM}" "$EXIT_USAGE" ;;
    esac

    if [ -n "$DESC_OVERRIDE" ]; then
        [ "${#SKILLS[@]}" -eq 1 ] || _die "--description takes exactly one skill." "$EXIT_USAGE"
        # An overridden description has no "before" counterpart to compare against.
        ARM="after"
    fi
}

# --- paths ------------------------------------------------------------------

_resolve_paths() {
    if [ -z "$REPO_ROOT" ]; then
        REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
            || _die "not in a git repo; pass --repo <path>." "$EXIT_USAGE"
    fi

    # The two facts this harness shares with the pytest guard and with #1410's
    # marketplace split: where skills live, and where a skill keeps its query set.
    SKILLS_SRC="${REPO_ROOT}/claude/skills"
    EVAL_SET_REL="evals/trigger-eval.json"

    SKILL_CREATE="${SKILLS_SRC}/skill-create"
    [ -f "${SKILL_CREATE}/scripts/run_eval.py" ] \
        || _die "run_eval.py not found under ${SKILL_CREATE}"

    local _s
    for _s in "${SKILLS[@]}"; do
        [ -f "${SKILLS_SRC}/${_s}/SKILL.md" ] || _die "no SKILL.md for skill ${_s}"
        [ -f "${SKILLS_SRC}/${_s}/${EVAL_SET_REL}" ] || _die "no ${EVAL_SET_REL} for skill ${_s}"
    done

    SRC_CONFIG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    [ -r "${SRC_CONFIG}/.credentials.json" ] || _die "no readable ${SRC_CONFIG}/.credentials.json to copy.
  Set CLAUDE_CONFIG_DIR to the logged-in account config dir."
}

# --- workspace --------------------------------------------------------------

_cleanup() {
    # shellcheck disable=SC2317  # reached via trap, not by fallthrough
    rm -rf "$SESSION_TMP"
}

_make_workspace() {
    SESSION_TMP="$(mktemp -d "${TMPDIR:-/tmp}/trigger-eval.XXXXXX")"
    trap _cleanup EXIT INT TERM

    if [ -z "$OUT_DIR" ]; then
        OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/trigger-eval-results.XXXXXX")"
    fi
    mkdir -p "$OUT_DIR"
}

# --- helpers ----------------------------------------------------------------

# Every line of the progress table — header, result, SKIP, ERROR — is rendered
# here, so the column widths exist in one place instead of being copied into
# each printf (and hand-padded inside jq, which has no printf of its own).
_row() {
    local line
    printf -v line '  %-34s %-7s %-7s %-11s %s' "$1" "$2" "${3-}" "${4-}" "${5-}"
    # The padding aligns columns; a short row (SKIP, ERROR) must not trail it.
    printf '%s\n' "${line%"${line##*[![:space:]]}"}"
}

# Extract the description from a SKILL.md using the SAME parser run_eval uses,
# so the "before" and "after" strings cannot drift from what the runner would
# have read itself. $1 = directory containing SKILL.md.
_describe() {
    PYTHONPATH="$SKILL_CREATE" python3 -c '
import sys
from pathlib import Path
from scripts.utils import parse_skill_md
sys.stdout.write(parse_skill_md(Path(sys.argv[1]))[1])
' "$1"
}

# One (skill, arm) measurement, run in the background by the scheduler below.
# $1 = skill, $2 = arm label, $3 = description. Gets a private config dir and
# probe project so no other job's probe is ever visible to it.
_run_job() {
    local skill="$1" arm="$2" desc="$3"
    local out="${OUT_DIR}/${skill}.${arm}.json"
    local dir="${SESSION_TMP}/${skill}.${arm}"
    local cfg="${dir}/config" proj="${dir}/project"
    local stats passed total pct hit_t all_t hit_f all_f

    if ! mkdir -p "$cfg" "${proj}/.claude/commands"; then
        _row "$skill" "$arm" "ERROR (workspace setup failed)"
        return 1
    fi

    # Create the credentials copy ALREADY at 0600. A plain `cp` followed by a
    # separate `chmod 600` leaves a live token readable at the umask default
    # for the window in between (agy review, PR #1429). The umask is scoped to
    # a subshell so it cannot leak into the measurement below.
    #
    # A SIGKILL between this copy and the EXIT trap still strands the file;
    # that gap is inherent to copying credentials at all and is out of scope.
    if ! (umask 077 && cp "${SRC_CONFIG}/.credentials.json" "${cfg}/.credentials.json"); then
        _row "$skill" "$arm" "ERROR (credentials copy failed)"
        return 1
    fi

    (
        cd "$proj" || exit 1
        CLAUDE_CONFIG_DIR="$cfg" \
            PYTHONPATH="$SKILL_CREATE" \
            python3 -m scripts.run_eval \
            --eval-set "${SKILLS_SRC}/${skill}/${EVAL_SET_REL}" \
            --skill-path "${SKILLS_SRC}/${skill}" \
            --description "$desc" \
            --model "$MODEL" \
            --runs-per-query "$RUNS" \
            --num-workers 1 \
            --timeout "$QUERY_TIMEOUT"
    ) > "$out" 2> "${OUT_DIR}/${skill}.${arm}.stderr"

    rm -rf "$dir"

    # One pass over the result, emitting numbers only — the shell formats them.
    # Splitting the score by expectation is the point: an all-zero trigger_rate
    # across BOTH classes is the twin-shadowing signature, not a real
    # measurement, and it would otherwise read as a respectable ~50% overall.
    # A missing .summary/.results makes this jq exit non-zero, which is the
    # ERROR path below — so no separate validity probe is needed.
    stats="$(jq -r '
        [.results[] | select(.should_trigger)]      as $t |
        [.results[] | select(.should_trigger|not)]  as $f |
        [ .summary.passed, .summary.total,
          (100 * .summary.passed / .summary.total),
          ([$t[] | select(.pass)] | length), ($t | length),
          ([$f[] | select(.pass)] | length), ($f | length) ] | @tsv
    ' "$out" 2> /dev/null)" || stats=""

    if [ -z "$stats" ]; then
        _row "$skill" "$arm" "ERROR (see ${skill}.${arm}.stderr)"
        return 1
    fi

    IFS=$'\t' read -r passed total pct hit_t all_t hit_f all_f <<< "$stats"

    printf '%s\t%s\t%s\t%s\t%s\n' "$skill" "$arm" "$passed" "$total" "$pct" \
        > "${OUT_DIR}/${skill}.${arm}.tsv"

    _row "$skill" "$arm" "${passed}/${total}" "${hit_t}/${all_t}" "${hit_f}/${all_f}"
}

# --- schedule ---------------------------------------------------------------

_throttle() {
    while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do
        wait -n 2> /dev/null || true
    done
}

# The only way a measurement is launched, so neither the throttle nor the
# output bookkeeping can be forgotten.
_spawn() {
    local tsv="${OUT_DIR}/${1}.${2}.tsv"
    # Drop any same-named artefact an earlier run left in a reused --out-dir,
    # so "this file exists afterwards" means "this run wrote it" and nothing
    # else. That single fact is what lets the verdict tell a completed job
    # from a failed one without a second bookkeeping channel.
    rm -f "$tsv" "${OUT_DIR}/${1}.${2}.json" "${OUT_DIR}/${1}.${2}.stderr"
    JOB_TSVS+=("$tsv")
    _throttle
    _run_job "$@" &
}

# Resolve one arm's description, then launch its measurement.
#
# The _describe call lives HERE and is never inlined into the _spawn argument
# list. run_eval.py does `description = args.description or original_description`
# and an empty string is falsy in Python, so an EMPTY --description silently
# falls back to the ON-DISK (i.e. "after") SKILL.md: a "before" arm whose
# extraction failed would measure after against after and report a guaranteed
# PASS. An unusable description therefore fails the job outright and never
# reaches a measurement (agy/codex review, PR #1429).
#
# $1 = skill, $2 = arm label, $3 = directory holding the SKILL.md to read.
_schedule_arm() {
    local skill="$1" arm="$2" src="$3" desc
    if ! desc="$(_describe "$src")" || [ -z "$desc" ]; then
        _row "$skill" "$arm" "ERROR (no description extracted)"
        SCHED_FAILURES=$((SCHED_FAILURES + 1))
        return 1
    fi
    _spawn "$skill" "$arm" "$desc"
}

_schedule() {
    local skill before_dir
    for skill in "${SKILLS[@]}"; do
        if [ "$ARM" = "before" ] || [ "$ARM" = "both" ]; then
            before_dir="${SESSION_TMP}/before-src-${skill}"
            mkdir -p "$before_dir"
            if git -C "$REPO_ROOT" show "${BEFORE_REF}:claude/skills/${skill}/SKILL.md" \
                > "${before_dir}/SKILL.md" 2> /dev/null; then
                _schedule_arm "$skill" "before" "$before_dir" || true
            else
                # A genuinely absent "before" state, not a failure: the verdict
                # reports it as INCOMPLETE rather than counting it as broken.
                _row "$skill" "before" "SKIP (no SKILL.md at ${BEFORE_REF})"
            fi
        fi

        if [ "$ARM" = "after" ] || [ "$ARM" = "both" ]; then
            if [ -n "$DESC_OVERRIDE" ]; then
                _spawn "$skill" "after" "$DESC_OVERRIDE"
            else
                _schedule_arm "$skill" "after" "${SKILLS_SRC}/${skill}" || true
            fi
        fi
    done
    wait
}

# --- verdict ----------------------------------------------------------------

# Fold ONLY this run's rows into summary.tsv, render the contract table, and
# return the run's exit status. Kept as its own function so the aggregation and
# exit-status paths are testable without spending API budget
# (tests/bats/skills/run_trigger_eval.bats).
_verdict() {
    local summary="${OUT_DIR}/summary.tsv"
    local failed="$SCHED_FAILURES" rows=0 tsv rc

    printf 'skill\tarm\tpassed\ttotal\tpct\n' > "$summary"
    if [ "${#JOB_TSVS[@]}" -gt 0 ]; then
        for tsv in "${JOB_TSVS[@]}"; do
            if [ -s "$tsv" ]; then
                cat "$tsv" >> "$summary"
                rows=$((rows + 1))
            else
                # Launched but produced no row: the job errored (its ERROR line
                # is already in the progress table above) or was killed.
                failed=$((failed + 1))
            fi
        done
    fi

    printf '\n=== contract: after >= before - %s%%p ===\n' "$CONTRACT_MARGIN"

    if [ "$rows" -eq 0 ]; then
        printf '  HARNESS FAILURE: no measurement produced a data row.\n'
        printf '  Nothing was measured, so this is NOT a contract result.\n'
        printf '  Check %s/<skill>.<arm>.stderr for the cause.\n' "$OUT_DIR"
        return "$EXIT_HARNESS"
    fi

    printf '  %-34s %-8s %-8s %-8s %s\n' "skill" "before" "after" "delta" "verdict"
    awk -F'\t' -v margin="$CONTRACT_MARGIN" '
        NR == 1 { next }
        { pct[$1 "\t" $2] = $5; if (!seen[$1]++) { order[++n] = $1 } }
        END {
            failures = 0
            for (i = 1; i <= n; i++) {
                s = order[i]
                b = ((s "\tbefore") in pct) ? pct[s "\tbefore"] : ""
                a = ((s "\tafter") in pct) ? pct[s "\tafter"] : ""
                if (b == "" || a == "") {
                    printf "  %-34s %-8s %-8s %-8s %s\n", s, \
                        (b == "" ? "-" : sprintf("%.1f", b)), \
                        (a == "" ? "-" : sprintf("%.1f", a)), "-", "INCOMPLETE"
                    continue
                }
                d = a - b
                v = (d >= -margin) ? "PASS" : "FAIL"
                if (v == "FAIL") { failures++ }
                printf "  %-34s %-8.1f %-8.1f %+-8.1f %s\n", s, b, a, d, v
            }
            printf "\n  %d skill(s) below contract.\n", failures
            exit (failures > 0)
        }
    ' "$summary"
    rc=$?

    if [ "$failed" -gt 0 ]; then
        printf '\n  HARNESS FAILURE: %d measurement(s) did not complete, so the\n' "$failed"
        printf '  table above is partial and its verdict is not conclusive.\n'
        printf '  Check %s/<skill>.<arm>.stderr for the cause.\n' "$OUT_DIR"
        return "$EXIT_HARNESS"
    fi

    # awk exits 1 exactly when a skill is below contract, which is EXIT_CONTRACT.
    return "$rc"
}

# --- main -------------------------------------------------------------------

main() {
    _parse_args "$@"
    _preflight
    _resolve_paths
    _make_workspace

    printf '=== SKILL.md description trigger eval (#1417) ===\n'
    printf 'repo        : %s\n' "$REPO_ROOT"
    printf 'arm(s)      : %s\n' "$ARM"
    printf 'before ref  : %s\n' "$BEFORE_REF"
    printf 'model       : %s   runs/query: %s   concurrent jobs: %s\n' "$MODEL" "$RUNS" "$JOBS"
    printf 'workspace   : %s  (removed on exit)\n' "$SESSION_TMP"
    printf 'results     : %s\n' "$OUT_DIR"
    printf '\n'
    _row "skill" "arm" "score" "recall" "reject"

    _schedule

    local rc=0
    _verdict || rc=$?

    printf '\nPer-query detail: %s/<skill>.<arm>.json\n' "$OUT_DIR"
    return "$rc"
}

# Sourced (tests reuse _schedule_arm / _spawn / _verdict) → define only.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
    exit $?
fi
