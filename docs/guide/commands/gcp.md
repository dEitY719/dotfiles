# gcp

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/gcp.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic gcp --force`

## 호출

- Help 진입점: `gcp-help [section|--list|--all]`
- 통합 라우팅: `my-help gcp [section]`
- Alias: `gcp-help`

## 요약 (gcp-help)

- Usage: gcp help [section|--list|--all]
- sections
    - scan    gcp scan [base] [src] [--author=<name|all>]   compare & cherry-pick missing commits
    - theirs  gcp theirs <commit>...                         cherry-pick with -X theirs (incoming wins)
    - ours    gcp ours <commit>...                           cherry-pick with -X ours (current wins)
    - author  gcp author <range> [author]                    cherry-pick commits by author
    - pick    gcp pick <commit>...                           bare cherry-pick (one or more)
    - details gcp help <section>  (example: gcp help scan)

## 섹션

### scan

- **syntax** — gcp scan [base] [src] [--author=<name|all>] — Compare & pick missing commits
- **default** — main <- upstream/main, author=dEitY719 — Filter by author by default
- **--author=all** — show all authors — Bypass filter
- **behavior** — same subject -> patch-id compared — Skip confirmed only on an identical patch (issue #1136)
- **behavior** — always individual cherry-pick — range shortcut removed in #913; Suggested Range is a manual hint
- **--show-skip-list** — print known-resolved SHAs — git/config/gcp-scan-skip.conf (issue #1039)
- **skip list** — registered SHAs skipped silently — ignored under --author=all
- **--show-skip-paths** — print path-excluded paths — git/config/gcp-scan-skip-paths.conf
- **skip paths** — commits touching only listed paths skipped — ignored under --author=all
- **behavior** — unpredicted conflict -> rolled back, batch continues — reported under Needs manual resolution (issue #1647)
- **--stop-on-conflict** — abort whole remaining batch on first conflict — legacy all-or-nothing behavior

### theirs

- **syntax** — gcp theirs <commit>... — Cherry-pick with -X theirs
- **conflict** — incoming (cherry-picked) changes win

### ours

- **syntax** — gcp ours <commit>... — Cherry-pick with -X ours
- **conflict** — current branch changes win

### author

- **syntax** — gcp author <range> [author] — Cherry-pick commits by author
- **default author** — dEitY719
- **range format** — <start>..<end> or <start>^..<end>

### pick

- **syntax** — gcp pick <commit>... — Bare cherry-pick (one or more)
- **note** — replaces deprecated bare 'gcp <commit>' — bare form bridges with deprecation warning

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/gcp.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/gcp.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
