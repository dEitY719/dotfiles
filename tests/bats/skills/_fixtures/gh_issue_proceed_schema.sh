#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_issue_proceed_schema.sh
# Source-of-truth mirror for the strict 8-section schema validator
# documented in
#   claude/skills/gh-issue-proceed/references/protocol-schema.md
#
# The bats suite injects an issue body via FAKE_BODY and asserts the
# validator's pass/fail verdict + categorized output. Keep this in sync
# with protocol-schema.md whenever the schema changes.
#
# Inputs:
#   FAKE_BODY — the GitHub directive issue body (markdown)

# Comma-separated, lowercased alias list for one required section key.
_gp_aliases() {
    case "$1" in
    goal) printf 'goal,목표' ;;
    preconditions) printf 'preconditions,사전 조건,prerequisites' ;;
    execution_protocol) printf 'execution protocol,execution matrix,실행 절차,steps' ;;
    decision_rules) printf 'decision rules,결정 규칙,branching,decision matrix' ;;
    deliverables) printf 'deliverables,산출물,output,outputs' ;;
    done_criteria) printf 'done criteria,종료 조건,acceptance,acceptance criteria' ;;
    out_of_scope) printf 'out of scope,out-of-scope,범위 밖' ;;
    safety) printf 'safety,abort,안전 규칙,safety rules' ;;
    esac
}

# Returns 0 if a heading (H2-H6) matching any alias for KEY exists in
# FAKE_BODY, 1 otherwise.
_gp_has_section() {
    local _aliases
    _aliases=$(_gp_aliases "$1")
    printf '%s\n' "${FAKE_BODY-}" | awk -v al="$_aliases" '
        BEGIN { n = split(al, A, ","); rc = 1 }
        /^##+[[:blank:]]+/ {
            h = tolower($0); sub(/^##+[[:blank:]]+/, "", h)
            for (i = 1; i <= n; i++)
                if (A[i] != "" && index(h, A[i]) > 0) { rc = 0; exit }
        }
        END { exit rc }
    '
}

# Echoes the content lines under the first heading matching KEY (heading
# excluded), stopping at the next heading.
_gp_get_content() {
    local _aliases
    _aliases=$(_gp_aliases "$1")
    printf '%s\n' "${FAKE_BODY-}" | awk -v al="$_aliases" '
        BEGIN { n = split(al, A, ","); cap = 0 }
        /^##+[[:blank:]]+/ {
            if (cap == 1) { exit }
            h = tolower($0); sub(/^##+[[:blank:]]+/, "", h)
            for (i = 1; i <= n; i++)
                if (A[i] != "" && index(h, A[i]) > 0) { cap = 1; next }
            next
        }
        { if (cap == 1) print }
    '
}

# Returns 0 (true) when CONTENT is "empty" per the schema definition:
# under 50 chars after stripping fences, list markers, and outer
# whitespace.
_gp_is_empty() {
    local _c
    _c=$(printf '%s\n' "$1" |
        sed -E 's/`{3,}//g' |
        sed -E 's/^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+//' |
        tr -s '[:space:]' ' ' |
        sed -E 's/^ //; s/ $//')
    [ "${#_c}" -lt 50 ]
}

# Returns 0 when CONTENT has parseable steps: a numbered block
# (^N. or ^### N.) OR a workflow/step+command matrix table.
_gp_protocol_parseable() {
    local _c="$1"
    if printf '%s\n' "$_c" | grep -qE '^[[:space:]]*(#{3,6}[[:space:]]*)?[0-9]+\.'; then
        return 0
    fi
    if printf '%s\n' "$_c" | grep -E '^\|' | grep -iqE '(workflow|step)' &&
        printf '%s\n' "$_c" | grep -E '^\|' | grep -iqE '(command|명령)'; then
        return 0
    fi
    return 1
}

# Main validator. Prints a verdict line and (on failure) categorized
# section lists. Returns 0 when the body satisfies the 8-section schema,
# 1 otherwise.
gh_proceed_validate_schema() {
    local _n="${1:-?}"
    local _missing="" _empty="" _unparseable=""
    local _keys="goal preconditions execution_protocol decision_rules deliverables done_criteria out_of_scope safety"
    local _k _content

    for _k in $_keys; do
        if ! _gp_has_section "$_k"; then
            _missing="$_missing $_k"
            continue
        fi
        _content=$(_gp_get_content "$_k")
        case "$_k" in
        done_criteria)
            if ! printf '%s\n' "$_content" | grep -qE '^[[:space:]]*- \[[ xX]\]'; then
                _empty="$_empty $_k"
            fi
            ;;
        execution_protocol)
            if _gp_is_empty "$_content"; then
                _empty="$_empty $_k"
            elif ! _gp_protocol_parseable "$_content"; then
                _unparseable="$_unparseable execution_protocol"
            fi
            ;;
        *)
            if _gp_is_empty "$_content"; then
                _empty="$_empty $_k"
            fi
            ;;
        esac
    done

    if [ -n "$_missing$_empty$_unparseable" ]; then
        printf 'gh:issue-proceed #%s schema validation failed\n' "$_n"
        [ -n "$_missing" ] && printf '  Missing required sections:%s\n' "$_missing"
        [ -n "$_empty" ] && printf '  Empty required sections:%s\n' "$_empty"
        [ -n "$_unparseable" ] && printf '  Unparseable sections:%s\n' "$_unparseable"
        return 1
    fi

    printf 'gh:issue-proceed #%s schema OK\n' "$_n"
    return 0
}
