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
# P23-P34 cover the #2263 redesign: aligned 2-tone rows, the `/` scope menu,
#        Tab cycling, preview cards, the responsive layout and fzf tiers.

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
    assert_output --partial "alias · evil"
    assert_output --partial "rm -rf ${TEST_TEMP_HOME}/marker"
    assert_output --partial "fake.sh:1"
    # NF-3: the candidate was printed, not executed.
    [ -e "$TEST_TEMP_HOME/marker" ]
}

@test "P13: a func record renders as a function, a topic record via the topic renderer" {
    _stage_records
    _preview "$TEST_TEMP_HOME/records.tsv" 3
    assert_success
    assert_output --partial "func · gwt"
    assert_output --partial "shell-common/functions/git_worktree.sh:1"

    _preview "$TEST_TEMP_HOME/records.tsv" 1
    assert_success
    assert_output --partial "git-help"

    _preview "$TEST_TEMP_HOME/records.tsv" 2
    assert_success
    assert_output --partial "category · development"
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
[ "\$1" = "--version" ] && { echo 0.44.1; exit 0; }
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
        echo "kinds1=$(awk -F"\t" "{print \$4}" "$STUB_DIR/stream.1" | LC_ALL=C sort -u | tr "\n" ",")"
        echo "kinds2=$(awk -F"\t" "{print \$4}" "$STUB_DIR/stream.2" | LC_ALL=C sort -u | tr "\n" ",")"
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

# ---------------------------------------------------------------------------
# P20-P22: PR #1745 review follow-ups
# ---------------------------------------------------------------------------

# The func grep pattern is built *from* the registry, so an entry whose real
# definition the pattern cannot match (e.g. `function name {`, or a rename)
# drops out silently — the palette just shows one row fewer. agy flagged the
# narrow regex; the cheaper guard is a tripwire that fails when an entry stops
# resolving, rather than widening the pattern for forms this repo does not use.
@test "P20: every registry entry resolves to a real definition" {
    # Compare the two counts to each other, not to a literal: a hard-coded
    # size went stale the moment an entry was added (wcp, #1900).
    run_in_bash '
        reg=$(_my_help_func_registry | wc -l)
        res=$(_my_help_function_index | cut -f1 | LC_ALL=C sort -u | wc -l)
        [ "$reg" -gt 0 ] && echo "registry=nonempty" || echo "registry=empty"
        [ "$reg" -eq "$res" ] && echo "resolved=all" || echo "resolved=$res/$reg"
        printf "unresolved=%s\n" "$(comm -13 \
            <(_my_help_function_index | cut -f1 | LC_ALL=C sort -u) \
            <(_my_help_func_registry | cut -f1 | LC_ALL=C sort -u) | tr "\n" " ")"
    '
    assert_success
    assert_line --index 0 "registry=nonempty"
    assert_line --index 1 "resolved=all"
    assert_line --index 2 "unresolved="
}

@test "P21: an unknown MY_HELP_DEFAULT_SCOPE falls back to topic, not an empty palette" {
    # codex review: the value reaches the candidate stream and (before the fix)
    # an fzf action string, so a typo opened a palette with nothing in it.
    run_in_bash '
        STUB_DIR="$HOME/fzfstub"; mkdir -p "$STUB_DIR/bin"; export STUB_DIR
        printf "#!/usr/bin/env bash\ncat > \"\$STUB_DIR/stream\"\nprintf \"\\n\"\nhead -1 \"\$STUB_DIR/stream\"\n" > "$STUB_DIR/bin/fzf"
        chmod +x "$STUB_DIR/bin/fzf"
        PATH="$STUB_DIR/bin:$PATH"
        _my_help_palette_available() { return 0; }
        MY_HELP_DEFAULT_SCOPE=nonsense _my_help_search > /dev/null 2>&1
        awk -F"\t" "{print \$4}" "$STUB_DIR/stream" | LC_ALL=C sort -u | tr "\n" ","
    '
    assert_success
    assert_output "topic,"
}

@test "P22: an fzf failure degrades to the category table instead of printing nothing" {
    # agy BLOCKER: rc=2 (unsupported option, lost tty) was absorbed as if the
    # user had pressed Esc, so the palette exited silently with no fallback.
    run_in_bash '
        STUB_DIR="$HOME/fzfstub"; mkdir -p "$STUB_DIR/bin"; export STUB_DIR
        printf "#!/usr/bin/env bash\ncat > /dev/null\nexit 2\n" > "$STUB_DIR/bin/fzf"
        chmod +x "$STUB_DIR/bin/fzf"
        PATH="$STUB_DIR/bin:$PATH"
        _my_help_palette_available() { return 0; }
        _my_help_search
    '
    assert_success
    assert_output --partial "Categories"

    # Esc (130) stays silent — the fallback must not fire on a user cancel.
    run_in_bash '
        STUB_DIR="$HOME/fzfstub"; mkdir -p "$STUB_DIR/bin"; export STUB_DIR
        printf "#!/usr/bin/env bash\ncat > /dev/null\nexit 130\n" > "$STUB_DIR/bin/fzf"
        chmod +x "$STUB_DIR/bin/fzf"
        PATH="$STUB_DIR/bin:$PATH"
        _my_help_palette_available() { return 0; }
        _my_help_search
    '
    assert_success
    assert_output ""
}

# ---------------------------------------------------------------------------
# P23-P32: palette v2 — rows, scope menu, cards, layout, fzf tiers (#2263)
# ---------------------------------------------------------------------------

# A stub fzf that answers --version with $STUB_VER, records each round's
# stdin/argv, and replays one scripted reply per round from $STUB_DIR/reply.N
# (missing reply = Esc).
_install_stub_fzf() {
    cat > "$STUB_DIR/bin/fzf" <<'STUB'
#!/usr/bin/env bash
[ "$1" = "--version" ] && { echo "${STUB_VER:-0.44.1}"; exit 0; }
n=$(cat "$STUB_DIR/count" 2>/dev/null || echo 0)
n=$((n + 1))
printf "%s\n" "$n" > "$STUB_DIR/count"
cat > "$STUB_DIR/stream.$n"
printf "%s\n" "$@" > "$STUB_DIR/args.$n"
[ -f "$STUB_DIR/reply.$n" ] || exit 130
cat "$STUB_DIR/reply.$n"
exit 0
STUB
    chmod +x "$STUB_DIR/bin/fzf"
}

_stub_prelude='
    STUB_DIR="$HOME/fzfstub"; mkdir -p "$STUB_DIR/bin"; export STUB_DIR
    PATH="$STUB_DIR/bin:$PATH"
    _my_help_palette_available() { return 0; }
'

@test "P23: every rendered row starts its description at the same column" {
    run_in_bash '
        {
            _my_help_search_candidates alias
            printf "a_name_that_is_far_longer_than_24\tlong one\talias\tx.sh:1\techo hi\n"
        } | _my_help_render_rows alias | cut -f1 |
            awk "{ match(\$0, /  +/); c[RSTART + RLENGTH]++ } END { n = 0; for (k in c) n++; print n }"
        printf "a_name_that_is_far_longer_than_24\td\talias\tx.sh:1\tv\n" |
            _my_help_render_rows alias | cut -f1 | cut -d" " -f1
    '
    assert_success
    assert_line --index 0 "1"
    assert_line --index 1 "a_name_that_is_far_long…"
}

@test "P24: per-kind row rules — no -help or [Category] on topics, badges only in /all" {
    run_in_bash '
        _my_help_search_candidates topic | _my_help_render_rows topic | cut -f1 > "$HOME/t"
        grep -c -e "-help " -e "\[" "$HOME/t" || true
        grep -c "^git " "$HOME/t"
        printf "gco\tshell-common/aliases/git.sh:35\talias\tshell-common/aliases/git.sh:35\tgit checkout\n" |
            _my_help_render_rows alias | cut -f1
        printf "gwt\tworktree\tfunc\tshell-common/functions/git_worktree.sh:18\tgwt()\n" |
            _my_help_render_rows func | cut -f1
        printf "development\tDev tools\tcategory\t21 topics\t\n" |
            _my_help_render_rows category | cut -f1
        printf "development\tDev tools\tcategory\t21 topics\t\n" |
            _my_help_render_rows all | cut -f1
    '
    assert_success
    assert_line --index 0 "0"
    assert_line --index 1 "1"
    assert_line --index 2 "gco  git checkout  · git.sh"
    assert_line --index 3 "gwt  worktree  · git_worktree.sh"
    assert_line --index 4 "development  Dev tools  · 21 topics"
    assert_line --index 5 "development  cat    Dev tools  · 21 topics"
}

@test "P25: no-colour mode streams carry no ESC and fzf gets --color=bw" {
    run_in_bash "
        _my_help_search_candidates all | _my_help_render_rows all | grep -c \$'\\033' || true
        ${_stub_prelude}"'
        _install_stub_fzf() { :; }
    '
    assert_success
    assert_line --index 0 "0"

    run_in_bash "${_stub_prelude}
        $(declare -f _install_stub_fzf)
        _install_stub_fzf
        _my_help_search >/dev/null 2>&1
        grep -c -x -e '--color=bw' -e '--ansi' \"\$STUB_DIR/args.1\"
    "
    assert_success
    assert_output "2"
}

@test "P26: --scopes emits the 5-row menu with counts from the records, writing nothing" {
    _stage_records
    local before after
    before=$(find "$TEST_TEMP_HOME" | LC_ALL=C sort)
    _preview --scopes "$TEST_TEMP_HOME/records.tsv"
    assert_success
    after=$(find "$TEST_TEMP_HOME" | LC_ALL=C sort)
    [ "$before" = "$after" ]
    [ "${#lines[@]}" -eq 5 ]
    assert_line --index 0 "/topic${TAB}Help topics${TAB}scope${TAB}1${TAB}topic"
    assert_line --index 1 "/alias${TAB}Repo aliases${TAB}scope${TAB}1${TAB}alias"
    assert_line --index 3 "/cat${TAB}Categories${TAB}scope${TAB}1${TAB}category"
    assert_line --index 4 "/all${TAB}Everything${TAB}scope${TAB}4${TAB}all"

    # A single-kind record file leaves the other kinds blank, not wrong.
    printf 'a\tb\talias\tx:1\tv\na2\tb\talias\tx:2\tv\n' > "$TEST_TEMP_HOME/one.tsv"
    _preview --scopes "$TEST_TEMP_HOME/one.tsv"
    assert_line --index 0 "/topic${TAB}Help topics${TAB}scope${TAB}${TAB}topic"
    assert_line --index 1 "/alias${TAB}Repo aliases${TAB}scope${TAB}2${TAB}alias"
    assert_line --index 4 "/all${TAB}Everything${TAB}scope${TAB}${TAB}all"
}

@test "P27: Tab / Shift-Tab cycle topic->alias->func->category->all and carry the query" {
    run_in_bash "${_stub_prelude}
        $(declare -f _install_stub_fzf)
        _install_stub_fzf
        "'for i in 1 2 3 4 5; do printf "doc\ntab\n" > "$STUB_DIR/reply.$i"; done
        printf "doc\nbtab\n" > "$STUB_DIR/reply.6"
        _my_help_search >/dev/null 2>&1
        for i in 1 2 3 4 5 6 7; do
            printf "%s:" "$(awk -F"\t" "{print \$4}" "$STUB_DIR/stream.$i" | LC_ALL=C sort -u | tr "\n" ",")"
            grep -c -x -- "--query=doc" "$STUB_DIR/args.$i" || true
        done
    '
    assert_success
    assert_line --index 0 "topic,:0"
    assert_line --index 1 "alias,:1"
    assert_line --index 2 "func,:1"
    assert_line --index 3 "category,:1"
    assert_line --index 4 "alias,category,func,topic,:1"
    assert_line --index 5 "topic,:1"
    assert_line --index 6 "alias,category,func,topic,:1"
}

@test "P28: Enter on a scope-menu row switches scope without rendering anything" {
    run_in_bash "${_stub_prelude}
        $(declare -f _install_stub_fzf)
        _install_stub_fzf
        "'printf "/a\n\nx\t/alias\tRepo aliases\tscope\t\talias\n" > "$STUB_DIR/reply.1"
        _my_help_search > "$HOME/palette.out" 2>&1
        echo "rounds=$(cat "$STUB_DIR/count")"
        echo "kinds2=$(awk -F"\t" "{print \$4}" "$STUB_DIR/stream.2" | LC_ALL=C sort -u | tr "\n" ",")"
        grep -c -x -- "--query=" "$STUB_DIR/args.2"
        wc -c < "$HOME/palette.out" | tr -d " "
    '
    assert_success
    assert_line --index 0 "rounds=2"
    assert_line --index 1 "kinds2=alias,"
    assert_line --index 2 "1"
    assert_line --index 3 "0"
}

@test "P29: the preview layout follows the terminal width in three tiers" {
    run_in_bash 'for c in 160 120 119 100 99 80 "" junk; do _my_help_palette_layout "$c"; done'
    assert_success
    assert_line --index 0 "right,50%,border-left,<45(down,45%,border-top)"
    assert_line --index 1 "right,50%,border-left,<45(down,45%,border-top)"
    assert_line --index 2 "down,45%,border-top"
    assert_line --index 3 "down,45%,border-top"
    assert_line --index 4 --regexp "^hidden,"
    assert_line --index 5 --regexp "^hidden,"
    assert_line --index 6 --regexp "^right,"
    assert_line --index 7 --regexp "^right,"
}

@test "P30: fzf version tiers — 0.44 gets no Tier B flags, 0.63 does, <0.44 falls back" {
    run_in_bash '
        _my_help_fzf_ge 0.44.0 0.44.1 && echo T1
        _my_help_fzf_ge 0.58.0 0.44.1 || echo F2
        _my_help_fzf_ge 0.63.0 0.63.0 && echo T3
        _my_help_fzf_ge 0.44.0 "" || echo F4
    '
    assert_success
    assert_output "T1
F2
T3
F4"

    run_in_bash "${_stub_prelude}
        $(declare -f _install_stub_fzf)
        _install_stub_fzf
        STUB_VER=0.44.1 _my_help_search >/dev/null 2>&1
        grep -c -e '--style' -e '--footer' -e '--ghost' \"\$STUB_DIR/args.1\" || true
        grep -c -e '--border-label=' \"\$STUB_DIR/args.1\"
        rm -f \"\$STUB_DIR/count\"
        STUB_VER=0.63.0 _my_help_search >/dev/null 2>&1
        grep -c -e '--style=full' -e '--footer=' -e '--ghost=' \"\$STUB_DIR/args.1\"
        rm -f \"\$STUB_DIR/count\"
        STUB_VER=0.40.0 _my_help_search
    "
    assert_success
    assert_line --index 0 "0"
    assert_line --index 1 "1"
    assert_line --index 2 "3"
    assert_output --partial "fzf 0.44+"
    assert_output --partial "Categories"
}

@test "P31: every card opens with 'kind · name · ...' and never runs or writes" {
    _stage_records
    local before after
    before=$(find "$TEST_TEMP_HOME" | LC_ALL=C sort)

    _preview "$TEST_TEMP_HOME/records.tsv" 0
    assert_line --index 0 "alias · evil · fake.sh:1"
    _preview "$TEST_TEMP_HOME/records.tsv" 1
    assert_line --index 0 --regexp "^topic · git-help( · .*)?$"
    refute_output --partial "[Development]"
    _preview "$TEST_TEMP_HOME/records.tsv" 2
    assert_line --index 0 "category · development · 15 topics"
    refute_output --partial "╔"
    _preview "$TEST_TEMP_HOME/records.tsv" 3
    assert_line --index 0 "func · gwt · shell-common/functions/git_worktree.sh:1"
    # The excerpt: the file's first line, numbered.
    assert_line --regexp "^ +1  #!"
    assert_output --partial "never runs it"
    _preview "$TEST_TEMP_HOME/records.tsv" 0 "/a"
    assert_line --index 0 "scope · /topic · 1"

    after=$(find "$TEST_TEMP_HOME" | LC_ALL=C sort)
    [ "$before" = "$after" ]
    [ -e "$TEST_TEMP_HOME/marker" ]

    # A location outside the repo is never opened.
    printf 'x\td\tfunc\t../../etc/passwd:1\tx()\n' > "$TEST_TEMP_HOME/escape.tsv"
    _preview "$TEST_TEMP_HOME/escape.tsv" 0
    refute_output --partial "root:"
    assert_output --partial "source: ../../etc/passwd:1"
}

@test "P32: with FZF_PREVIEW_COLUMNS=40 no card line is wider than 40" {
    _stage_records
    local i
    for i in 0 1 2 3; do
        run env HOME="$TEST_TEMP_HOME" XDG_CACHE_HOME="$TEST_TEMP_HOME" TERM=dumb \
            DOTFILES_TEST_MODE=1 FZF_PREVIEW_COLUMNS=40 "$PREVIEW" "$TEST_TEMP_HOME/records.tsv" "$i"
        assert_success
        [ -n "$output" ]
        printf '%s\n' "$output" | awk 'length($0) > 40 { bad++ } END { exit bad > 0 }'
    done
}

@test "P33: a func entry prints its source excerpt on Enter, not just the signature (F-10)" {
    run_in_bash '_my_help_show_alias_entry "gwt${TAB:-	}d	func	shell-common/functions/git_worktree.sh:18	gwt()"'
    assert_success
    assert_output --partial "Function: gwt"
    assert_line --regexp "18  gwt\(\) \{"
    refute_output --partial "definition: gwt()"
}

@test "P34: zsh renders the same rows and layout as bash (NF-5)" {
    local cmd='_my_help_search_candidates topic | _my_help_render_rows topic | cksum; _my_help_palette_layout 80; _my_help_scope_step next all'
    run_in_bash "$cmd"
    assert_success
    local bash_out="$output"
    run_in_zsh "$cmd"
    assert_success
    [ "$output" = "$bash_out" ]
}
