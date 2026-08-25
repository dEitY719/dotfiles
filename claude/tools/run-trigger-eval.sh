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
    *) printf 'run-trigger-eval: --arm must be before|after|both, got %s\n' "$ARM" >&2; exit 2 ;;
esac

if [ -n "$DESC_OVERRIDE" ]; then
    if [ "${#SKILLS[@]}" -ne 1 ]; then
        printf 'run-trigger-eval: --description takes exactly one skill.\n' >&2
        exit 2
    fi
    # An overridden description has no "before" counterpart to compare against.
    ARM="after"
fi

if [ -z "$REPO_ROOT" ]; then
    REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
        printf 'run-trigger-eval: not in a git repo; pass --repo <path>.\n' >&2
        exit 2
    }
fi

SKILL_CREATE="${REPO_ROOT}/claude/skills/skill-create"
if [ ! -f "${SKILL_CREATE}/scripts/run_eval.py" ]; then
    printf 'run-trigger-eval: run_eval.py not found under %s\n' "$SKILL_CREATE" >&2
    exit 1
fi

for _s in "${SKILLS[@]}"; do
    if [ ! -f "${REPO_ROOT}/claude/skills/${_s}/SKILL.md" ]; then
        printf 'run-trigger-eval: no SKILL.md for skill %s\n' "$_s" >&2
        exit 1
    fi
    if [ ! -f "${REPO_ROOT}/claude/skills/${_s}/evals/trigger-eval.json" ]; then
        printf 'run-trigger-eval: no evals/trigger-eval.json for skill %s\n' "$_s" >&2
        exit 1
    fi
done

SRC_CONFIG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ ! -r "${SRC_CONFIG}/.credentials.json" ]; then
    printf 'run-trigger-eval: no readable %s/.credentials.json to copy.\n' "$SRC_CONFIG" >&2
    printf '  Set CLAUDE_CONFIG_DIR to the logged-in account config dir.\n' >&2
    exit 1
fi

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
    _rj_skill="$1"
    _rj_arm="$2"
    _rj_desc="$3"
    _rj_out="${OUT_DIR}/${_rj_skill}.${_rj_arm}.json"
    _rj_dir="${SESSION_TMP}/${_rj_skill}.${_rj_arm}"
    _rj_cfg="${_rj_dir}/config"
    _rj_proj="${_rj_dir}/project"

    mkdir -p "$_rj_cfg" "${_rj_proj}/.claude/commands"
    cp "${SRC_CONFIG}/.credentials.json" "${_rj_cfg}/.credentials.json"
    chmod 600 "${_rj_cfg}/.credentials.json"

    (
        cd "$_rj_proj" || exit 1
        CLAUDE_CONFIG_DIR="$_rj_cfg" \
            PYTHONPATH="$SKILL_CREATE" \
            python3 -m scripts.run_eval \
            --eval-set "${REPO_ROOT}/claude/skills/${_rj_skill}/evals/trigger-eval.json" \
            --skill-path "${REPO_ROOT}/claude/skills/${_rj_skill}" \
            --description "$_rj_desc" \
            --model "$MODEL" \
            --runs-per-query "$RUNS" \
            --num-workers 1 \
            --timeout "$QUERY_TIMEOUT"
    ) > "$_rj_out" 2> "${OUT_DIR}/${_rj_skill}.${_rj_arm}.stderr"

    rm -rf "$_rj_dir"

    if ! jq -e '.summary' "$_rj_out" > /dev/null 2>&1; then
        printf '  %-34s %-7s ERROR (see %s.%s.stderr)\n' \
            "$_rj_skill" "$_rj_arm" "$_rj_skill" "$_rj_arm"
        return 1
    fi

    jq -r --arg s "$_rj_skill" --arg a "$_rj_arm" \
        '.summary | [$s, $a, .passed, .total, (100 * .passed / .total)] | @tsv' \
        "$_rj_out" > "${OUT_DIR}/${_rj_skill}.${_rj_arm}.tsv"

    # Split the score by expectation: an all-zero trigger_rate across BOTH
    # classes is the twin-shadowing signature, not a real measurement, and it
    # would otherwise read as a respectable ~50% overall.
    jq -r --arg s "$_rj_skill" --arg a "$_rj_arm" '
        [.results[] | select(.should_trigger)]      as $t |
        [.results[] | select(.should_trigger|not)]  as $f |
        "  \($s | . + (" " * (34 - length))) \($a | . + (" " * (7 - length)))" +
        "\(.summary.passed)/\(.summary.total)   " +
        "recall \([$t[]|select(.pass)]|length)/\($t|length)   " +
        "reject \([$f[]|select(.pass)]|length)/\($f|length)"
    ' "$_rj_out"
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
printf '  %-34s %-7s %-7s %-11s %s\n' "skill" "arm" "score" "recall" "reject"

_throttle() {
    while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do
        wait -n 2> /dev/null || true
    done
}

for skill in "${SKILLS[@]}"; do
    if [ "$ARM" = "before" ] || [ "$ARM" = "both" ]; then
        before_dir="${SESSION_TMP}/before-src-${skill}"
        mkdir -p "$before_dir"
        if git -C "$REPO_ROOT" show "${BEFORE_REF}:claude/skills/${skill}/SKILL.md" \
            > "${before_dir}/SKILL.md" 2> /dev/null; then
            _throttle
            _run_job "$skill" "before" "$(_describe "$before_dir")" &
        else
            printf '  %-34s %-7s SKIP (no SKILL.md at %s)\n' "$skill" "before" "$BEFORE_REF"
        fi
    fi

    if [ "$ARM" = "after" ] || [ "$ARM" = "both" ]; then
        if [ -n "$DESC_OVERRIDE" ]; then
            _throttle
            _run_job "$skill" "after" "$DESC_OVERRIDE" &
        else
            _throttle
            _run_job "$skill" "after" "$(_describe "${REPO_ROOT}/claude/skills/${skill}")" &
        fi
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
