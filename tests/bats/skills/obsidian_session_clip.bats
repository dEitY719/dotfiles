#!/usr/bin/env bats
# tests/bats/skills/obsidian_session_clip.bats
# Offline coverage for claude/skills/obsidian-session-clip/lib/*.sh (issue #1321).
#
# Verification map:
#   NF-1  safe-name.sh sanitize  — 9 forbidden chars + control chars, 100-char cut
#   F-2   safe-name.sh resolve   — -2 / -3 collision suffixes, stop after 10
#   NF-2  commit-note.sh         — pathspec-limited: exactly one file per commit,
#                                  never -a / -A / `git add .`,
#                                  .git/index.lock retry with backoff
#   NF-4  commit-note.sh         — note survives + exit 0 when the lock never clears
#   F-3/F-5 verify-clip.sh       — frontmatter keys, status, memo subsections
#   NF-3  grep                   — the skill never invokes a remote push

load '../test_helper'

SKILL_DIR="${DOTFILES_ROOT}/claude/skills/obsidian-session-clip"
SAFE_NAME="${SKILL_DIR}/lib/safe-name.sh"
COMMIT_NOTE="${SKILL_DIR}/lib/commit-note.sh"
VERIFY_CLIP="${SKILL_DIR}/lib/verify-clip.sh"
RESOLVE_VAULT="${SKILL_DIR}/lib/resolve-vault.sh"

setup() {
    setup_isolated_home
    SKILL_DIR="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/obsidian-session-clip"
    SAFE_NAME="${SKILL_DIR}/lib/safe-name.sh"
    COMMIT_NOTE="${SKILL_DIR}/lib/commit-note.sh"
    VERIFY_CLIP="${SKILL_DIR}/lib/verify-clip.sh"
    RESOLVE_VAULT="${SKILL_DIR}/lib/resolve-vault.sh"

    WORK="$(mktemp -d)"
}

teardown() {
    if [ -n "${WORK:-}" ] && [ -d "$WORK" ]; then
        rm -rf "$WORK"
    fi
    teardown_isolated_home
}

# Throwaway git repo standing in for the vault. Never the user's real vault.
make_vault() {
    VAULT="${WORK}/vault"
    mkdir -p "${VAULT}/99-Inbox/ai-session"
    git -C "$VAULT" init -q
    git -C "$VAULT" config user.email "test@example.com"
    git -C "$VAULT" config user.name "Test"
    git -C "$VAULT" config commit.gpgsign false
    printf 'seed\n' >"${VAULT}/README.md"
    git -C "$VAULT" add -- README.md
    git -C "$VAULT" commit -q -m "seed"
}

write_note() {
    # write_note <path> [status] [drop-key] [empty-section]
    local path="$1" status="${2:-unprocessed}" drop="${3:-}" empty="${4:-}"
    mkdir -p "$(dirname "$path")"
    {
        echo '---'
        [ "$drop" = "title" ] || echo 'title: 세션 클립 스킬 구현'
        [ "$drop" = "source" ] || echo 'source: https://github.com/dEitY719/dotfiles/issues/1321'
        [ "$drop" = "repo" ] || echo 'repo: dotfiles'
        [ "$drop" = "branch" ] || echo 'branch: wt/issue-1321/1'
        [ "$drop" = "session_type" ] || echo 'session_type: code'
        [ "$drop" = "created" ] || echo 'created: 2026-08-11'
        [ "$drop" = "status" ] || echo "status: ${status}"
        [ "$drop" = "memo" ] || echo 'memo: ai-generated'
        [ "$drop" = "tags" ] || echo 'tags: [ai-session, dotfiles]'
        echo '---'
        echo ''
        echo '## 요약'
        echo ''
        echo '세션 클립 스킬을 만들었다.'
        echo ''
        echo '## 메모'
        echo ''
        echo '### 핵심 요약'
        echo ''
        [ "$empty" = "핵심 요약" ] || echo 'pathspec 한정 커밋이 병렬 세션 안전성의 핵심이다.'
        echo ''
        echo '### 왜 저장했나'
        echo ''
        [ "$empty" = "왜 저장했나" ] || echo '같은 함정을 다음 세션에서 다시 밟지 않으려고.'
        echo ''
        echo '### 액션 아이템'
        echo ''
        [ "$empty" = "액션 아이템" ] || echo '- [ ] vault AGENTS.md 에 clip: 프리픽스 추가'
    } >"$path"
}

# ── NF-1: sanitize ────────────────────────────────────────────────────

@test "NF-1: sanitize strips all 9 Windows-forbidden characters" {
    run bash "$SAFE_NAME" sanitize 'a\b/c:d*e?f"g<h>i|j'
    assert_success
    assert_output 'abcdefghij'
}

@test "NF-1: sanitize strips control characters" {
    run bash "$SAFE_NAME" sanitize "$(printf 'clip\ttab\x07bell\x1besc')"
    assert_success
    assert_output 'cliptabbellesc'
}

@test "NF-1: sanitize truncates to 100 characters" {
    long="$(printf 'a%.0s' $(seq 1 250))"
    run bash "$SAFE_NAME" sanitize "$long"
    assert_success
    [ "${#output}" -eq 100 ]
}

@test "NF-1: sanitize keeps a normal stem untouched" {
    run bash "$SAFE_NAME" sanitize '2026-08-11-1530-dotfiles-session-clip'
    assert_success
    assert_output '2026-08-11-1530-dotfiles-session-clip'
}

@test "NF-1: sanitize fails loudly when nothing survives" {
    run bash "$SAFE_NAME" sanitize '///:::***'
    assert_failure
    [ -n "$output" ]
}

@test "NF-1: sanitize fails loudly on an empty name" {
    run bash "$SAFE_NAME" sanitize ''
    assert_failure
}

# ── F-2: collision resolution ─────────────────────────────────────────

@test "F-2: resolve returns the bare path when nothing collides" {
    run bash "$SAFE_NAME" resolve "$WORK" 'note'
    assert_success
    assert_output "${WORK}/note.md"
}

@test "F-2: resolve appends -2 then -3 on collision" {
    : >"${WORK}/note.md"
    run bash "$SAFE_NAME" resolve "$WORK" 'note'
    assert_success
    assert_output "${WORK}/note-2.md"

    : >"${WORK}/note-2.md"
    run bash "$SAFE_NAME" resolve "$WORK" 'note'
    assert_success
    assert_output "${WORK}/note-3.md"
}

@test "F-2: resolve stops after 10 attempts" {
    : >"${WORK}/note.md"
    for n in 2 3 4 5 6 7 8 9 10; do
        : >"${WORK}/note-${n}.md"
    done
    run bash "$SAFE_NAME" resolve "$WORK" 'note'
    assert_failure
    assert_output --partial '10'
}

# ── NF-2: pathspec-limited commit ─────────────────────────────────────

@test "NF-2: commit-note commits exactly one file amid other dirty files" {
    make_vault
    note="${VAULT}/99-Inbox/ai-session/2026-08-11-1530-dotfiles-clip.md"
    write_note "$note"

    # Noise another parallel session / the user could have left behind.
    printf 'dirty\n' >>"${VAULT}/README.md"
    printf 'other\n' >"${VAULT}/99-Inbox/ai-session/other-session.md"
    printf 'untracked\n' >"${VAULT}/scratch.md"

    run bash "$COMMIT_NOTE" "$VAULT" "$note" '세션 클립 스킬 구현' 'dotfiles'
    assert_success

    run git -C "$VAULT" show --name-only --format='%s' HEAD
    assert_success
    assert_line 'clip: 세션 클립 스킬 구현 (dotfiles)'
    assert_line '99-Inbox/ai-session/2026-08-11-1530-dotfiles-clip.md'
    refute_line --partial 'other-session.md'
    refute_line --partial 'scratch.md'
    refute_line --partial 'README.md'

    # `git show --stat` must list exactly one path (the acceptance criterion).
    run bash -c "git -C '${VAULT}' show --name-only --format='' HEAD | grep -c ."
    assert_output '1'

    # The other files must still be dirty/untracked afterwards.
    run git -C "$VAULT" status --porcelain
    assert_output --partial 'README.md'
    assert_output --partial 'other-session.md'
    assert_output --partial 'scratch.md'
}

@test "NF-2: commit-note accepts a vault-relative note path" {
    make_vault
    rel='99-Inbox/ai-session/relative-note.md'
    write_note "${VAULT}/${rel}"

    run bash "$COMMIT_NOTE" "$VAULT" "$rel" 'relative path' 'dotfiles'
    assert_success

    run git -C "$VAULT" show --name-only --format='' HEAD
    assert_output --partial "$rel"
}

@test "NF-2: commit-note source never uses -a / -A / git add ." {
    # Comments deliberately name the forbidden forms, so audit code lines only.
    code="${WORK}/commit-note.code"
    grep -vE '^[[:space:]]*#' "$COMMIT_NOTE" >"$code"

    run grep -nE 'add[[:space:]]+(-A|--all|\.)|commit[[:space:]].*[[:space:]]-a([[:space:]]|$)' "$code"
    assert_failure

    # ...and both git verbs carry the `--` pathspec separator.
    run grep -cF 'add -- "$rel"' "$COMMIT_NOTE"
    assert_output '1'
    run grep -cF 'commit -q -m "$subject" -- "$rel"' "$COMMIT_NOTE"
    assert_output '1'
}

@test "NF-2: a fake git rejecting -A/-a/. still lets commit-note succeed" {
    make_vault
    note="${VAULT}/99-Inbox/ai-session/guarded.md"
    write_note "$note"

    mkdir -p "${WORK}/bin"
    cat >"${WORK}/bin/git" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    case "$arg" in
        -A | --all | -a | .)
            echo "FORBIDDEN GIT ARG: $arg" >&2
            exit 99
            ;;
    esac
done
exec "$REAL_GIT" "$@"
EOF
    chmod +x "${WORK}/bin/git"
    REAL_GIT="$(command -v git)"
    export REAL_GIT

    run env PATH="${WORK}/bin:${PATH}" bash "$COMMIT_NOTE" "$VAULT" "$note" 'guarded' 'dotfiles'
    assert_success
    refute_output --partial 'FORBIDDEN GIT ARG'

    run git -C "$VAULT" log --oneline -1
    assert_output --partial 'clip: guarded (dotfiles)'
}

@test "NF-2: commit-note retries past a transient .git/index.lock" {
    make_vault
    note="${VAULT}/99-Inbox/ai-session/locked.md"
    write_note "$note"

    lock="${VAULT}/.git/index.lock"
    : >"$lock"
    # obsidian-git releases the index shortly after we start; the backoff
    # loop's second attempt (t = 1s) must succeed.
    (
        sleep 0.5
        rm -f "$lock"
    ) &
    remover=$!

    run bash "$COMMIT_NOTE" "$VAULT" "$note" 'lock retry' 'dotfiles'
    wait "$remover" || true
    assert_success

    run git -C "$VAULT" log --oneline -1
    assert_output --partial 'clip: lock retry (dotfiles)'
}

@test "NF-4: a lock that never clears keeps the note and exits 0" {
    make_vault
    note="${VAULT}/99-Inbox/ai-session/stuck.md"
    write_note "$note"

    : >"${VAULT}/.git/index.lock"

    # Neutralise the backoff so the 5 retries do not really sleep 55s.
    mkdir -p "${WORK}/bin"
    printf '#!/usr/bin/env bash\nexit 0\n' >"${WORK}/bin/sleep"
    chmod +x "${WORK}/bin/sleep"

    run env PATH="${WORK}/bin:${PATH}" bash "$COMMIT_NOTE" "$VAULT" "$note" 'stuck' 'dotfiles'
    assert_success
    assert_output --partial 'index.lock'

    [ -f "$note" ]
    run git -C "$VAULT" log --oneline
    refute_output --partial 'clip: stuck'
}

@test "NF-2: a preempting commit between add and commit is success, not error" {
    make_vault
    note="${VAULT}/99-Inbox/ai-session/preempted.md"
    write_note "$note"

    # obsidian-git got there first.
    git -C "$VAULT" add -- '99-Inbox/ai-session/preempted.md'
    git -C "$VAULT" commit -q -m 'vault backup: preempted' -- '99-Inbox/ai-session/preempted.md'

    run bash "$COMMIT_NOTE" "$VAULT" "$note" 'preempted' 'dotfiles'
    assert_success
    assert_output --partial '이미 반영됨'
}

@test "NF-4: a non-git vault warns and exits 0 with the note intact" {
    plain="${WORK}/plain-vault"
    note="${plain}/99-Inbox/ai-session/plain.md"
    write_note "$note"

    run bash "$COMMIT_NOTE" "$plain" "$note" 'plain' 'dotfiles'
    assert_success
    [ -f "$note" ]
}

# ── verify-clip ───────────────────────────────────────────────────────

@test "verify-clip: PASS on a well-formed note" {
    note="${WORK}/2026-08-11-1530-dotfiles-session-clip.md"
    write_note "$note"

    run bash "$VERIFY_CLIP" "$note"
    assert_success
    assert_output --partial '[OK] verify-clip passed'
}

@test "verify-clip: FAIL when a frontmatter key is missing" {
    note="${WORK}/2026-08-11-1530-dotfiles-missing-key.md"
    write_note "$note" 'unprocessed' 'source'

    run bash "$VERIFY_CLIP" "$note"
    assert_failure
    assert_output --partial '[FAIL]'
    assert_output --partial 'source'
}

@test "verify-clip: FAIL when status is not unprocessed" {
    note="${WORK}/2026-08-11-1530-dotfiles-bad-status.md"
    write_note "$note" 'processed'

    run bash "$VERIFY_CLIP" "$note"
    assert_failure
    assert_output --partial '[FAIL]'
    assert_output --partial 'unprocessed'
}

@test "verify-clip: FAIL on a forbidden character in the filename" {
    note="${WORK}/2026-08-11-1530-dotfiles-bad?name.md"
    write_note "$note"

    run bash "$VERIFY_CLIP" "$note"
    assert_failure
    assert_output --partial '[FAIL]'
    assert_output --partial 'NF-1'
}

@test "verify-clip: FAIL when a memo subsection is empty" {
    note="${WORK}/2026-08-11-1530-dotfiles-empty-memo.md"
    write_note "$note" 'unprocessed' '' '왜 저장했나'

    run bash "$VERIFY_CLIP" "$note"
    assert_failure
    assert_output --partial '[FAIL]'
    assert_output --partial '왜 저장했나'
}

@test "verify-clip: FAIL when the note does not exist" {
    run bash "$VERIFY_CLIP" "${WORK}/nope.md"
    assert_failure
    assert_output --partial '[FAIL]'
}

# ── NF-3: no remote push anywhere in the skill ────────────────────────

@test "NF-3: the skill never invokes a remote push" {
    for f in "${SKILL_DIR}/SKILL.md" "${SKILL_DIR}"/lib/*.sh; do
        run grep -c 'git push' "$f"
        assert_output '0'
    done
}

@test "NF-3: no remote push in references either" {
    run grep -rn 'git push' "$SKILL_DIR"
    assert_failure
}

# ── SKILL.md conventions (NF-5) ───────────────────────────────────────

@test "NF-5: SKILL.md stays within 100 lines" {
    lines="$(wc -l <"${SKILL_DIR}/SKILL.md")"
    [ "$lines" -le 100 ]
}

@test "NF-5: SKILL.md declares the obsidian:session-clip name" {
    run grep -c '^name: obsidian:session-clip$' "${SKILL_DIR}/SKILL.md"
    assert_output '1'
}

@test "F-8: SKILL.md routes -h/--help/help to references/help.md verbatim" {
    run grep -n 'references/help.md` verbatim' "${SKILL_DIR}/SKILL.md"
    assert_success
    [ -f "${SKILL_DIR}/references/help.md" ]
    run grep -c -- '--dry-run' "${SKILL_DIR}/references/help.md"
    refute_output '0'
}

@test "F-8: every reference file the SKILL.md names exists" {
    for f in help.md options.md template-code.md template-research.md frontmatter.md; do
        [ -f "${SKILL_DIR}/references/${f}" ]
    done
}

@test "lib scripts print their own usage on -h" {
    for s in "$SAFE_NAME" "$COMMIT_NOTE" "$VERIFY_CLIP" "$RESOLVE_VAULT"; do
        run bash "$s" -h
        assert_success
        assert_output --partial 'Usage:'
    done
}

# ── resolve-vault: PC-mode-aware vault default (issue #1351) ───────────

@test "resolve-vault: explicit arg wins over env var and mode file" {
    export OBSIDIAN_VAULT_DIR="${WORK}/env-vault"
    printf 'internal\n' >"${HOME}/.dotfiles-setup-mode"

    run bash "$RESOLVE_VAULT" "${WORK}/explicit-vault"
    assert_success
    assert_output "${WORK}/explicit-vault"
}

@test "resolve-vault: OBSIDIAN_VAULT_DIR wins over mode file when no explicit arg" {
    export OBSIDIAN_VAULT_DIR="${WORK}/env-vault"
    printf 'internal\n' >"${HOME}/.dotfiles-setup-mode"

    run bash "$RESOLVE_VAULT"
    assert_success
    assert_output "${WORK}/env-vault"
}

@test "resolve-vault: mode file 'internal' resolves to the company vault" {
    printf 'internal\n' >"${HOME}/.dotfiles-setup-mode"

    run bash "$RESOLVE_VAULT"
    assert_success
    assert_output "${HOME}/para/project/obsidian-para-company"
}

@test "resolve-vault: legacy mode file '2' resolves to the company vault" {
    printf '2\n' >"${HOME}/.dotfiles-setup-mode"

    run bash "$RESOLVE_VAULT"
    assert_success
    assert_output "${HOME}/para/project/obsidian-para-company"
}

@test "resolve-vault: mode file 'external' resolves to the default vault" {
    printf 'external\n' >"${HOME}/.dotfiles-setup-mode"

    run bash "$RESOLVE_VAULT"
    assert_success
    assert_output "${HOME}/para/project/obsidian-para"
}

@test "resolve-vault: mode file 'public' resolves to the default vault" {
    printf 'public\n' >"${HOME}/.dotfiles-setup-mode"

    run bash "$RESOLVE_VAULT"
    assert_success
    assert_output "${HOME}/para/project/obsidian-para"
}

@test "resolve-vault: no mode file resolves to the default vault without crashing" {
    run bash "$RESOLVE_VAULT"
    assert_success
    assert_output "${HOME}/para/project/obsidian-para"
}
