# gh-project-pat

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/gh_project_pat_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic gh_project_pat --force`

## 호출

- Help 진입점: `gh-project-pat-help [section|--list|--all]`
- 통합 라우팅: `my-help gh_project_pat [section]`
- Alias: `gh-project-pat-help`

## 요약 (gh-project-pat-help)

- Usage: gh-project-pat <guide|set|status> [--host HOST] [options]
- 순서: guide (PAT 발급) -> set (dry-run 확인) -> set --apply (등록) -> status (존재 확인)
- sections
    - guide: classic PAT 생성 경로 + project/repo scope
    - set: 여러 저장소에 PROJECT_BOARD_PAT 등록 (기본 dry-run, --apply 로 쓰기)
    - status: 각 저장소의 PROJECT_BOARD_PAT 존재 여부
    - options: --host / --owner / --repo / --repo-pattern / 종료 코드
    - details: gh-project-pat-help <section>  (example: gh-project-pat-help set)

## 섹션

### guide

- URL: https://<host>/settings/tokens/new
- 메뉴: Settings -> Developer settings -> Personal access tokens -> Tokens (classic) -> Generate new token
- fine-grained PAT 생성 화면으로 들어갔다면 왼쪽 메뉴의 Tokens (classic) 으로 이동
1. Note 입력 (예: skills-plugins-board)
2. Expiration 선택 (만료 시 새 PAT 로 set --apply 재실행)
3. scope 선택: project (보드 쓰기) + repo (비공개 이슈/PR 접근)
4. Generate token 클릭
5. 표시된 토큰을 복사 (화면을 떠나면 다시 볼 수 없음)
- 다음: gh-project-pat set --host <host> --owner <owner>  (dry-run)

### set

- **set** — 대상/개수만 표시 (dry-run) — PAT 입력/쓰기 없음
- **set --apply** — PAT 를 TTY 에서 한 번 숨김 입력 -> 각 repo 에 등록 — gh secret set 의 stdin 으로만 전달
- 예: gh-project-pat set --host github.com --owner <owner> --apply
- 예: gh-project-pat set --repo <owner>/repo-a --repo <owner>/repo-b --apply
- 한 repo 실패가 나머지를 막지 않음 -> 마지막에 성공/실패 합계, 실패가 있으면 종료 코드 1
- 재실행은 같은 secret 을 갱신하므로 수렴. 중단돼도 이미 쓴 secret 은 rollback 하지 않음
- TTY 없음 / 빈 입력 / Ctrl-C 는 secret 을 쓰기 전에 종료
- PAT 는 인자/환경변수/출력/파일에 남기지 않음. gh auth token 등 다른 토큰을 대신 쓰지 않음

### status

- **status** — 각 repo 의 PROJECT_BOARD_PAT 존재 여부 — gh secret list 메타데이터만 조회
- 예: gh-project-pat status --host github.com --owner <owner>
- 존재는 PAT 의 scope/만료나 board-sync 성공을 보증하지 않음 -> workflow 실행으로 별도 확인
- 누락 또는 조회 오류가 하나라도 있으면 종료 코드 1

### options

- **--host HOST** — 대상 GitHub host — 생략 시 _gh_resolve_host (setup mode 기반)
- **--owner OWNER** — 저장소 owner — 생략 시 host 의 인증 사용자
- **--repo OWNER/REPO** — 대상 직접 지정 (반복 가능) — owner 불일치는 입력 오류
- **--repo-pattern P** — 저장소 이름 glob (기본 *-skills) — --repo 와 동시 사용 불가
- **--dry-run | --apply** — set 의 쓰기 여부 (기본 dry-run) — 동시 지정은 입력 오류
- 비공개 저장소 포함, 목록은 마지막 페이지까지 조회
- 종료 코드: 0 정상 | 1 일부 실패/누락/대상 0개/TTY 없음 | 2 잘못된 옵션/host/owner
- 요구: gh (대상 host 에 gh auth login --hostname HOST), python3

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/gh-project-pat.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/gh_project_pat_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
