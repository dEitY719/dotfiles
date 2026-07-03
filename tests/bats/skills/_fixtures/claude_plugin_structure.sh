#!/usr/bin/env bash
# tests/bats/skills/_fixtures/claude_plugin_structure.sh
# Source-of-truth mirror for the structure spec documented in
#   claude/skills/claude-plugin-structure-check/references/structure-spec.md
#   claude/skills/claude-plugin-structure-refactor/references/plan-and-report-templates.md
#
# The two skills are AI-interpreted markdown with no shell entry point;
# these functions are the executable form of their M1-M10 / R1-R8 evaluation
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

# ---- mode detection + plugin-root abstraction (#914) ---------------------
# A "plugin root" is the dir holding .claude-plugin/plugin.json and skills/.
#   mono   -> each plugins/<p>/   single -> the repo root "." (exactly one).
# Defining M3/M4/R1/R2/R4/R5 over the plugin-root set makes them mode-agnostic
# (Approach C in structure-spec.md): only HOW the root set is computed differs.

_cps_detect_mode() {
    # $1=repo [$2=forced: single|mono] -> echo single|mono (priority order).
    local _repo="$1" _forced="${2:-}" _mf _src
    case "$_forced" in
    single | mono)
        echo "$_forced"
        return
        ;;
    esac
    # marketplace.json plugins[].source — most authoritative unflagged signal.
    _mf="$_repo/.claude-plugin/marketplace.json"
    if _cps_json_ok "$_mf"; then
        _src="$(jq -r '.plugins[]? | if type=="object" then .source else . end' "$_mf" 2>/dev/null | head -n1)"
        case "$_src" in
        ./ | .) echo single && return ;;
        plugins/* | ./plugins/*) echo mono && return ;;
        esac
    fi
    # filesystem fallback.
    if [ -d "$_repo/plugins" ] && [ -n "$(_cps_plugins "$_repo")" ]; then
        echo mono
        return
    fi
    [ -f "$_repo/.claude-plugin/plugin.json" ] && {
        echo single
        return
    }
    echo mono # still ambiguous -> default (header marks "추정")
}

_cps_plugin_roots() {
    # $1=repo $2=mode -> plugin-root paths RELATIVE to repo, one per line.
    #   single: "." iff the root manifest exists (so a missing manifest yields
    #           0 roots -> M3/M4 N/A, with M2 owning the single FAIL, mirroring
    #           the mono "0 plugins" rule). mono: plugins/<p> per dir.
    local _repo="$1" _mode="$2" _p
    if [ "$_mode" = single ]; then
        [ -f "$_repo/.claude-plugin/plugin.json" ] && echo "."
        return
    fi
    [ -d "$_repo/plugins" ] || return 0
    for _p in "$_repo"/plugins/*/; do
        [ -d "$_p" ] || continue
        echo "plugins/$(basename "$_p")"
    done
}

_cps_skills_in_root() {
    # $1=repo $2=root(relative) -> skill basenames under <root>/skills/.
    local _sd="$1/$2/skills"
    [ -d "$_sd" ] || return 0
    for _s in "$_sd"/*/; do
        [ -d "$_s" ] || continue
        basename "$_s"
    done
}

# ---- mandatory checks (M1-M10) -- echo PASS|FAIL|N/A ---------------------
cps_check_M1() { _cps_json_ok "$1/.claude-plugin/marketplace.json" && echo PASS || echo FAIL; }

cps_check_M2() {
    # ≥1 plugin root. mono: plugins/<p>/ dirs; single: root manifest exists.
    local _mode
    _mode="$(_cps_detect_mode "$1" "${2:-}")"
    [ "$(_cps_plugin_roots "$1" "$_mode" | grep -c .)" -ge 1 ] && echo PASS || echo FAIL
}

cps_check_M3() {
    # every plugin root must carry a valid plugin.json
    local _mode _root _any=0
    _mode="$(_cps_detect_mode "$1" "${2:-}")"
    while IFS= read -r _root; do
        [ -n "$_root" ] || continue
        _any=1
        _cps_json_ok "$1/$_root/.claude-plugin/plugin.json" || {
            echo FAIL
            return
        }
    done <<EOF
$(_cps_plugin_roots "$1" "$_mode")
EOF
    # No plugin roots → subject absent → N/A (M2 already owns the FAIL).
    [ "$_any" -eq 1 ] && echo PASS || echo "N/A"
}

cps_check_M4() {
    # every skill must have a SKILL.md with name: and description:
    local _mode _root _s _any=0 _sm
    _mode="$(_cps_detect_mode "$1" "${2:-}")"
    while IFS= read -r _root; do
        [ -n "$_root" ] || continue
        while IFS= read -r _s; do
            [ -n "$_s" ] || continue
            _any=1
            _sm="$1/$_root/skills/$_s/SKILL.md"
            [ -f "$_sm" ] || {
                echo FAIL
                return
            }
            if ! grep -q '^name:' "$_sm" || ! grep -q '^description:' "$_sm"; then
                echo FAIL
                return
            fi
        done <<EOF
$(_cps_skills_in_root "$1" "$_root")
EOF
    done <<EOF
$(_cps_plugin_roots "$1" "$_mode")
EOF
    # No skills anywhere → subject absent → N/A, not FAIL (N/A rule).
    [ "$_any" -eq 1 ] && echo PASS || echo "N/A"
}

cps_check_M5() {
    [ -d "$1/docs/skill-guides" ] && [ -d "$1/docs/skill-output" ] && echo PASS || echo FAIL
}

cps_check_M6() { [ -f "$1/README.md" ] && echo PASS || echo FAIL; }

# ---- M7-M9: marketplace.json plugins[].source integrity (#1084) ----------
# Root cause (claude-plugin-jira#61): Claude Code 2.1.198 does NOT inherit a
# marketplace top-level `source` at install time — each plugins[] element must
# carry its own source, or /plugin install fails. structure-check PASS up to
# M6 did not catch this, which misled diagnosis (#63). M7-M9 close that gap.

cps_check_M7() {
    # Each plugins[] element must resolve to a source. A bare STRING element IS
    # the source (shorthand); an OBJECT element MUST have its own .source key.
    # FAIL when any object element lacks source (the #61 shape). N/A when the
    # marketplace is unreadable (M1 owns that) or lists 0 plugins (M2 owns it).
    local _mf="$1/.claude-plugin/marketplace.json" _n _bad
    _cps_json_ok "$_mf" || {
        echo "N/A"
        return
    }
    _n="$(jq '(.plugins // []) | length' "$_mf" 2>/dev/null || echo 0)"
    [ "${_n:-0}" -ge 1 ] || {
        echo "N/A"
        return
    }
    _bad="$(jq '[(.plugins // [])[] | select(type=="object") | select(has("source")|not)] | length' "$_mf" 2>/dev/null || echo 1)"
    [ "${_bad:-1}" -eq 0 ] && echo PASS || echo FAIL
}

cps_check_M8() {
    # Shape validity of each resolvable source (mono/single common):
    #   local path : "." | "./" | "plugins/*" | "./plugins/*"
    #   git URL    : object { "source":"url", "url":"<non-empty>" }
    # Only an object *missing* the source key is skipped (M7 owns that) — an
    # explicit null source, or a null plugin element, is collected and FAILs
    # here (a malformed source is not a free pass; PR #1085 gemini review).
    # N/A when marketplace unreadable or 0 plugins.
    local _mf="$1/.claude-plugin/marketplace.json" _n _bad
    _cps_json_ok "$_mf" || {
        echo "N/A"
        return
    }
    _n="$(jq '(.plugins // []) | length' "$_mf" 2>/dev/null || echo 0)"
    [ "${_n:-0}" -ge 1 ] || {
        echo "N/A"
        return
    }
    _bad="$(jq '
      [ (.plugins // [])[]
        | ( if type=="object" then . else { "source": . } end ) as $e
        | ($e.source) as $s
        | select( if type=="object" then has("source") else true end )
        | select(
            ( ($s|type=="string") and
              ( $s=="." or $s=="./" or ($s|startswith("plugins/")) or ($s|startswith("./plugins/")) ) )
            or
            ( $s=="url" and (($e.url // "")|type=="string") and (($e.url // "")|length>0) )
          | not )
      ] | length' "$_mf" 2>/dev/null || echo 1)"
    [ "${_bad:-1}" -eq 0 ] && echo PASS || echo FAIL
}

cps_check_M9() {
    # mono only: each declared LOCAL mono plugin path must exist on disk
    #   ./plugins/<name> (or plugins/<name>) → <repo>/plugins/<name>/ present.
    # single mode → N/A (no plugins/ layout). Remote (url-type) sources are
    # skipped — nothing local to verify (avoids the #63-style false FAIL). N/A
    # when the marketplace is unreadable or declares no local mono path.
    local _repo="$1" _mode _mf="$1/.claude-plugin/marketplace.json" _paths _p _any=0
    _mode="$(_cps_detect_mode "$1" "${2:-}")"
    [ "$_mode" = mono ] || {
        echo "N/A"
        return
    }
    _cps_json_ok "$_mf" || {
        echo "N/A"
        return
    }
    _paths="$(jq -r '(.plugins // [])[]
        | ( if type=="object" then .source else . end )
        | select(type=="string")
        | select(test("^\\.?/?plugins/"))' "$_mf" 2>/dev/null)"
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        _any=1
        [ -d "$_repo/plugins/$(basename "$_p")" ] || {
            echo FAIL
            return
        }
    done <<EOF
$_paths
EOF
    [ "$_any" -eq 1 ] && echo PASS || echo "N/A"
}

# Known top-level plugin.json fields per the Claude Code manifest schema
# (2.1.x). SSOT mirror of structure-spec.md → "plugin.json known fields (M10)".
# `skills` is intentionally NOT here — the runtime auto-scans skills/, and a
# skills field makes the manifest fail validation → plugin loads not at all
# (claude-plugin-jira#65, #1084 comment 2026-07-02). Update on CC releases.
_CPS_PLUGIN_JSON_KNOWN_FIELDS='["name","version","description","author","homepage","repository","license","keywords"]'

cps_check_M10() {
    # Every plugin.json top-level key must be in the known-field whitelist.
    # An unknown field (e.g. skills) → FAIL — install succeeds but Claude Code
    # rejects the manifest at load ("Validation errors: skills: Invalid input").
    # Evaluated per plugin root; a missing/invalid plugin.json is M3's concern
    # (skipped here). No plugin root with a valid manifest → N/A.
    local _mode _root _pj _unknown _any=0
    _mode="$(_cps_detect_mode "$1" "${2:-}")"
    while IFS= read -r _root; do
        [ -n "$_root" ] || continue
        _pj="$1/$_root/.claude-plugin/plugin.json"
        _cps_json_ok "$_pj" || continue
        _any=1
        _unknown="$(jq --argjson k "$_CPS_PLUGIN_JSON_KNOWN_FIELDS" \
            '[keys[] | select(. as $x | $k | index($x) | not)] | length' \
            "$_pj" 2>/dev/null || echo 1)"
        [ "${_unknown:-1}" -eq 0 ] || {
            echo FAIL
            return
        }
    done <<EOF
$(_cps_plugin_roots "$1" "$_mode")
EOF
    [ "$_any" -eq 1 ] && echo PASS || echo "N/A"
}

# ---- recommended checks (R1-R5) -- echo PASS|WARN|N/A -------------------
# (R6-R8 added below the R1-R5 block, same contract.)
cps_check_R1() {
    # per-skill docs/skill-guides/<skill>.html ; N/A if no skills. Docs paths
    # are repo-level (mode-independent); only skill discovery is plugin-root.
    local _mode _root _s _any=0
    _mode="$(_cps_detect_mode "$1" "${2:-}")"
    while IFS= read -r _root; do
        [ -n "$_root" ] || continue
        while IFS= read -r _s; do
            [ -n "$_s" ] || continue
            _any=1
            [ -f "$1/docs/skill-guides/$_s.html" ] || {
                echo WARN
                return
            }
        done <<EOF
$(_cps_skills_in_root "$1" "$_root")
EOF
    done <<EOF
$(_cps_plugin_roots "$1" "$_mode")
EOF
    [ "$_any" -eq 1 ] && echo PASS || echo "N/A"
}

cps_check_R2() {
    local _mode _root _s _any=0
    _mode="$(_cps_detect_mode "$1" "${2:-}")"
    while IFS= read -r _root; do
        [ -n "$_root" ] || continue
        while IFS= read -r _s; do
            [ -n "$_s" ] || continue
            _any=1
            { [ -f "$1/docs/skill-output/$_s-usage.html" ] ||
                [ -f "$1/docs/skill-output/$_s-usage.md" ]; } || {
                echo WARN
                return
            }
        done <<EOF
$(_cps_skills_in_root "$1" "$_root")
EOF
    done <<EOF
$(_cps_plugin_roots "$1" "$_mode")
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
    local _mode _root _s _any=0 _sm _name _expect
    _mode="$(_cps_detect_mode "$1" "${2:-}")"
    while IFS= read -r _root; do
        [ -n "$_root" ] || continue
        while IFS= read -r _s; do
            [ -n "$_s" ] || continue
            _sm="$1/$_root/skills/$_s/SKILL.md"
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
$(_cps_skills_in_root "$1" "$_root")
EOF
    done <<EOF
$(_cps_plugin_roots "$1" "$_mode")
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
    local _mode _root _s _any=0
    _mode="$(_cps_detect_mode "$1" "${2:-}")"
    while IFS= read -r _root; do
        [ -n "$_root" ] || continue
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
$(_cps_skills_in_root "$1" "$_root")
EOF
    done <<EOF
$(_cps_plugin_roots "$1" "$_mode")
EOF
    [ "$_any" -eq 1 ] && echo PASS || echo "N/A"
}

# ---- R6-R8: marketplace UI / registration quality (#1084) -- WARN|PASS|N/A
cps_check_R6() {
    # top-level "$schema" declaration in marketplace.json (LSP/IDE validation).
    local _mf="$1/.claude-plugin/marketplace.json"
    _cps_json_ok "$_mf" || {
        echo "N/A"
        return
    }
    [ "$(jq -r 'has("$schema")' "$_mf" 2>/dev/null)" = "true" ] && echo PASS || echo WARN
}

cps_check_R7() {
    # marketplace listing quality: top-level "description" + each OBJECT
    # plugin's "homepage". String-form plugins have nowhere for homepage → only
    # object plugins are checked. WARN when description missing or any object
    # plugin lacks a non-empty homepage.
    local _mf="$1/.claude-plugin/marketplace.json" _missing
    _cps_json_ok "$_mf" || {
        echo "N/A"
        return
    }
    # Guard the type before length so a non-string description/homepage (bool,
    # number) can't crash jq and slip through the `|| echo 0` fallback as a
    # false PASS (PR #1085 gemini review).
    [ "$(jq -r '(has("description") and (.description|type=="string") and (.description|length>0))' "$_mf" 2>/dev/null)" = "true" ] || {
        echo WARN
        return
    }
    _missing="$(jq '[(.plugins // [])[] | select(type=="object") | select((has("homepage")|not) or (.homepage|type!="string") or (.homepage|length==0))] | length' "$_mf" 2>/dev/null || echo 0)"
    [ "${_missing:-0}" -eq 0 ] && echo PASS || echo WARN
}

cps_check_R8() {
    # README /plugin marketplace add hint: prefer the raw marketplace.json URL
    # over a .git clone (raw avoids a local clone — the #61 success pattern).
    # Both are valid, so a .git example only WARNs. N/A when README absent or
    # carries no marketplace-add example (no subject).
    local _rm="$1/README.md" _line
    [ -f "$_rm" ] || {
        echo "N/A"
        return
    }
    grep -q 'plugin marketplace add' "$_rm" || {
        echo "N/A"
        return
    }
    _line="$(grep -m1 'plugin marketplace add' "$_rm")"
    case "$_line" in
    *marketplace.json*) echo PASS ;;
    *.git*) echo WARN ;;
    *) echo PASS ;;
    esac
}

# ---- aggregate verdict ---------------------------------------------------
cps_verdict() {
    # echo FAIL | WARN | PASS for repo $1 ; optional $2 forces single|mono.
    # M5/M6/R3 are mode-independent so the extra arg is harmless for them.
    local _r _mode="${2:-}"
    for _c in M1 M2 M3 M4 M5 M6 M7 M8 M9 M10; do
        _r="$(cps_check_$_c "$1" "$_mode")"
        [ "$_r" = FAIL ] && {
            echo FAIL
            return
        }
    done
    for _c in R1 R2 R3 R4 R5 R6 R7 R8; do
        _r="$(cps_check_$_c "$1" "$_mode")"
        [ "$_r" = WARN ] && {
            echo WARN
            return
        }
    done
    echo PASS
}

# ---- refactor apply ------------------------------------------------------
# cps_refactor <repo> <scope:mp|op> <run:dry-run|apply> [forced:single|mono]
# Dry-run is a no-op on disk. Apply fixes the repo toward the golden layout
# of its DETECTED mode (or the forced target when it equals the detected
# layout); single targets the repo root (no plugins/ dir), mono targets
# plugins/<p>/. Idempotent.
#
# Conversion guard (#915): when the forced target mode differs from the
# detected current layout, that is a single<->mono CONVERSION (relocate the
# whole plugin + rewrite the manifest) — OUT OF SCOPE. The function writes
# NOTHING and returns 3 (a safe no-op, never a partial move).
cps_refactor() {
    local _repo="$1" _scope="${2:-mp}" _run="${3:-dry-run}" _forced="${4:-}"
    [ "$_run" = "apply" ] || return 0 # dry-run: touch nothing

    # Conversion guard — forced target ≠ detected current layout → refuse.
    local _current _target
    _current="$(_cps_detect_mode "$_repo")" # signal-based current layout
    if [ -n "$_forced" ] && [ "$_forced" != "$_current" ]; then
        return 3 # layout conversion required — not performed (safe no-op)
    fi
    _target="${_forced:-$_current}"

    # M5 docs dirs + .claude-plugin (mode-independent).
    mkdir -p "$_repo/docs/skill-guides" "$_repo/docs/skill-output" \
        "$_repo/.claude-plugin"

    if [ "$_target" = single ]; then
        _cps_refactor_single "$_repo" "$_scope"
    else
        _cps_refactor_mono "$_repo" "$_scope"
    fi
    # M7 repair (mandatory, both scopes): inject a source into any existing
    # object plugin that lacks one (the #61 shape). The skeleton path above
    # already writes source-bearing plugins, so this only rewrites a
    # pre-existing marketplace.json.
    _cps_repair_m7 "$_repo" "$_target"
    # M10 repair (mandatory, both scopes): strip unknown fields from every
    # plugin.json (e.g. a schema-violating skills array), keeping a .bak.
    _cps_repair_m10 "$_repo" "$_target"
    return 0 # success (0); the conversion-guard early return above is 3
}

# M10 fix: strip any top-level plugin.json key outside the known-field
# whitelist (the #1084 comment case: a skills array that fails manifest
# validation). A timestamp-free `.bak` copy is left beside each rewritten
# plugin.json so the removal is recoverable. Idempotent: a no-op when every
# manifest is already clean, or when it is missing/invalid (M3 owns that).
_cps_repair_m10() {
    local _repo="$1" _mode="$2" _root _pj _unknown _tmp _status=0
    _mode="$(_cps_detect_mode "$_repo")"
    while IFS= read -r _root; do
        [ -n "$_root" ] || continue
        _pj="$_repo/$_root/.claude-plugin/plugin.json"
        _cps_json_ok "$_pj" || continue
        _unknown="$(jq --argjson k "$_CPS_PLUGIN_JSON_KNOWN_FIELDS" \
            '[keys[] | select(. as $x | $k | index($x) | not)] | length' \
            "$_pj" 2>/dev/null || echo 0)"
        [ "${_unknown:-0}" -gt 0 ] || continue
        cp "$_pj" "$_pj.bak"
        _tmp="$_pj.tmp"
        jq --argjson k "$_CPS_PLUGIN_JSON_KNOWN_FIELDS" \
            'with_entries(select(.key as $x | $k | index($x)))' \
            "$_pj" >"$_tmp" && mv -f "$_tmp" "$_pj" || _status=$?
        rm -f "$_tmp"
    done <<EOF
$(_cps_plugin_roots "$_repo" "$_mode")
EOF
    return "$_status"
}

# M7 fix: for each object plugin missing .source, inject one. Prefer a git URL
# derived from the plugin's own homepage/repository (…​.git) → { source:"url",
# url:<git> }; otherwise fall back to the local path of the detected mode
# (mono → ./plugins/<name>, single → ./). Idempotent: a no-op when every plugin
# already carries a source, or when the marketplace is missing/invalid.
_cps_repair_m7() {
    local _repo="$1" _mode="$2" _mf="$1/.claude-plugin/marketplace.json" _need _tmp _status=0
    _cps_json_ok "$_mf" || return 0
    _need="$(jq '[(.plugins // [])[] | select(type=="object") | select(has("source")|not)] | length' "$_mf" 2>/dev/null || echo 0)"
    [ "${_need:-0}" -gt 0 ] || return 0
    _tmp="$_mf.tmp"
    if [ "$_mode" = single ]; then
        jq '.plugins |= map(if type=="object" and (has("source")|not)
              then . + {"source":"./"} else . end)' \
            "$_mf" >"$_tmp" && mv -f "$_tmp" "$_mf" || _status=$?
    else
        jq '.plugins |= map(if type=="object" and (has("source")|not)
              then ((.homepage // .repository // "") as $u
                    | if ($u|type=="string") and ($u|endswith(".git"))
                      then . + {"source":"url","url":$u}
                      else . + {"source":("./plugins/" + (.name // "plugin"))} end)
              else . end)' \
            "$_mf" >"$_tmp" && mv -f "$_tmp" "$_mf" || _status=$?
    fi
    # Single cleanup point: drop any orphaned temp file on failure (jq/mv),
    # then surface the real status (PR #1085 gemini review).
    rm -f "$_tmp"
    return "$_status"
}

# mono apply: marketplace + per-plugin plugin.json + plugins/<p>/ stubs/links.
_cps_refactor_mono() {
    local _repo="$1" _scope="$2"

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
        printf '{ "$schema": "https://anthropic.com/claude-code/marketplace.schema.json", "name": "%s", "description": "%s plugin marketplace", "plugins": [%s] }\n' \
            "$(basename "$_repo")" "$(basename "$_repo")" "${_plugins_json:-\"./plugins/plugin\"}" \
            >"$_repo/.claude-plugin/marketplace.json"
    fi

    # M3 per-plugin plugin.json skeleton — list ALL skills of each plugin
    # plugin.json carries ONLY known manifest fields — no skills array (M10,
    # #1084): the runtime auto-scans skills/, and a skills field fails manifest
    # validation → plugin never loads. Skills are discovered by dir scan.
    local _p
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        mkdir -p "$_repo/plugins/$_p/.claude-plugin"
        if ! _cps_json_ok "$_repo/plugins/$_p/.claude-plugin/plugin.json"; then
            printf '{ "name": "%s", "version": "0.0.0" }\n' \
                "$_p" >"$_repo/plugins/$_p/.claude-plugin/plugin.json"
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
            _cps_stub_recommended "$_repo" "$_s"
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
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        while IFS= read -r _s; do
            [ -n "$_s" ] || continue
            _cps_backfill_links "$_repo" "$_s"
        done <<EOF
$(_cps_skills "$_repo" "$_p")
EOF
    done <<EOF
$(_cps_plugins "$_repo")
EOF
}

# single apply: the repo root IS the one plugin root — marketplace source
# "./", a ROOT plugin.json, root skills/<s>/. NEVER creates a plugins/ dir.
_cps_refactor_single() {
    local _repo="$1" _scope="$2" _s

    # M1 marketplace.json skeleton with the single source "./".
    if ! _cps_json_ok "$_repo/.claude-plugin/marketplace.json"; then
        printf '{ "$schema": "https://anthropic.com/claude-code/marketplace.schema.json", "name": "%s", "description": "%s plugin marketplace", "plugins": [{ "source": "./" }] }\n' \
            "$(basename "$_repo")" "$(basename "$_repo")" >"$_repo/.claude-plugin/marketplace.json"
    fi

    # M3 ROOT plugin.json skeleton — known manifest fields only, no skills
    # array (M10, #1084): skills are auto-scanned; a skills field fails
    # manifest validation and blocks the plugin from loading.
    if ! _cps_json_ok "$_repo/.claude-plugin/plugin.json"; then
        printf '{ "name": "%s", "version": "0.0.0" }\n' \
            "$(basename "$_repo")" >"$_repo/.claude-plugin/plugin.json"
    fi

    # M6 README skeleton (with a docs/ link so R3 also passes).
    [ -f "$_repo/README.md" ] || printf '# %s\n\nSee [docs/](./docs/).\n' \
        "$(basename "$_repo")" >"$_repo/README.md"

    [ "$_scope" = "op" ] || return 0

    # --op: R1/R2 stubs + R5 link backfill over ROOT skills (paths identical
    # to mono — only the skill-discovery root differs).
    while IFS= read -r _s; do
        [ -n "$_s" ] || continue
        _cps_stub_recommended "$_repo" "$_s"
        _cps_backfill_links "$_repo" "$_s"
    done <<EOF
$(_cps_skills_in_root "$_repo" ".")
EOF
}

# ---- shared --op write helpers (mode-independent — docs paths are repo-level)
_cps_stub_recommended() {
    # $1=repo $2=skill : create R1 guide + R2 usage placeholder stubs if absent.
    local _repo="$1" _s="$2"
    [ -f "$_repo/docs/skill-guides/$_s.html" ] || printf \
        '<!-- TODO: claude-plugin guide for %s — fill with /devx:visualize -->\n' \
        "$_s" >"$_repo/docs/skill-guides/$_s.html"
    { [ -f "$_repo/docs/skill-output/$_s-usage.html" ] ||
        [ -f "$_repo/docs/skill-output/$_s-usage.md" ]; } || printf \
        '<!-- TODO: %s usage sample — fill with /devx:visualize -->\n' \
        "$_s" >"$_repo/docs/skill-output/$_s-usage.md"
}

_cps_backfill_links() {
    # $1=repo $2=skill : append ONLY the missing README link(s) (idempotent).
    local _repo="$1" _s="$2" _has_guide=0 _has_usage=0
    grep -qF "skill-guides/$_s.html" "$_repo/README.md" && _has_guide=1
    { grep -qF "skill-output/$_s-usage.html" "$_repo/README.md" ||
        grep -qF "skill-output/$_s-usage.md" "$_repo/README.md"; } && _has_usage=1
    [ "$_has_guide" -eq 1 ] && [ "$_has_usage" -eq 1 ] && return 0
    [ "$_has_guide" -eq 0 ] && printf -- '- `%s` ([visual guide ↗](docs/skill-guides/%s.html))\n' \
        "$_s" "$_s" >>"$_repo/README.md"
    [ "$_has_usage" -eq 0 ] && printf -- '- `%s` usage: [usage](docs/skill-output/%s-usage.md)\n' \
        "$_s" "$_s" >>"$_repo/README.md"
}
