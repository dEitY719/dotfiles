# gitignore-pr

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/gitignore_pr_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic gitignore_pr --force`

## 호출

- Help 진입점: `gitignore-pr-help [section|--list|--all]`
- 통합 라우팅: `my-help gitignore_pr [section]`
- Alias: `gitignore-pr-help`

## 요약 (gitignore-pr-help)

- Usage: gitignore-pr-help [section|--list|--all]
- sections
    - usage: gitignore-pr <pattern>... | no args lists untracked
    - flow: origin/<default> branch | commit | push | PR | switch back
    - safety: dirty tree | branch exists | hook/push/PR failure
    - example
    - details: gitignore-pr-help <section>  (example: gitignore-pr-help flow)

## 섹션

### usage

- gitignore-pr                   # list untracked entries, change nothing
- gitignore-pr <pattern>...      # add to repo-root .gitignore and open a PR
- An existing directory gets a trailing / (.omo -> .omo/); anything else is added as typed
- Patterns are root-relative: written to the repo-root .gitignore as given (./ and <root>/ stripped), even when run from a subdirectory
- Only the root .gitignore of origin/<default> is checked; the PR always targets origin (a fork's origin gets the PR, not upstream)
- Rejected: patterns containing a newline or starting with #

### flow

1. Check: git repo, gh CLI, origin is a GitHub remote, no staged/unstaged changes
2. Skip patterns already in origin/<default>'s .gitignore (.omo and .omo/ are the same)
3. Create chore/gitignore-<slug> from origin/<default>, not from the current branch
4. Commit 'chore: ignore <patterns>', push to origin, gh pr create --repo <host>/<owner>/<repo>
5. Switch back to the branch you started on (success or failure)

### safety

- Fails on any staged/unstaged change, including .gitignore — untracked files are fine
- Fails if chore/gitignore-<slug> already exists locally or on origin (never overwrites)
- No force-push, no --no-verify: a failing hook stops the run and the empty branch is deleted
- Push or PR failure keeps the branch and commit and prints the retry command

### example

- gitignore-pr .omo .superpowers   # -> chore/gitignore-omo-superpowers

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/gitignore-pr.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/gitignore_pr_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
