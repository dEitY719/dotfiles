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
#   second copy of the same skill — installed, left over, or concurrent — wins
#   the call instead, and run_eval.py:143-151 returns on that first Skill block
#   and scores a correct trigger as a miss. The failure is silent: it looks
#   exactly like "the description is bad" (#1412).
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
#      sh:check query: --num-workers 3 -> 0/3 FAIL, --num-workers 1 -> 3/3 PASS.
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
# WHY --model DEFAULTS TO sonnet
#
#   run_eval.py decides from the FIRST content_block_start of type tool_use:
#   anything that is not Skill or Read returns False immediately
#   (run_eval.py:135-143). That makes detection model-dependent. Measured on
#   one identical sh:check query during #1417:
#
#       --model opus     0/2  FAIL   (the Skill call happens, but the stream
#                                     shape defeats the first-block detector)
#       --model sonnet   1/1  PASS
#
#   The contract above is a DELTA between two descriptions, so the model only
#   has to be held constant across the two arms, not maximised. sonnet is
#   pinned because it is the arm-neutral choice the detector can actually read,
#   and it is roughly an order of magnitude cheaper per query. Override with
#   --model when re-measuring against a different tier, but use the same value
#   for both arms or the numbers mean nothing.
#
# MANUAL diagnostic. It spends real API budget (one `claude -p` per query per
# run per arm) and needs live credentials, so it is deliberately NOT wired into
# `mise run test`. Run it by hand:
#
#   claude/tools/run-trigger-eval.sh gh-commit
#   claude/tools/run-trigger-eval.sh --arm after --runs 1 sh-check skill-check
#   claude/tools/run-trigger-eval.sh --description "$(cat variant.txt)" devx-restart
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
                      (default: a fresh mktemp -d, path printed).
  --description <txt> Override the description under test. Single skill only;
                      forces --arm after. This is how the negative control
                      (trigger phrases deliberately removed) is measured.
  --repo <path>       Repo root (default: git rev-parse --show-toplevel).
  -h, --help          Print this help.

Prints per-skill pass/total and, when both arms ran, the delta and a
PASS/FAIL verdict against  after >= before - ${CONTRACT_MARGIN}%p.
Exit status is 1 if any skill is below contract.
EOF
}

# --- arg parsing ------------------------------------------------------------

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
        -*) printf 'run-trigger-eval: unknown option: %s\n' "$1" >&2; _usage >&2; exit 2 ;;
        *) SKILLS+=("$1"); shift ;;
    esac
done

if [ "${#SKILLS[@]}" -eq 0 ]; then
    printf 'run-trigger-eval: no skill named.\n' >&2
    _usage >&2
    exit 2
fi

case "$ARM" in
    before | after | both) ;;
    *) _die "--arm must be before|after|both, got ${ARM}" 2 ;;
esac

if [ -n "$DESC_OVERRIDE" ]; then
    [ "${#SKILLS[@]}" -eq 1 ] || _die "--description takes exactly one skill." 2
    # An overridden description has no "before" counterpart to compare against.
    ARM="after"
fi

if [ -z "$REPO_ROOT" ]; then
    REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
        || _die "not in a git repo; pass --repo <path>." 2
fi

# The two facts this harness shares with the pytest guard and with #1410's
# marketplace split: where skills live, and where a skill keeps its query set.
SKILLS_SRC="${REPO_ROOT}/claude/skills"
EVAL_SET_REL="evals/trigger-eval.json"

SKILL_CREATE="${SKILLS_SRC}/skill-create"
[ -f "${SKILL_CREATE}/scripts/run_eval.py" ] \
    || _die "run_eval.py not found under ${SKILL_CREATE}"

for _s in "${SKILLS[@]}"; do
    [ -f "${SKILLS_SRC}/${_s}/SKILL.md" ] || _die "no SKILL.md for skill ${_s}"
    [ -f "${SKILLS_SRC}/${_s}/${EVAL_SET_REL}" ] || _die "no ${EVAL_SET_REL} for skill ${_s}"
done

SRC_CONFIG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[ -r "${SRC_CONFIG}/.credentials.json" ] || _die "no readable ${SRC_CONFIG}/.credentials.json to copy.
  Set CLAUDE_CONFIG_DIR to the logged-in account config dir."

# --- workspace --------------------------------------------------------------

SESSION_TMP="$(mktemp -d "${TMPDIR:-/tmp}/trigger-eval.XXXXXX")"

_cleanup() {
    # shellcheck disable=SC2317  # reached via trap, not by fallthrough
    rm -rf "$SESSION_TMP"
}
trap _cleanup EXIT INT TERM

if [ -z "$OUT_DIR" ]; then
    OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/trigger-eval-results.XXXXXX")"
fi
mkdir -p "$OUT_DIR"

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

    mkdir -p "$cfg" "${proj}/.claude/commands"
    cp "${SRC_CONFIG}/.credentials.json" "${cfg}/.credentials.json"
    chmod 600 "${cfg}/.credentials.json"

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

printf '=== SKILL.md description trigger eval (#1417) ===\n'
printf 'repo        : %s\n' "$REPO_ROOT"
printf 'arm(s)      : %s\n' "$ARM"
printf 'before ref  : %s\n' "$BEFORE_REF"
printf 'model       : %s   runs/query: %s   concurrent jobs: %s\n' "$MODEL" "$RUNS" "$JOBS"
printf 'workspace   : %s  (removed on exit)\n' "$SESSION_TMP"
printf 'results     : %s\n' "$OUT_DIR"
printf '\n'
_row "skill" "arm" "score" "recall" "reject"

_throttle() {
    while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do
        wait -n 2> /dev/null || true
    done
}

# The only way a measurement is launched, so the throttle cannot be forgotten.
_spawn() {
    _throttle
    _run_job "$@" &
}

for skill in "${SKILLS[@]}"; do
    if [ "$ARM" = "before" ] || [ "$ARM" = "both" ]; then
        before_dir="${SESSION_TMP}/before-src-${skill}"
        mkdir -p "$before_dir"
        if git -C "$REPO_ROOT" show "${BEFORE_REF}:claude/skills/${skill}/SKILL.md" \
            > "${before_dir}/SKILL.md" 2> /dev/null; then
            _spawn "$skill" "before" "$(_describe "$before_dir")"
        else
            _row "$skill" "before" "SKIP (no SKILL.md at ${BEFORE_REF})"
        fi
    fi

    if [ "$ARM" = "after" ] || [ "$ARM" = "both" ]; then
        _spawn "$skill" "after" "${DESC_OVERRIDE:-$(_describe "${SKILLS_SRC}/${skill}")}"
    fi
done
wait

# --- verdict ----------------------------------------------------------------

SUMMARY_TSV="${OUT_DIR}/summary.tsv"
printf 'skill\tarm\tpassed\ttotal\tpct\n' > "$SUMMARY_TSV"
cat "$OUT_DIR"/*.*.tsv >> "$SUMMARY_TSV" 2> /dev/null

printf '\n=== contract: after >= before - %s%%p ===\n' "$CONTRACT_MARGIN"
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
' "$SUMMARY_TSV"
_rc=$?

printf '\nPer-query detail: %s/<skill>.<arm>.json\n' "$OUT_DIR"
exit "$_rc"
