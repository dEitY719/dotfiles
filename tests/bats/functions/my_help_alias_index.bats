#!/usr/bin/env bats
# tests/bats/functions/my_help_alias_index.bats
# Coverage for the `my-help search` alias index introduced in issue #1261.
#
# T1-T4  cover _my_help_build_alias_index's record shape: 5 tab-separated
#        fields, the trailing-comment vs file:line description fallback, and
#        the quote/comment splitting that keeps `alias x='cmd #1'` intact.
# T5-T8  cover the 24h cache (build, warm read, corrupt/empty rebuild, TTL
#        expiry) — issue #1261 NF-1 and Error Cases.
# T9-T11 cover the merged candidate stream (F-1/F-2) and the topics-only
#        fallback when the scan yields nothing.
# T12-T13 cover the fzf-missing / non-TTY regression guard (F-3).
# T14-T15 cover zsh parity — my_help.sh is sourced by both shells.

load '../test_helper'

setup() {
    setup_isolated_home
    # Keep every test's index in its own sandbox; XDG_CACHE_HOME already
    # points at TEST_TEMP_HOME, but pinning the path makes the assertions
    # below independent of the default layout.
    export MY_HELP_ALIAS_CACHE_PATH="$TEST_TEMP_HOME/alias-index.tsv"
}

teardown() {
    teardown_isolated_home
}

# Tab literal for assertions — bats' assert_output compares raw strings.
TAB=$'\t'

# ---------------------------------------------------------------------------
# T1-T4: index record shape
# ---------------------------------------------------------------------------

@test "T1: build emits 5 tab-separated fields on every record" {
    run_in_bash '_my_help_build_alias_index | awk -F"\t" "NF!=5{bad++} END{print bad+0}"'
    assert_success
    assert_output "0"
}

@test "T2: build finds a meaningful number of aliases, with no duplicate records" {
    run_in_bash '_my_help_build_alias_index | wc -l'
    assert_success
    [ "$output" -gt 300 ]

    # `sort -u` dedupes whole records. Identical (name, location, definition)
    # triples must never appear twice — but see T2b: the same *name* legitimately
    # may, when two files define it differently.
    run_in_bash '_my_help_build_alias_index | LC_ALL=C sort | uniq -d | wc -l'
    assert_success
    assert_output "0"
}

@test "T2b: a name defined twice with different bodies keeps BOTH definitions" {
    # Regression pin for the PR #1266 review blocker. `llm-help` is
    # `litellm_help` in shell-common/functions/ai_tools_help.sh and
    # `ollama_help` in shell-common/aliases/help_system_aliases.sh. Collapsing
    # them with `sort -u -k1,1` picked an arbitrary winner, so the picker could
    # claim a definition the shell does not actually resolve to. Only the shell
    # knows which file was sourced last, so the index must surface both rather
    # than guess.
    run_in_bash '_my_help_build_alias_index | awk -F"\t" "\$1==\"llm-help\"{print \$5}" | LC_ALL=C sort'
    assert_success
    assert_line --index 0 "litellm_help"
    assert_line --index 1 "ollama_help"

    # Both rows must carry their own distinct location, or the conflict is
    # indistinguishable from a duplicate.
    run_in_bash '_my_help_build_alias_index | awk -F"\t" "\$1==\"llm-help\"{print \$4}" | LC_ALL=C sort -u | wc -l'
    assert_success
    assert_output "2"
}

@test "T3: trailing comment becomes the description; kind field is 'alias'" {
    # shell-common/tools/integrations/apt.sh: alias aar='...'  # Remove unused dependencies
    run_in_bash '_my_help_build_alias_index | grep "^aar'"$TAB"'"'
    assert_success
    assert_output --partial "Remove unused dependencies"
    assert_output --partial "${TAB}alias${TAB}"
    assert_output --partial "sudo apt-get autoremove"
}

@test "T4: comment-less alias falls back to relpath:line as its description" {
    # csm carries no trailing comment, so fields 2 and 4 must both be the location.
    run_in_bash '_my_help_build_alias_index | awk -F"\t" "\$1==\"csm\"{print (\$2==\$4) ? \"same\" : \"differ\"; print \$2}"'
    assert_success
    assert_line --index 0 "same"
    assert_line --index 1 --partial "marketplace.sh:"
}

@test "T4c: dash-form aliases that only re-expose a help topic are dropped" {
    # `agy-help` expands to `agy_help`, which the topic stream already lists
    # with a real description — keeping the alias row would duplicate the entry.
    run_in_bash '_my_help_build_alias_index | grep -c "^agy-help'"$TAB"'" || true'
    assert_success
    assert_output "0"

    # ...but a -help alias pointing at a differently-named function is a
    # genuinely new search target and must survive.
    run_in_bash '_my_help_build_alias_index | awk -F"\t" "\$1==\"doc-help\"{print \$5}"'
    assert_success
    assert_output "show_doc_help"
}

@test "T4d: no alias row shadows a topic row of the same name" {
    # The property that actually matters: the -help dedupe (T4c) must leave no
    # name owned by both a topic row and an alias row, because the two would
    # render differently for the same pick. Names duplicated *within* the alias
    # rows are a separate, legitimate case — see T2b.
    run_in_bash '
        _my_help_search_candidates > "$HOME/cands.tsv"
        awk -F"\t" "\$3==\"topic\"{print \$1}" "$HOME/cands.tsv" | LC_ALL=C sort -u > "$HOME/t.txt"
        awk -F"\t" "\$3==\"alias\"{print \$1}" "$HOME/cands.tsv" | LC_ALL=C sort -u > "$HOME/a.txt"
        LC_ALL=C comm -12 "$HOME/t.txt" "$HOME/a.txt" | wc -l
    '
    assert_success
    assert_output "0"
}

@test "T4b: a '#' inside the quoted body is not mistaken for a comment" {
    # `alias ..='cd ..'` has no comment; `alias aac='sudo apt-get autoclean' # ...`
    # does. Both must keep their full definition in field 5.
    run_in_bash '_my_help_build_alias_index | awk -F"\t" "\$1==\"..\"{print \$5}"'
    assert_success
    assert_output "cd .."
}

# ---------------------------------------------------------------------------
# T5-T8: cache behavior (NF-1 + Error Cases)
# ---------------------------------------------------------------------------

@test "T5: cold call builds the index and persists it to the cache path" {
    run_in_bash '_my_help_alias_index >/dev/null; [ -s "$MY_HELP_ALIAS_CACHE_PATH" ] && wc -l < "$MY_HELP_ALIAS_CACHE_PATH"'
    assert_success
    [ "$output" -gt 300 ]
}

@test "T6: a fresh cache is served verbatim without re-scanning" {
    run_in_bash '
        printf "SENTINEL\tdesc\talias\tloc\tdef\n" > "$MY_HELP_ALIAS_CACHE_PATH"
        _my_help_alias_index
    '
    assert_success
    assert_output "SENTINEL${TAB}desc${TAB}alias${TAB}loc${TAB}def"
}

@test "T7: corrupt or empty cache is rebuilt instead of returned" {
    run_in_bash '
        printf "garbage-without-tabs\n" > "$MY_HELP_ALIAS_CACHE_PATH"
        _my_help_alias_index | wc -l
    '
    assert_success
    [ "$output" -gt 300 ]

    run_in_bash '
        : > "$MY_HELP_ALIAS_CACHE_PATH"
        _my_help_alias_index | wc -l
    '
    assert_success
    [ "$output" -gt 300 ]
}

@test "T8: cache older than MY_HELP_ALIAS_CACHE_MAX_AGE is rebuilt" {
    # POSIX `touch -t CCYYMMDDhhmm` backdates the sentinel well past the 24h
    # TTL, so this exercises the real mtime path rather than a zeroed MAX_AGE.
    #
    # Redirect to a file rather than piping into `head`: on the rebuild path
    # _my_help_alias_index writes ~385 lines, and a reader that exits after
    # line 1 leaves the producer holding a closed pipe — an exit-141 SIGPIPE
    # race that makes this test flaky under a loaded parallel bats run.
    run_in_bash '
        printf "SENTINEL\tdesc\talias\tloc\tdef\n" > "$MY_HELP_ALIAS_CACHE_PATH"
        touch -t 200001010000 "$MY_HELP_ALIAS_CACHE_PATH"
        _my_help_alias_index > "$HOME/rebuilt.tsv"
        grep -c "^SENTINEL" "$HOME/rebuilt.tsv" || true
        wc -l < "$HOME/rebuilt.tsv"
    '
    assert_success
    assert_line --index 0 "0"
    [ "${lines[1]// /}" -gt 300 ]
}

@test "T8b: an unwritable cache directory still yields a usable index" {
    run_in_bash '
        MY_HELP_ALIAS_CACHE_PATH=/proc/nope/idx.tsv
        _my_help_alias_index | wc -l
    '
    assert_success
    [ "$output" -gt 300 ]
}

# ---------------------------------------------------------------------------
# T9-T11: merged candidate stream (F-1 / F-2) + empty-scan fallback
# ---------------------------------------------------------------------------

@test "T9: candidates contain both topic and alias rows" {
    run_in_bash '_my_help_search_candidates | awk -F"\t" "{n[\$3]++} END{print n[\"topic\"]+0; print n[\"alias\"]+0}"'
    assert_success
    [ "${lines[0]}" -gt 20 ]
    [ "${lines[1]}" -gt 300 ]
}

@test "T10: an alias name is findable in the candidate stream (F-1)" {
    run_in_bash '_my_help_search_candidates | grep -c "^csm'"$TAB"'"'
    assert_success
    assert_output "1"
}

@test "T11: an unscannable tree degrades to topics only, without error" {
    run_in_bash '
        DOTFILES_ROOT=/nonexistent
        SHELL_COMMON=/nonexistent/shell-common
        MY_HELP_ALIAS_CACHE_PATH="$HOME/missing.tsv"
        _my_help_search_candidates | awk -F"\t" "{n[\$3]++} END{print n[\"topic\"]+0; print n[\"alias\"]+0}"
    '
    assert_success
    [ "${lines[0]}" -gt 20 ]
    assert_line --index 1 "0"
}

# ---------------------------------------------------------------------------
# T12-T13: fzf-missing / non-TTY fallback regression guard (F-3)
# ---------------------------------------------------------------------------

@test "T12: _my_help_search without a TTY still prints the category table" {
    run_in_bash '_my_help_search'
    assert_success
    assert_output --partial "Categories"
}

@test "T13: alias records render definition, source, and note on selection" {
    run_in_bash '_my_help_show_alias_entry "$(printf "uvs\tsync deps\talias\tshell-common/tools/integrations/uv.sh:24\tuv sync")"'
    assert_success
    assert_output --partial "Alias: uvs"
    assert_output --partial "uv sync"
    assert_output --partial "shell-common/tools/integrations/uv.sh:24"
    assert_output --partial "sync deps"
}

@test "T13b: a comment-less record does not repeat the location as a note" {
    run_in_bash '_my_help_show_alias_entry "$(printf "csm\tfoo.sh:1\talias\tfoo.sh:1\tclaude_skills_marketplace")"'
    assert_success
    assert_output --partial "claude_skills_marketplace"
    refute_output --partial "note:"
}

# ---------------------------------------------------------------------------
# T14-T15: zsh parity
# ---------------------------------------------------------------------------

@test "T14: zsh builds the same index without stray stdout" {
    run_in_zsh '_my_help_build_alias_index | awk -F"\t" "NF!=5{bad++} END{print bad+0}"'
    assert_success
    assert_output "0"
}

@test "T15: zsh cache write survives noclobber" {
    run_in_zsh '
        setopt noclobber
        export MY_HELP_ALIAS_CACHE_PATH="$HOME/alias-index.tsv"
        _my_help_alias_index >/dev/null
        wc -l < "$MY_HELP_ALIAS_CACHE_PATH"
    '
    assert_success
    [ "${output// /}" -gt 300 ]
}
