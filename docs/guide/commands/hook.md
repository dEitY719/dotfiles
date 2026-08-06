# hook

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/hook_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic hook --force`

## 호출

- Help 진입점: `hook-help [section|--list|--all]`
- 통합 라우팅: `my-help hook [section]`
- Alias: `hook-help`

## 요약 (hook-help)

- Usage: hook-help [section|--list|--all]
- sections
    - overview: 2-tier (user + project) | 자동 진단 | HOOK_WORKFLOW.md
    - commands: hook-check | hook-check --help
    - results: ✓ 정상 | ✗ 오류 | ⚠ 경고
    - trouble: hook 안 됨 | hooksPath | 권한 | 재실행
    - types: User-level | Project-level
    - more: HOOK_WORKFLOW.md | global-hooks | hook-config | setup.sh
    - tips: 주기적 점검 | 새 PC 셋업 | GIT_HOOKS_DEBUG
    - details: hook-help <section>  (example: hook-help commands)

## 섹션

### overview

- 2-tier Hook 아키텍처: User-level (전역) + Project-level (로컬)
- 자동 진단 도구로 설정 문제를 쉽게 해결
- 상세 가이드: git/doc/HOOK_WORKFLOW.md

### commands

- **hook-check** — Hook 설정 진단 ⭐ — 6가지 자동 체크 + 자동 수정 옵션
- **hook-check --help** — 도움말 보기 — 이 페이지 표시

### results

- ✓ = 설정 정상
- ✗ = 설정 오류 (수정 필요)
- ⚠ = 경고 (선택적)

### trouble

- **Hook이 실행 안 됨** — hook-check 실행 — 자동 진단 및 수정
- **core.hooksPath 오류** — git config 명령 직접 실행
- **권한 오류** — chmod +x 명령 실행 — Hook 파일을 실행 가능하게
- **설정 전부 다시** — setup.sh 재실행 — cd ~/dotfiles && ./git/setup.sh

### types

- **User-level** — ~/.config/git/hooks/pre-commit — 모든 git 프로젝트에 적용 (전역)
- **Project-level** — dotfiles/.git/hooks/pre-commit — 이 dotfiles 프로젝트에만 적용

### more

- 자세한 가이드: git/doc/HOOK_WORKFLOW.md
- Hook 구현: git/global-hooks/pre-commit
- Hook 설정값: git/config/hook-config.sh
- Setup 스크립트: git/setup.sh

### tips

- hook-check를 주기적으로 실행해서 설정 상태 확인
- 새 PC에서는 반드시 ./git/setup.sh 실행
- Hook 문제 발생 시 GIT_HOOKS_DEBUG=1 환경변수로 디버그 출력

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/hook.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/hook_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
