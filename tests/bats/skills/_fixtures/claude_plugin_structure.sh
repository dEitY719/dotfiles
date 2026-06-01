#!/usr/bin/env bash
# tests/bats/skills/_fixtures/claude_plugin_structure.sh
# Source-of-truth mirror for the structure spec documented in
#   claude/skills/claude-plugin-structure-check/references/structure-spec.md
#   claude/skills/claude-plugin-structure-refactor/references/plan-and-report-templates.md
#
# The two skills are AI-interpreted markdown with no shell entry point;
# these functions are the executable form of their M1-M6 / R1-R5 evaluation
# and the refactor apply logic, so bats can pin the behavior against real
# fixture repos. Keep them in sync with structure-spec.md whenever the spec
# changes.
#
# All functions take an explicit <repo> path — no globals, no network.

# ---- JSON validity helper ------------------------------------------------
_cps_json_ok() {
    # $1 = path to a JSON file. 0 if it exists and parses, 1 otherwise.
    [ -f "$1" ] || return 1
    jq empty "$1" >/dev/null 2>&1
}

# ---- dynamic discovery ---------------------------------------------------
_cps_plugins() {
    # echo plugin basenames, one per line (dirs under plugins/).
    [ -d "$1/plugins" ] || return 0
    for _p in "$1"/plugins/*/; do
        [ -d "$_p" ] || continue
        basename "$_p"
    done
}

_cps_skills() {
    # $1=repo $2=plugin -> skill basenames under plugins/<p>/skills/.
    local _sd="$1/plugins/$2/skills"
    [ -d "$_sd" ] || return 0
    for _s in "$_sd"/*/; do
        [ -d "$_s" ] || continue
        basename "$_s"
    done
}

# ---- mandatory checks (M1-M6) -- echo PASS|FAIL -------------------------
cps_check_M1() { _cps_json_ok "$1/.claude-plugin/marketplace.json" && echo PASS || echo FAIL; }

cps_check_M2() {
    [ "$(_cps_plugins "$1" | grep -c .)" -ge 1 ] && echo PASS || echo FAIL
}

cps_check_M3() {
    # every plugin must carry a valid plugin.json
    local _p _any=0
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        _any=1
        _cps_json_ok "$1/plugins/$_p/.claude-plugin/plugin.json" || {
            echo FAIL
            return
        }
    done <<EOF
$(_cps_plugins "$1")
EOF
    # No plugins → subject absent → N/A (M2 already owns the "0 plugins" FAIL).
    [ "$_any" -eq 1 ] && echo PASS || echo "N/A"
}

cps_check_M4() {
    # every skill must have a SKILL.md with name: and description:
    local _p _s _any=0 _sm
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        while IFS= read -r _s; do
            [ -n "$_s" ] || continue
            _any=1
            _sm="$1/plugins/$_p/skills/$_s/SKILL.md"
            [ -f "$_sm" ] || {
                echo FAIL
                return
            }
            if ! grep -q '^name:' "$_sm" || ! grep -q '^description:' "$_sm"; then
                echo FAIL
                return
            fi
        done <<EOF
$(_cps_skills "$1" "$_p")
EOF
    done <<EOF
$(_cps_plugins "$1")
EOF
    # No skills anywhere → subject absent → N/A, not FAIL (N/A rule).
    [ "$_any" -eq 1 ] && echo PASS || echo "N/A"
}

cps_check_M5() {
    [ -d "$1/docs/skill-guides" ] && [ -d "$1/docs/skill-output" ] && echo PASS || echo FAIL
}

cps_check_M6() { [ -f "$1/README.md" ] && echo PASS || echo FAIL; }

# ---- recommended checks (R1-R5) -- echo PASS|WARN|N/A -------------------
cps_check_R1() {
    # per-skill docs/skill-guides/<skill>.html ; N/A if no skills
    local _p _s _any=0
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        while IFS= read -r _s; do
            [ -n "$_s" ] || continue
            _any=1
            [ -f "$1/docs/skill-guides/$_s.html" ] || {
                echo WARN
                return
            }
        done <<EOF
$(_cps_skills "$1" "$_p")
EOF
    done <<EOF
$(_cps_plugins "$1")
EOF
    [ "$_any" -eq 1 ] && echo PASS || echo "N/A"
}

cps_check_R2() {
    local _p _s _any=0
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        while IFS= read -r _s; do
            [ -n "$_s" ] || continue
            _any=1
            { [ -f "$1/docs/skill-output/$_s-usage.html" ] ||
                [ -f "$1/docs/skill-output/$_s-usage.md" ]; } || {
                echo WARN
                return
            }
        done <<EOF
$(_cps_skills "$1" "$_p")
EOF
    done <<EOF
$(_cps_plugins "$1")
EOF
    [ "$_any" -eq 1 ] && echo PASS || echo "N/A"
}

cps_check_R3() {
    # README "Simple": links into docs/. N/A when README absent (M6 owns that).
    [ -f "$1/README.md" ] || {
        echo "N/A"
        return
    }
    grep -Eq '\]\(\.?/?docs/' "$1/README.md" && echo PASS || echo WARN
}

cps_check_R4() {
    # naming: SKILL.md name: colon-namespace ↔ skill directory hyphen form.
    local _p _s _any=0 _sm _name _expect
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        while IFS= read -r _s; do
            [ -n "$_s" ] || continue
            _sm="$1/plugins/$_p/skills/$_s/SKILL.md"
            [ -f "$_sm" ] || continue
            _any=1
            # strip leading `name:` + surrounding spaces/quotes (single & double)
            _name="$(grep -m1 '^name:' "$_sm" | sed 's/^name:[[:space:]'\''" ]*//;s/[[:space:]'\''" ]*$//')"
            _expect="$(printf '%s' "$_name" | tr ':' '-')"
            [ "$_expect" = "$_s" ] || {
                echo WARN
                return
            }
        done <<EOF
$(_cps_skills "$1" "$_p")
EOF
    done <<EOF
$(_cps_plugins "$1")
EOF
    [ "$_any" -eq 1 ] && echo PASS || echo "N/A"
}

cps_check_R5() {
    # per-skill README links: README must reference BOTH skill-guides/<s>.html
    # AND skill-output/<s>-usage.{html,md} for every skill. Matching is by
    # path-string presence (relative or Pages-absolute both count). N/A when
    # README absent (M6 owns that) or no skills exist.
    [ -f "$1/README.md" ] || {
        echo "N/A"
        return
    }
    local _p _s _any=0
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        while IFS= read -r _s; do
            [ -n "$_s" ] || continue
            _any=1
            grep -qF "skill-guides/$_s.html" "$1/README.md" || {
                echo WARN
                return
            }
            { grep -qF "skill-output/$_s-usage.html" "$1/README.md" ||
                grep -qF "skill-output/$_s-usage.md" "$1/README.md"; } || {
                echo WARN
                return
            }
        done <<EOF
$(_cps_skills "$1" "$_p")
EOF
    done <<EOF
$(_cps_plugins "$1")
EOF
    [ "$_any" -eq 1 ] && echo PASS || echo "N/A"
}

# ---- aggregate verdict ---------------------------------------------------
cps_verdict() {
    # echo FAIL | WARN | PASS for repo $1
    local _r
    for _c in M1 M2 M3 M4 M5 M6; do
        _r="$(cps_check_$_c "$1")"
        [ "$_r" = FAIL ] && {
            echo FAIL
            return
        }
    done
    for _c in R1 R2 R3 R4 R5; do
        _r="$(cps_check_$_c "$1")"
        [ "$_r" = WARN ] && {
            echo WARN
            return
        }
    done
    echo PASS
}

# ---- refactor apply ------------------------------------------------------
# cps_refactor <repo> <scope:mp|op> <mode:dry-run|apply>
# Dry-run is a no-op on disk. Apply creates missing mandatory items, and
# (op scope) recommended placeholder stubs. Idempotent.
cps_refactor() {
    local _repo="$1" _scope="${2:-mp}" _mode="${3:-dry-run}"
    [ "$_mode" = "apply" ] || return 0 # dry-run: touch nothing

    # M5 dirs
    mkdir -p "$_repo/docs/skill-guides" "$_repo/docs/skill-output"
    mkdir -p "$_repo/.claude-plugin"

    # M1 marketplace.json skeleton (only if missing/invalid) — list ALL plugins
    if ! _cps_json_ok "$_repo/.claude-plugin/marketplace.json"; then
        local _p _plugins_json=""
        while IFS= read -r _p; do
            [ -n "$_p" ] || continue
            [ -n "$_plugins_json" ] && _plugins_json="${_plugins_json}, "
            _plugins_json="${_plugins_json}\"./plugins/${_p}\""
        done <<EOF
$(_cps_plugins "$_repo")
EOF
        printf '{ "name": "%s", "plugins": [%s] }\n' \
            "$(basename "$_repo")" "${_plugins_json:-\"./plugins/plugin\"}" \
            >"$_repo/.claude-plugin/marketplace.json"
    fi

    # M3 per-plugin plugin.json skeleton — list ALL skills of each plugin
    local _p _s _skills_json
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        mkdir -p "$_repo/plugins/$_p/.claude-plugin"
        if ! _cps_json_ok "$_repo/plugins/$_p/.claude-plugin/plugin.json"; then
            _skills_json=""
            while IFS= read -r _s; do
                [ -n "$_s" ] || continue
                [ -n "$_skills_json" ] && _skills_json="${_skills_json}, "
                _skills_json="${_skills_json}\"./skills/${_s}\""
            done <<EOF
$(_cps_skills "$_repo" "$_p")
EOF
            printf '{ "name": "%s", "version": "0.0.0", "skills": [%s] }\n' \
                "$_p" "${_skills_json:-\"./skills/skill\"}" \
                >"$_repo/plugins/$_p/.claude-plugin/plugin.json"
        fi
    done <<EOF
$(_cps_plugins "$_repo")
EOF

    # M6 README skeleton (with a docs/ link so R3 also passes)
    [ -f "$_repo/README.md" ] || printf '# %s\n\nSee [docs/](./docs/).\n' \
        "$(basename "$_repo")" >"$_repo/README.md"

    [ "$_scope" = "op" ] || return 0

    # --op: R1/R2 placeholder stubs per skill
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        while IFS= read -r _s; do
            [ -n "$_s" ] || continue
            [ -f "$_repo/docs/skill-guides/$_s.html" ] || printf \
                '<!-- TODO: claude-plugin guide for %s — fill with /devx:visualize -->\n' \
                "$_s" >"$_repo/docs/skill-guides/$_s.html"
            { [ -f "$_repo/docs/skill-output/$_s-usage.html" ] ||
                [ -f "$_repo/docs/skill-output/$_s-usage.md" ]; } || printf \
                '<!-- TODO: %s usage sample — fill with /devx:visualize -->\n' \
                "$_s" >"$_repo/docs/skill-output/$_s-usage.md"
        done <<EOF
$(_cps_skills "$_repo" "$_p")
EOF
    done <<EOF
$(_cps_plugins "$_repo")
EOF

    # --op: R5 README link backfill — append ONLY the missing link(s) per skill
    # so an already-present link is never duplicated (idempotent, per spec).
    # The real skill writes the GUIDE link as a GitHub Pages absolute URL
    # derived from `git remote` (github.com → https://<owner>.github.io/<repo>,
    # GHE → https://<host>/pages/<owner>/<repo>; see plan-and-report-templates.md
    # → "Pages host & URL derivation"). This hermetic fixture has no remote, so
    # it writes the relative fallback form — both satisfy cps_check_R5, which
    # matches by the `skill-guides/<s>.html` substring common to both forms.
    local _has_guide _has_usage
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        while IFS= read -r _s; do
            [ -n "$_s" ] || continue
            _has_guide=0
            _has_usage=0
            grep -qF "skill-guides/$_s.html" "$_repo/README.md" && _has_guide=1
            { grep -qF "skill-output/$_s-usage.html" "$_repo/README.md" ||
                grep -qF "skill-output/$_s-usage.md" "$_repo/README.md"; } && _has_usage=1
            [ "$_has_guide" -eq 1 ] && [ "$_has_usage" -eq 1 ] && continue
            [ "$_has_guide" -eq 0 ] && printf -- '- `%s` guide: [guide](docs/skill-guides/%s.html)\n' \
                "$_s" "$_s" >>"$_repo/README.md"
            [ "$_has_usage" -eq 0 ] && printf -- '- `%s` usage: [usage](docs/skill-output/%s-usage.md)\n' \
                "$_s" "$_s" >>"$_repo/README.md"
        done <<EOF
$(_cps_skills "$_repo" "$_p")
EOF
    done <<EOF
$(_cps_plugins "$_repo")
EOF
}
