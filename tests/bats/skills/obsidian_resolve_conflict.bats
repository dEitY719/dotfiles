#!/usr/bin/env bats
# tests/bats/skills/obsidian_resolve_conflict.bats
# Offline coverage for claude/skills/obsidian-resolve-conflict/lib/*.sh (issue #1326).
#
# Every fixture is a throwaway git repo standing in for a vault. No test ever
# touches a real vault: OBSIDIAN_VAULT_WIN_ROOT / OBSIDIAN_VAULT_WSL_ROOT and
# HOME are all redirected into the per-test temp dir, so the Windows glob and
# the WSL candidate probe can only ever see the fixtures.
#
# Verification map:
#   F-2   resolve-vault.sh      — glob with a Windows username != WSL username,
#                                 0 / 2+ matches stop, WSL candidate + mode,
#                                 missing --vault path stops without mkdir
#   F-4   classify-conflicts.sh — A/B/C boundary keyed on the *current*
#                                 .gitignore, artifact always A, 90-personal
#                                 excluded from automatic handling (F-8)
#   F-7   resolve-vault.sh      — PEER_MATCH from origin URL equality
#   F-9   verify-sync.sh        — leftover conflicts, artifact, .gitignore
#                                 SUGGEST, nested clone report
#   NF-3  classify-conflicts.sh — a note body is never resolved automatically
#   NF-5  classify-conflicts.sh — without --apply index and worktree are intact
#   NF-6  classify-conflicts.sh — .git/index.lock backoff, lock never deleted
#   NF-7  resolve-vault.sh      — internal + github.com refuses push, GHES does not
#   NF-1/NF-2 grep              — the destructive-command guard

load '../test_helper'

setup() {
    setup_isolated_home
    SKILL_DIR="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/obsidian-resolve-conflict"
    RESOLVE_VAULT="${SKILL_DIR}/lib/resolve-vault.sh"
    CLASSIFY="${SKILL_DIR}/lib/classify-conflicts.sh"
    VERIFY_SYNC="${SKILL_DIR}/lib/verify-sync.sh"

    WORK="$(mktemp -d)"
    # Hermetic detection roots — never /mnt/c/Users, never ~/para/project.
    export OBSIDIAN_VAULT_WIN_ROOT="${WORK}/winroot"
    export OBSIDIAN_VAULT_WSL_ROOT="${WORK}/wslroot"
    mkdir -p "$OBSIDIAN_VAULT_WIN_ROOT" "$OBSIDIAN_VAULT_WSL_ROOT"
    unset OBSIDIAN_VAULT_WIN_DIR OBSIDIAN_VAULT_DIR
}

teardown() {
    if [ -n "${WORK:-}" ] && [ -d "$WORK" ]; then
        rm -rf "$WORK"
    fi
    teardown_isolated_home
}

# git_init <dir> — throwaway repo, hooks and signing off so the fixture is
# independent of the developer's own git config.
git_init() {
    git -c init.defaultBranch=main init -q "$1"
    git -C "$1" config core.hooksPath /dev/null
    git -C "$1" config user.email "test@example.com"
    git -C "$1" config user.name "Test"
    git -C "$1" config commit.gpgsign false
}

# make_clone <dir> <origin-url> — seeded repo with an origin remote
make_clone() {
    mkdir -p "$1"
    git_init "$1"
    printf 'seed\n' >"$1/README.md"
    git -C "$1" add -- README.md
    git -C "$1" commit -q -m "seed"
    [ -n "${2:-}" ] && git -C "$1" remote add origin "$2"
    return 0
}

# make_vault — reproduces the 2026-08-12 case: obsidian-git's auto-backup
# modified .obsidian/graph.json on this side while the remote excluded the
# same file from tracking, plus the plugin's own artifact file.
# Extra fixtures are opt-in via the arg list:
#   note      a both-modified note body (class B)
#   keeper    a both-modified .obsidian/appearance.json, NOT gitignored (class C)
make_vault() {
    VAULT="${WORK}/vault"
    local want_note=0 want_keeper=0 arg
    for arg in "$@"; do
        case "$arg" in
            note) want_note=1 ;;
            keeper) want_keeper=1 ;;
        esac
    done

    mkdir -p "${VAULT}/.obsidian" "${VAULT}/40-Areas"
    git_init "$VAULT"
    printf 'seed\n' >"${VAULT}/README.md"
    printf '{"graph":1}\n' >"${VAULT}/.obsidian/graph.json"
    printf '.trash/\n' >"${VAULT}/.gitignore"
    if [ "$want_note" -eq 1 ]; then
        printf 'base note\n' >"${VAULT}/40-Areas/note.md"
    fi
    if [ "$want_keeper" -eq 1 ]; then
        printf '{"theme":"base"}\n' >"${VAULT}/.obsidian/appearance.json"
    fi
    git -C "$VAULT" add -A
    git -C "$VAULT" commit -q -m "seed"
    git -C "$VAULT" branch remote-side

    # local side — obsidian-git auto-backup
    printf '{"graph":2}\n' >"${VAULT}/.obsidian/graph.json"
    if [ "$want_note" -eq 1 ]; then
        printf 'local note\n' >"${VAULT}/40-Areas/note.md"
    fi
    if [ "$want_keeper" -eq 1 ]; then
        printf '{"theme":"local"}\n' >"${VAULT}/.obsidian/appearance.json"
    fi
    git -C "$VAULT" commit -q -am "vault backup: local"

    # remote side — stop tracking graph.json
    git -C "$VAULT" checkout -q remote-side
    printf '.trash/\n.obsidian/graph.json\n' >"${VAULT}/.gitignore"
    git -C "$VAULT" rm -q --cached -- .obsidian/graph.json
    if [ "$want_note" -eq 1 ]; then
        printf 'remote note\n' >"${VAULT}/40-Areas/note.md"
    fi
    if [ "$want_keeper" -eq 1 ]; then
        printf '{"theme":"remote"}\n' >"${VAULT}/.obsidian/appearance.json"
    fi
    git -C "$VAULT" add -A
    git -C "$VAULT" commit -q -m "chore(gitignore): exclude graph.json"

    git -C "$VAULT" checkout -q main
    printf 'obsidian-git artifact\n' >"${VAULT}/conflict-files-obsidian-git.md"
    git -C "$VAULT" merge remote-side >/dev/null 2>&1 || true
}

# ── F-2: vault path resolution ────────────────────────────────────────

@test "F-2: the Windows glob absorbs a Windows username != the WSL username" {
    # WSL user is whatever runs the tests; the Windows account is different.
    win="${OBSIDIAN_VAULT_WIN_ROOT}/byoungwoo.yoon/Documents/ObsidianVault-PARA"
    make_clone "$win" 'git@github.com:dEitY719/obsidian-para.git'

    run bash "$RESOLVE_VAULT" windows --mode external
    assert_success
    assert_line "VAULT='${win}'"
    assert_line "SIDE='windows'"
}

@test "F-2: zero glob matches stops and lists the candidates, creating nothing" {
    run bash "$RESOLVE_VAULT" windows --mode external
    assert_failure
    assert_output --partial 'ERROR'
    assert_output --partial '--vault'
    [ ! -e "${OBSIDIAN_VAULT_WIN_ROOT}/Documents" ]
}

@test "F-2: two glob matches refuse to pick one" {
    make_clone "${OBSIDIAN_VAULT_WIN_ROOT}/userA/Documents/ObsidianVault-PARA" ''
    make_clone "${OBSIDIAN_VAULT_WIN_ROOT}/userB/Documents/ObsidianVault-PARA" ''

    run bash "$RESOLVE_VAULT" windows --mode external
    assert_failure
    assert_output --partial 'userA'
    assert_output --partial 'userB'
    assert_output --partial '--vault'
}

@test "F-2: both WSL candidates present — internal picks the company clone" {
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para-company" 'git@ghes.internal.example:team/obsidian-para-company.git'
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para" 'git@github.com:dEitY719/obsidian-para.git'

    run bash "$RESOLVE_VAULT" wsl --mode internal
    assert_success
    assert_line "VAULT='${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para-company'"
}

@test "F-2: both WSL candidates present — external picks the personal clone" {
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para-company" 'git@ghes.internal.example:team/obsidian-para-company.git'
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para" 'git@github.com:dEitY719/obsidian-para.git'

    run bash "$RESOLVE_VAULT" wsl --mode external
    assert_success
    assert_line "VAULT='${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para'"
}

@test "F-2: the mode comes from ~/.dotfiles-setup-mode, legacy numbers included" {
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para-company" 'git@ghes.internal.example:team/obsidian-para-company.git'
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para" 'git@github.com:dEitY719/obsidian-para.git'
    printf '2\n' >"${HOME}/.dotfiles-setup-mode"

    run bash "$RESOLVE_VAULT" wsl
    assert_success
    assert_line "MODE='internal'"
    assert_line "VAULT='${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para-company'"
}

@test "F-2: both WSL candidates + unknown mode stops instead of guessing" {
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para-company" ''
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para" ''

    run bash "$RESOLVE_VAULT" wsl
    assert_failure
    assert_output --partial 'obsidian-para-company'
    assert_output --partial 'obsidian-para'
}

@test "NF-4: a --vault path that does not exist stops without creating it" {
    missing="${WORK}/no/such/vault"
    run bash "$RESOLVE_VAULT" wsl --vault "$missing"
    assert_failure
    assert_output --partial "$missing"
    [ ! -d "${WORK}/no" ]
}

@test "NF-4: a --vault path that is not a git repo stops" {
    plain="${WORK}/plain"
    mkdir -p "$plain"
    run bash "$RESOLVE_VAULT" wsl --vault "$plain"
    assert_failure
    assert_output --partial 'git'
}

@test "F-2: the remote name is emitted so merge-flow.md's \$REMOTE resolves" {
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para" 'git@github.com:dEitY719/obsidian-para.git'

    run bash "$RESOLVE_VAULT" wsl --mode external
    assert_success
    assert_line "REMOTE='origin'"
    # ...and the emitted block really is eval-able into that variable.
    run bash -c "eval \"\$(bash '$RESOLVE_VAULT' wsl --mode external)\"; printf '%s\n' \"\$REMOTE\""
    assert_success
    assert_output 'origin'
}

@test "F-2: origin_host keeps its locals out of the caller's scope" {
    run bash -c "source '$RESOLVE_VAULT' -h >/dev/null
        origin_host 'git@github.com:dEitY719/obsidian-para.git' >/dev/null
        printf 'url=[%s] rest=[%s]\n' \"\${url-unset}\" \"\${rest-unset}\""
    assert_success
    assert_output 'url=[unset] rest=[unset]'
}

# ── NF-7: the internal-PC push guard ──────────────────────────────────

@test "NF-7: internal + github.com origin refuses to push" {
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para" 'git@github.com:dEitY719/obsidian-para.git'

    run bash "$RESOLVE_VAULT" wsl --mode internal
    assert_success
    assert_line "PUSH_ALLOWED='no'"
    assert_output --partial 'pull only'
    assert_output --partial 'external/public'
}

@test "NF-7: internal + GHES origin pushes normally" {
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para-company" 'git@ghes.internal.example:team/obsidian-para-company.git'

    run bash "$RESOLVE_VAULT" wsl --mode internal
    assert_success
    assert_line "PUSH_ALLOWED='yes'"
    refute_line "PUSH_ALLOWED='no'"
}

@test "NF-7: https github.com origin is caught too, not just the ssh form" {
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para" 'https://github.com/dEitY719/obsidian-para.git'

    run bash "$RESOLVE_VAULT" wsl --mode internal
    assert_success
    assert_line "PUSH_ALLOWED='no'"
}

@test "NF-7: a mixed-case GitHub.com host does not slip past the guard" {
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para" 'https://GitHub.com/dEitY719/obsidian-para.git'

    run bash "$RESOLVE_VAULT" wsl --mode internal
    assert_success
    assert_line "PUSH_ALLOWED='no'"
    assert_output --partial 'pull only'
    # only the comparison is lowercased — the URL is reported as it is stored
    assert_line "VAULT_ORIGIN='https://GitHub.com/dEitY719/obsidian-para.git'"
}

@test "NF-7: a mixed-case scp-form GitHub.com host is caught too" {
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para" 'git@GitHub.Com:dEitY719/obsidian-para.git'

    run bash "$RESOLVE_VAULT" wsl --mode internal
    assert_success
    assert_line "PUSH_ALLOWED='no'"
}

@test "NF-7: external mode pushes to github.com" {
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para" 'git@github.com:dEitY719/obsidian-para.git'

    run bash "$RESOLVE_VAULT" wsl --mode external
    assert_success
    assert_line "PUSH_ALLOWED='yes'"
}

# ── F-7: peer matching by origin URL ──────────────────────────────────

@test "F-7: a peer sharing the origin is reported as a match" {
    make_clone "${OBSIDIAN_VAULT_WIN_ROOT}/winuser/Documents/ObsidianVault-PARA" 'git@github.com:dEitY719/obsidian-para.git'
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para" 'git@github.com:dEitY719/obsidian-para.git'

    run bash "$RESOLVE_VAULT" windows --mode external
    assert_success
    assert_line "PEER='${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para'"
    assert_line "PEER_MATCH='yes'"
}

@test "F-7: a peer pointing at a different origin is refused" {
    make_clone "${OBSIDIAN_VAULT_WIN_ROOT}/winuser/Documents/ObsidianVault-PARA" 'git@ghes.internal.example:team/obsidian-para-company.git'
    make_clone "${OBSIDIAN_VAULT_WSL_ROOT}/obsidian-para" 'git@github.com:dEitY719/obsidian-para.git'

    run bash "$RESOLVE_VAULT" windows --mode external
    assert_success
    assert_line "PEER_MATCH='no'"
}

@test "F-7: no peer at all is reported as none, not as an error" {
    make_clone "${OBSIDIAN_VAULT_WIN_ROOT}/winuser/Documents/ObsidianVault-PARA" 'git@github.com:dEitY719/obsidian-para.git'

    run bash "$RESOLVE_VAULT" windows --mode external
    assert_success
    assert_line "PEER=''"
    assert_line "PEER_MATCH='none'"
}

# ── F-4: classification ───────────────────────────────────────────────

@test "F-4: today's case classifies as two automatic rows and nothing manual" {
    make_vault

    run bash "$CLASSIFY" "$VAULT"
    assert_success
    assert_line $'A\tdelete\tconflict-files-obsidian-git.md'
    assert_line $'A\trm-cached\t.obsidian/graph.json'
    assert_line 'SUMMARY: A=2 B=0 C=0'
}

@test "NF-3: a both-modified note body is class B, never resolved" {
    make_vault note

    run bash "$CLASSIFY" "$VAULT" --apply
    assert_success
    assert_line $'B\tmanual\t40-Areas/note.md'
    refute_output --partial $'APPLIED\tmanual'

    # still conflicting, and both sides still recoverable from the index
    run git -C "$VAULT" ls-files -u -- 40-Areas/note.md
    assert_output --partial '40-Areas/note.md'
    run git -C "$VAULT" show ':2:40-Areas/note.md'
    assert_output 'local note'
    run git -C "$VAULT" show ':3:40-Areas/note.md'
    assert_output 'remote note'
}

@test "F-4: a .obsidian file the .gitignore does NOT exclude stays class C" {
    make_vault keeper

    run bash "$CLASSIFY" "$VAULT"
    assert_success
    assert_line $'C\tmanual\t.obsidian/appearance.json'
    refute_line $'A\trm-cached\t.obsidian/appearance.json'
}

@test "F-4: --apply keeps the excluded file on disk while dropping the index entry" {
    make_vault

    run bash "$CLASSIFY" "$VAULT" --apply
    assert_success
    assert_line $'APPLIED\trm-cached\t.obsidian/graph.json'
    assert_line $'APPLIED\tdelete\tconflict-files-obsidian-git.md'

    # the acceptance criterion: the working copy survives
    [ -f "${VAULT}/.obsidian/graph.json" ]
    run cat "${VAULT}/.obsidian/graph.json"
    assert_output '{"graph":2}'

    # ...and the plugin artifact is gone
    [ ! -e "${VAULT}/conflict-files-obsidian-git.md" ]

    # no conflict left, so the merge can be committed
    run git -C "$VAULT" ls-files -u
    assert_output ''
    git -C "$VAULT" commit -q --no-edit -m "merge: resolve"

    run git -C "$VAULT" status --porcelain
    assert_output ''
    [ -f "${VAULT}/.obsidian/graph.json" ]
}

@test "NF-5: without --apply the index and the worktree are untouched" {
    make_vault note

    before_status="$(git -C "$VAULT" status --porcelain)"
    before_index="$(git -C "$VAULT" ls-files -s)"
    before_graph="$(cat "${VAULT}/.obsidian/graph.json")"

    run bash "$CLASSIFY" "$VAULT"
    assert_success

    [ "$(git -C "$VAULT" status --porcelain)" = "$before_status" ]
    [ "$(git -C "$VAULT" ls-files -s)" = "$before_index" ]
    [ "$(cat "${VAULT}/.obsidian/graph.json")" = "$before_graph" ]
    [ -f "${VAULT}/conflict-files-obsidian-git.md" ]
}

@test "F-4: no conflicts at all is a clean, idempotent no-op" {
    make_clone "${WORK}/quiet" 'git@github.com:dEitY719/obsidian-para.git'

    run bash "$CLASSIFY" "${WORK}/quiet"
    assert_success
    assert_line 'SUMMARY: A=0 B=0 C=0'

    run bash "$CLASSIFY" "${WORK}/quiet" --apply
    assert_success
    assert_output --partial 'SUMMARY: A=0 B=0 C=0'
}

@test "F-4: the obsidian-git artifact is class A even when merely untracked" {
    make_clone "${WORK}/quiet" ''
    printf 'artifact\n' >"${WORK}/quiet/conflict-files-obsidian-git.md"

    run bash "$CLASSIFY" "${WORK}/quiet" --apply
    assert_success
    assert_line $'A\tdelete\tconflict-files-obsidian-git.md'
    [ ! -e "${WORK}/quiet/conflict-files-obsidian-git.md" ]
}

@test "F-4: a user note merely sharing the artifact's basename is class B" {
    # obsidian-git writes its artifact at the vault root only. A note deeper in
    # the tree with the same filename is the user's writing (NF-3).
    make_clone "${WORK}/quiet" ''
    lookalike="40-Areas/conflict-files-obsidian-git.md"
    mkdir -p "${WORK}/quiet/40-Areas"
    printf 'my own note\n' >"${WORK}/quiet/${lookalike}"
    git -C "${WORK}/quiet" add -- "$lookalike"
    git -C "${WORK}/quiet" commit -q -m "track lookalike note"
    printf 'edited today\n' >>"${WORK}/quiet/${lookalike}"

    run bash "$CLASSIFY" "${WORK}/quiet" --apply
    assert_success
    assert_line $'B\tmanual\t'"${lookalike}"
    refute_line $'A\tdelete\t'"${lookalike}"
    refute_output --partial $'APPLIED'
    assert_line 'SUMMARY: A=0 B=1 C=0'
    # the acceptance criterion: the note survives, contents intact
    [ -f "${WORK}/quiet/${lookalike}" ]
    run cat "${WORK}/quiet/${lookalike}"
    assert_output --partial 'my own note'
}

@test "F-4: --apply reports SKIPPED, not APPLIED, when the path is already gone" {
    # The classify() -> apply_row() race: the row was real when it was
    # classified, but something removed the file before it was applied.
    make_clone "${WORK}/quiet" ''

    run bash -c "source '$CLASSIFY' -h >/dev/null
        VAULT='${WORK}/quiet'
        apply_row delete 'conflict-files-obsidian-git.md'"
    assert_success
    assert_line $'SKIPPED\tdelete\tconflict-files-obsidian-git.md\talready absent'
    refute_output --partial 'APPLIED'
}

@test "F-8: a nested 90-personal path is excluded from automatic handling" {
    # A pre-merge dirty tree, so the path really reaches the classifier.
    make_clone "${WORK}/quiet" ''
    mkdir -p "${WORK}/quiet/90-personal"
    printf 'x\n' >"${WORK}/quiet/90-personal/nested.md"
    git -C "${WORK}/quiet" add -- 90-personal/nested.md
    git -C "${WORK}/quiet" commit -q -m "track nested"
    printf 'y\n' >"${WORK}/quiet/90-personal/nested.md"

    run bash "$CLASSIFY" "${WORK}/quiet" --apply
    assert_success
    assert_line $'C\tnested-repo\t90-personal/nested.md'
    assert_output --partial 'embedded repo'
    refute_output --partial $'APPLIED'
    # untouched: still tracked, still dirty
    run git -C "${WORK}/quiet" status --porcelain
    assert_output --partial '90-personal/nested.md'
}

@test "F-3: unmerged paths without MERGE_HEAD stop the run" {
    make_vault
    rm -f "${VAULT}/.git/MERGE_HEAD"

    run bash "$CLASSIFY" "$VAULT"
    assert_failure
    assert_output --partial 'MERGE_HEAD'
}

@test "classify: a non-git directory fails loudly" {
    mkdir -p "${WORK}/plain"
    run bash "$CLASSIFY" "${WORK}/plain"
    assert_failure
    assert_output --partial 'git'
}

# ── NF-6: .git/index.lock backoff ─────────────────────────────────────

@test "NF-6: --apply retries past a transient .git/index.lock" {
    make_vault

    lock="${VAULT}/.git/index.lock"
    : >"$lock"
    (
        sleep 0.5
        rm -f "$lock"
    ) &
    remover=$!

    run bash "$CLASSIFY" "$VAULT" --apply
    wait "$remover" || true
    assert_success
    assert_line $'APPLIED\trm-cached\t.obsidian/graph.json'
}

@test "NF-6: a lock that never clears stops loudly and is never deleted" {
    make_vault
    lock="${VAULT}/.git/index.lock"
    : >"$lock"

    # Neutralise the backoff so 5 retries do not really sleep 30s.
    mkdir -p "${WORK}/bin"
    printf '#!/usr/bin/env bash\nexit 0\n' >"${WORK}/bin/sleep"
    chmod +x "${WORK}/bin/sleep"

    run env PATH="${WORK}/bin:${PATH}" bash "$CLASSIFY" "$VAULT" --apply
    assert_failure
    assert_output --partial 'index.lock'
    assert_output --partial 'obsidian-git'
    # the lock belongs to obsidian-git; the skill must leave it alone
    [ -f "$lock" ]
}

# ── F-9: verification report ──────────────────────────────────────────

@test "F-9: verify-sync PASSes on a fully resolved vault and reports the peer" {
    make_vault
    bash "$CLASSIFY" "$VAULT" --apply >/dev/null
    git -C "$VAULT" commit -q --no-edit -m "merge: resolve"
    make_clone "${WORK}/peer" 'git@github.com:dEitY719/obsidian-para.git'

    run bash "$VERIFY_SYNC" "$VAULT" --peer "${WORK}/peer" --resolved '.obsidian/graph.json'
    assert_success
    assert_output --partial 'VERDICT: PASS'
    assert_output --partial '[PEER]'
    assert_output --partial '[TARGET]'
}

@test "F-9: verify-sync FAILs while a conflict is still unresolved" {
    make_vault note

    run bash "$VERIFY_SYNC" "$VAULT"
    assert_failure
    assert_output --partial 'VERDICT: FAIL'
}

@test "F-9: an auto-resolved path missing from .gitignore is only SUGGESTed" {
    make_clone "${WORK}/quiet" ''
    before="$(git -C "${WORK}/quiet" status --porcelain)"

    run bash "$VERIFY_SYNC" "${WORK}/quiet" --resolved '.obsidian/workspace.json'
    assert_success
    assert_output --partial 'SUGGEST'
    assert_output --partial '.obsidian/workspace.json'
    # suggestion only — .gitignore is never written
    [ ! -e "${WORK}/quiet/.gitignore" ]
    [ "$(git -C "${WORK}/quiet" status --porcelain)" = "$before" ]
}

@test "F-8: verify-sync reports a nested 90-personal clone without touching it" {
    make_clone "${WORK}/quiet" ''
    make_clone "${WORK}/quiet/90-personal" ''
    printf 'dirty\n' >>"${WORK}/quiet/90-personal/README.md"

    run bash "$VERIFY_SYNC" "${WORK}/quiet"
    assert_success
    assert_output --partial '[NESTED]'
    assert_output --partial '90-personal'
    run git -C "${WORK}/quiet/90-personal" status --porcelain
    assert_output --partial 'README.md'
}

@test "F-9: verify-sync fails on a non-git target" {
    mkdir -p "${WORK}/plain"
    run bash "$VERIFY_SYNC" "${WORK}/plain"
    assert_failure
    assert_output --partial 'VERDICT: FAIL'
}

# ── NF-1 / NF-2: destructive-command guard ────────────────────────────

@test "NF-1/NF-2: no forbidden command appears anywhere in the skill" {
    for token in 'rebase' '--force' '--force-with-lease' 'reset --hard' 'checkout .' 'rm -rf'; do
        run grep -rnF -- "$token" "$SKILL_DIR"
        assert_failure
        assert_output ''
    done
}

@test "NF-1: the skill never pushes with an escalating flag" {
    run grep -rnE 'push[^|]*(--force|-f[[:space:]])' "$SKILL_DIR"
    assert_failure
}

@test "NF-2: lib scripts never widen a commit with -a / -A / git add ." {
    run grep -rnE 'add[[:space:]]+(-A|--all|\.)|commit[[:space:]].*[[:space:]]-a([[:space:]]|$)' "${SKILL_DIR}/lib"
    assert_failure
}

# ── SKILL.md conventions (NF-10) ──────────────────────────────────────

@test "NF-10: SKILL.md stays within 100 lines" {
    lines="$(wc -l <"${SKILL_DIR}/SKILL.md")"
    [ "$lines" -le 100 ]
}

@test "NF-10: SKILL.md declares the obsidian:resolve-conflict name" {
    run grep -c '^name: obsidian:resolve-conflict$' "${SKILL_DIR}/SKILL.md"
    assert_output '1'
}

@test "NF-10: SKILL.md declares the opus tier and the issue's allowed-tools" {
    run grep -c '^    tier: opus$' "${SKILL_DIR}/SKILL.md"
    assert_output '1'
    run grep -c '^allowed-tools: Bash, Read, Edit, Write, Grep$' "${SKILL_DIR}/SKILL.md"
    assert_output '1'
}

@test "F-1: SKILL.md routes -h/--help/help to references/help.md verbatim" {
    run grep -n 'references/help.md` verbatim' "${SKILL_DIR}/SKILL.md"
    assert_success
    [ -f "${SKILL_DIR}/references/help.md" ]
    for flag in '--no-push' '--no-sync-peer' '--dry-run' '--vault'; do
        run grep -c -- "$flag" "${SKILL_DIR}/references/help.md"
        refute_output '0'
    done
}

@test "F-1: every reference file the SKILL.md names exists" {
    for f in help.md options.md classify.md merge-flow.md pc-modes.md; do
        [ -f "${SKILL_DIR}/references/${f}" ]
    done
}

@test "NF-9: pc-modes.md links the SSOT instead of copying its tables" {
    run grep -c 'docs/.ssot/pc-environment.md' "${SKILL_DIR}/references/pc-modes.md"
    refute_output '0'
    # the SSOT's own §2/§3 row labels must not be duplicated here
    run grep -nE '사내망|최고 사양|Ollama 로컬 서빙|read/write' "${SKILL_DIR}/references/pc-modes.md"
    assert_failure
}

@test "lib scripts print their own usage on -h" {
    for s in "$RESOLVE_VAULT" "$CLASSIFY" "$VERIFY_SYNC"; do
        run bash "$s" -h
        assert_success
        assert_output --partial 'Usage:'
    done
}
