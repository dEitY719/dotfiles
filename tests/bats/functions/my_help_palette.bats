#!/usr/bin/env bats
# tests/bats/functions/my_help_palette.bats
# Coverage for the `my-help` fzf command palette (issue #1740, Phases 0-3).
#
# P1-P3  pin NF-4: the non-interactive `my-help` output must stay byte-identical
#        to the 6-bullet usage summary, in bash and zsh.
# P4-P6  cover the slash scope parser (F-4) — the palette switches scope by
#        re-invoking fzf with a new stream, so the parser is the whole feature
#        and is testable without a TTY.
# P7-P11 cover the per-scope candidate streams (F-5/F-6/F-7) and the record
#        contract every scope must honour.
# P12-P15 cover the preview helper (F-3/F-9/NF-2/NF-3): it renders records and
#        never writes a file or runs a candidate's definition.
# P16-P17 cover bash/zsh parity for the streams and the non-TTY fallback.

load '../test_helper'

setup() {
    setup_isolated_home
    export MY_HELP_ALIAS_CACHE_PATH="$TEST_TEMP_HOME/alias-index.tsv"
    PREVIEW="$DOTFILES_ROOT/shell-common/tools/custom/my_help_preview.sh"
}

teardown() {
    teardown_isolated_home
}

TAB=$'\t'

# ---------------------------------------------------------------------------
# P1-P3: NF-4 — the non-interactive default output does not move
# ---------------------------------------------------------------------------

@test "P1: argless my-help without a TTY is byte-identical to the usage summary" {
    run_in_bash '
        my_help_impl > "$HOME/argless.txt"
        _my_help_summary > "$HOME/summary.txt"
        if cmp -s "$HOME/argless.txt" "$HOME/summary.txt"; then echo SAME; else echo DIFF; fi
        wc -l < "$HOME/argless.txt" | tr -d " "
    '
    assert_success
    assert_line --index 0 "SAME"
    assert_line --index 1 "7"
}

@test "P2: the summary wording is pinned verbatim (NF-4 contract)" {
    # Captured from the pre-#1740 tree. Any edit here is a deliberate break of
    # the byte-identity guarantee, not an incidental one. Matched with --partial
    # so the ux_lib glyph prefixes stay out of this file (repo emoji rule).
    run_in_bash 'my_help_impl'
    assert_success
    assert_line --index 0 --partial "Usage: my-help [topic|category|section|--list|--all]"
    assert_line --index 1 --partial "sections"
    assert_line --index 2 --partial "categories: ai | cli | config | development | devops | docs | meta | system"
    assert_line --index 3 --partial "popular: git | docker | claude | uv | fzf"
    assert_line --index 4 --partial "navigation: my-help <topic> [args] / my-help <category>"
    assert_line --index 5 --partial "details: my-help <section>  (example: my-help categories)"
    assert_line --index 6 --partial "search: my-help search  (fzf fuzzy finder over topics + aliases, needs fzf)"
}

@test "P3: -h / --help / help keep the summary even when fzf exists" {
    run_in_bash '
        for flag in -h --help help; do my_help_impl "$flag"; done |
            grep -c "Usage: my-help \\[topic"
    '
    assert_success
    assert_output "3"
}

# ---------------------------------------------------------------------------
# P4-P6: slash scope parser (F-4)
# ---------------------------------------------------------------------------

@test "P4: a slash command yields its scope and the trailing search term" {
    run_in_bash '_my_help_parse_scope "/alias docker"'
    assert_success
    assert_output "alias${TAB}docker"

    run_in_bash '_my_help_parse_scope "/cat git"'
    assert_success
    assert_output "category${TAB}git"
}

@test "P5: every documented alias maps to its scope, with an empty query" {
    run_in_bash '
        for q in /all /topic /t /alias /a /func /f /cat /c; do
            printf "%s=" "$q"
            _my_help_parse_scope "$q"
        done
    '
    assert_success
    assert_line --index 0 "/all=all${TAB}"
    assert_line --index 1 "/topic=topic${TAB}"
    assert_line --index 2 "/t=topic${TAB}"
    assert_line --index 3 "/alias=alias${TAB}"
    assert_line --index 4 "/a=alias${TAB}"
    assert_line --index 5 "/func=func${TAB}"
    assert_line --index 6 "/f=func${TAB}"
    assert_line --index 7 "/cat=category${TAB}"
    assert_line --index 8 "/c=category${TAB}"
}

@test "P6: a plain query and an unknown slash word are not scope switches" {
    run_in_bash '_my_help_parse_scope "gwt"'
    assert_failure
    assert_output ""

    # A location fragment starts with a slash but is not a scope command.
    run_in_bash '_my_help_parse_scope "/usr/local"'
    assert_failure

    run_in_bash '_my_help_parse_scope "/nope docker"'
    assert_failure
}

@test "P6b: zsh parses slash scopes identically (NF-5)" {
    run_in_zsh '_my_help_parse_scope "/alias docker"; _my_help_parse_scope "/t"; _my_help_parse_scope "gwt" || echo NOPARSE'
    assert_success
    assert_line --index 0 "alias${TAB}docker"
    assert_line --index 1 "topic${TAB}"
    assert_line --index 2 "NOPARSE"
}

# ---------------------------------------------------------------------------
# P7-P11: per-scope candidate streams (F-5 / F-6 / F-7)
# ---------------------------------------------------------------------------

_kind_counts='_my_help_search_candidates "$SCOPE" | awk -F"\t" "{k[\$3]++} END{for (i in k) printf \"%s=%d \", i, k[i]}"'

@test "P7: each scope emits only its own kind" {
    run_in_bash "SCOPE=topic; ${_kind_counts}"
    assert_success
    assert_output --regexp '^topic=[0-9]+ $'

    run_in_bash "SCOPE=alias; ${_kind_counts}"
    assert_success
    assert_output --regexp '^alias=[0-9]+ $'

    run_in_bash "SCOPE=func; ${_kind_counts}"
    assert_success
    assert_output --regexp '^func=[0-9]+ $'

    run_in_bash "SCOPE=category; ${_kind_counts}"
    assert_success
    assert_output --regexp '^category=[0-9]+ $'
}

@test "P8: /all emits every kind, and so does the no-argument default" {
    run_in_bash '_my_help_search_candidates all | awk -F"\t" "{k[\$3]++} END{print k[\"topic\"]+0; print k[\"category\"]+0; print k[\"alias\"]+0; print k[\"func\"]+0}"'
    assert_success
    [ "${lines[0]}" -gt 20 ]
    [ "${lines[1]}" -eq 8 ]
    [ "${lines[2]}" -gt 300 ]
    [ "${lines[3]}" -gt 10 ]

    # The pre-#1740 call shape (no argument) must stay equivalent to "all" —
    # tests/bats/functions/my_help_alias_index.bats still calls it that way.
    run_in_bash '
        _my_help_search_candidates > "$HOME/none.tsv"
        _my_help_search_candidates all > "$HOME/all.tsv"
        if cmp -s "$HOME/none.tsv" "$HOME/all.tsv"; then echo SAME; else echo DIFF; fi
    '
    assert_success
    assert_output "SAME"
}

@test "P9: every record in every scope has 5 fields and a known kind" {
    run_in_bash '
        for s in all topic alias func category; do
            _my_help_search_candidates "$s"
        done | awk -F"\t" "
            NF != 5 { bad++ }
            \$3 != \"topic\" && \$3 != \"category\" && \$3 != \"alias\" && \$3 != \"func\" { badkind++ }
            END { print \"fields=\" bad+0; print \"kinds=\" badkind+0 }"
    '
    assert_success
    assert_line --index 0 "fields=0"
    assert_line --index 1 "kinds=0"
}

@test "P10: the function index exposes no private and no *_help names" {
    run_in_bash '_my_help_function_index | cut -f1 | grep -c -e "^_" -e "_help$" -e "-help$" || true'
    assert_success
    assert_output "0"

    # ...and it does resolve real definitions: relpath:line plus a signature.
    run_in_bash '_my_help_function_index | awk -F"\t" "\$1==\"gwt\"{print \$4; print \$5}"'
    assert_success
    assert_line --index 0 --partial "shell-common/functions/git_worktree.sh:"
    assert_line --index 1 "gwt()"
}

@test "P11: category records carry the category description and a topic count" {
    run_in_bash '_my_help_search_candidates category | awk -F"\t" "\$1==\"development\"{print \$2; print \$4}"'
    assert_success
    assert_line --index 0 --partial "Development tools"
    assert_line --index 1 --regexp '^[0-9]+ topics$'
}

# ---------------------------------------------------------------------------
# P12-P15: preview helper (F-3 / F-9 / NF-2 / NF-3)
# ---------------------------------------------------------------------------

# Stage a 4-record fixture, one per kind. The alias record's "definition" is a
# destructive command pointing at a marker file: rendering it must print the
# text and leave the marker alone.
_stage_records() {
    : > "$TEST_TEMP_HOME/marker"
    {
        printf 'evil\tnote here\talias\tfake.sh:1\trm -rf %s/marker\n' "$TEST_TEMP_HOME"
        printf 'git-help\tGit shortcuts\ttopic\t\t\n'
        printf 'development\tDev tools\tcategory\t15 topics\t\n'
        printf 'gwt\tworktree helper\tfunc\tshell-common/functions/git_worktree.sh:1\tgwt()\n'
    } > "$TEST_TEMP_HOME/records.tsv"
}

_preview() {
    run env HOME="$TEST_TEMP_HOME" XDG_CACHE_HOME="$TEST_TEMP_HOME" TERM=dumb \
        DOTFILES_TEST_MODE=1 "$PREVIEW" "$@"
}

@test "P12: an alias record renders its definition without running it" {
    _stage_records
    _preview "$TEST_TEMP_HOME/records.tsv" 0
    assert_success
    assert_output --partial "Alias: evil"
    assert_output --partial "rm -rf ${TEST_TEMP_HOME}/marker"
    assert_output --partial "fake.sh:1"
    # NF-3: the candidate was printed, not executed.
    [ -e "$TEST_TEMP_HOME/marker" ]
}

@test "P13: a func record renders as a function, a topic record via the topic renderer" {
    _stage_records
    _preview "$TEST_TEMP_HOME/records.tsv" 3
    assert_success
    assert_output --partial "Function: gwt"
    assert_output --partial "shell-common/functions/git_worktree.sh:1"

    _preview "$TEST_TEMP_HOME/records.tsv" 1
    assert_success
    assert_output --partial "git-help"

    _preview "$TEST_TEMP_HOME/records.tsv" 2
    assert_success
    assert_output --partial "Development"
}

@test "P14: rendering a record writes no file (NF-3)" {
    _stage_records
    local before after
    before=$(find "$TEST_TEMP_HOME" | LC_ALL=C sort)
    _preview "$TEST_TEMP_HOME/records.tsv" 0
    assert_success
    after=$(find "$TEST_TEMP_HOME" | LC_ALL=C sort)
    [ "$before" = "$after" ]
}

@test "P15: a non-integer index is refused, and ?-help is scope specific (F-8)" {
    _stage_records
    # fzf only ever passes {n}, an integer; anything else is rejected rather
    # than handed to sed (NF-2 defence in depth).
    _preview "$TEST_TEMP_HOME/records.tsv" '1; touch /tmp/pwned'
    assert_success
    assert_output ""

    _preview --keys alias
    assert_success
    assert_output --partial "never runs it"
    assert_output --partial "/topic"
    # The current scope is not offered as a switch to itself.
    refute_output --partial "/alias  /a"

    _preview --keys topic
    assert_success
    assert_output --partial "open the help topic"
    assert_output --partial "/alias  /a"
}

# ---------------------------------------------------------------------------
# P16-P17: bash / zsh parity
# ---------------------------------------------------------------------------

@test "P16: zsh emits the same per-scope kinds as bash, with no stray output" {
    run_in_zsh '_my_help_search_candidates func | awk -F"\t" "{k[\$3]++} END{for (i in k) printf \"%s=%d \", i, k[i]}"'
    assert_success
    assert_output --regexp '^func=[0-9]+ $'

    run_in_zsh '_my_help_search_candidates category | awk -F"\t" "NF!=5{bad++} END{print bad+0}"'
    assert_success
    assert_output "0"
}

@test "P17: zsh argless my-help without a TTY also matches the summary" {
    run_in_zsh '
        my_help_impl > "$HOME/argless.txt"
        _my_help_summary > "$HOME/summary.txt"
        if cmp -s "$HOME/argless.txt" "$HOME/summary.txt"; then echo SAME; else echo DIFF; fi
    '
    assert_success
    assert_output "SAME"
}

@test "P18: _my_help_search without fzf or a TTY still prints the category table" {
    run_in_bash 'PATH=/nonexistent _my_help_search'
    assert_success
    assert_output --partial "Categories"
}

# ---------------------------------------------------------------------------
# P19: the scope-switch loop itself (F-4 runtime path)
# ---------------------------------------------------------------------------
#
# P4-P6 cover _my_help_parse_scope in isolation. This pins the wiring around
# it: that a slash query really does re-invoke fzf, with the new scope's
# stream on stdin and the trailing term carried over as --query. A stub fzf
# records each invocation's stdin and argv; the TTY gate is stubbed out too
# (P18 is what covers the gate).
@test "P19: a slash query re-invokes fzf with the new scope's stream and query" {
    run_in_bash '
        STUB_DIR="$HOME/fzfstub"
        mkdir -p "$STUB_DIR/bin"
        export STUB_DIR
        cat > "$STUB_DIR/bin/fzf" <<STUB
#!/usr/bin/env bash
n=\$(cat "\$STUB_DIR/count" 2>/dev/null || echo 0)
n=\$((n + 1))
printf "%s\n" "\$n" > "\$STUB_DIR/count"
cat > "\$STUB_DIR/stream.\$n"
printf "%s\n" "\$*" > "\$STUB_DIR/args.\$n"
if [ "\$n" = 1 ]; then
    # A scope switch: fzf prints the query and exits 1 (nothing matched).
    printf "/alias docker\n"
    exit 1
fi
# Second round: empty query line, then the first candidate as the selection.
printf "\n"
head -1 "\$STUB_DIR/stream.\$n"
STUB
        chmod +x "$STUB_DIR/bin/fzf"
        PATH="$STUB_DIR/bin:$PATH"
        _my_help_palette_available() { return 0; }

        _my_help_search > "$HOME/palette.out" 2>&1

        echo "rounds=$(cat "$STUB_DIR/count")"
        echo "kinds1=$(awk -F"\t" "{print \$3}" "$STUB_DIR/stream.1" | LC_ALL=C sort -u | tr "\n" ",")"
        echo "kinds2=$(awk -F"\t" "{print \$3}" "$STUB_DIR/stream.2" | LC_ALL=C sort -u | tr "\n" ",")"
        case "$(cat "$STUB_DIR/args.2")" in *--query=docker*) echo "query=carried" ;; *) echo "query=lost" ;; esac
        grep -q "Alias:" "$HOME/palette.out" && echo "render=alias" || echo "render=none"
    '
    assert_success
    assert_line "rounds=2"
    assert_line "kinds1=topic,"
    assert_line "kinds2=alias,"
    assert_line "query=carried"
    assert_line "render=alias"
}
