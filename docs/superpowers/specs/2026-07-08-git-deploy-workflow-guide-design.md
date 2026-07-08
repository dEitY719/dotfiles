# Design Spec: 범용 git 배포 워크플로우 가이드 (`git-help` 확장)

- **Date:** 2026-07-08
- **Issue:** #1128 (`docs(release): upstream → origin/main → dev/prod 배포 git 명령어 가이드`)
- **Status:** Approved (brainstorming 완료, writing-plans 대기)
- **Branch:** `wt/issue-1128/1`

## 1. 배경 & 목표

사용자는 여러 프로젝트에서 **유사한 방식**으로 dev/prod 배포를 수행한다. 매 프로젝트 전용
스크립트 대신, **범용 git/gh 명령어를 사용자가 직접 실행**하는 편이 AI 도움 없이 토큰을
아끼고 빠르다. 따라서 `git-help <section>` 을 실행하면 배포 **일련의 과정이 복붙 가능한
순서로 보이고 그대로 따라 할 수 있는** 가이드를 만든다.

원천 자료는 #1128 (2026-07-08 v2.1.0 릴리스 실측: upstream/main 20커밋 merge → tag
v2.1.0 → rolling prod-deploy → 공지 INSERT). 이 실측 절차를 `<PLACEHOLDER>` 기반으로
일반화한다.

**한 줄 목표:** #1128 의 fork-sync → dev/prod 배포 절차를 placeholder 기반 범용 가이드로
만들어 기존 `git-help` 명령의 신규 섹션으로 노출한다.

## 2. Non-Goals (YAGNI)

- 자동화 스크립트(`prod-release.sh` 류) 이식 — 가이드는 "읽고 따라 하는" 것이지 orchestrator 가 아니다.
- 프로젝트 감지/adaptive 로직(docker-help `here` 류).
- 배포 방식 분기(legacy branch-push). 기존 `sync-to-deploy` / `sync_to_deploy_help` 는
  **손대지 않는다**(별도 이슈 여지). 문서에서 "폐기됨"만 명시.
- 여러 배포 스타일 카탈로그화 — 사용자 프로젝트는 "유사한 방식"이므로 단일 표준 흐름으로 충분.

## 3. 확정된 결정 (brainstorming Q&A 결과)

| # | 결정 | 근거 |
|---|------|------|
| 1 | 표면 = 기존 `git-help` 하위 섹션 | 사용자 "git-help xxx" 표현과 일치, git 우산 아래 유지 |
| 2 | Phase 0(origin/main 최신화)을 **선택 프리루드**로 분리: fork=`merge upstream/main`, 일반=`pull --ff-only` | fork/비-fork 프로젝트 모두 커버, 가장 범용적 |
| 3 | 섹션 6개: `deploy` `release` `release-artifacts` `rollback` `pitfalls` `principles` | #1128 4덩어리 + rollback(신규) + artifacts 분리 |
| 4 | 치환값 = **angle-bracket placeholder + 각 섹션 상단 범례표** | 설정 0, 세션 오염 없음, #1128 스타일 |
| 5 | release = 범용 스켈레톤, 프로젝트-특화 산출물은 `release-artifacts` 별도 섹션 | 재사용성 ↑, release 흐름 깔끔 |
| 6 | 형태 = 코드(quick steps) + `docs/guide/deploy-workflow.md`(근거) 병행 | 명령어는 명령으로, 근거는 문서로 |
| a | 언어: **Phase 라벨 영어 + 주석/설명 한글** | 기존 git_help(영어) + #1128(한글) 절충 |
| b | 문서 경로: `docs/guide/deploy-workflow.md` | 기존 `docs/guide/team-git.md` 와 동급 |

## 4. 산출물 (3개) & SSOT 경계

| # | 파일 | 역할(SSOT) |
|---|------|-----------|
| A | `shell-common/functions/git_help.sh` (수정) | **명령어 순서(steps)의 SSOT** |
| B | `docs/guide/deploy-workflow.md` (신규) | **근거(why)의 SSOT** |
| C | `tests/integration/test_help_topics.py` (+필요시 `test_help_compact_policy.py`) | 회귀 방지 |

**Drift 방지 규칙 (2곳 유지의 핵심):**
- 명령어 시퀀스 = **코드에만**. 문서는 명령어를 재나열하지 않고 `git-help <section>` 을 가리킨다.
- 근거·서술 = **문서에만**. 코드 각 섹션 footer 는 `근거·상세: docs/guide/deploy-workflow.md` 포인터만.
- pitfalls/principles/release-artifacts 는 코드=한 줄 요약, 문서=전체 서술의 의도적 요약/상세 분리.
- 대원칙: **"단계·명령어는 코드가 SSOT, 설명은 문서가 SSOT."**

## 5. 공용 치환값(placeholder) 범례

각 섹션 상단에 그 섹션에서 쓰는 것만 추려 `ux_section "치환값(placeholder)"` + `ux_table_row` 로 표기.

| placeholder | 의미 | 예시 |
|-------------|------|------|
| `<DEV_WORKFLOW>` | dev 배포 workflow 파일 | `dev-deploy.yml` |
| `<PROD_WORKFLOW>` | prod 배포 workflow 파일 | `prod-deploy.yml` |
| `<REPO_COORD>` | `gh --repo` 좌표 `<GHE_HOST>/<ORG>/<REPO>` | `github.example.net/org/repo` |
| `<TAG>` | 릴리스 태그 | `v2.1.0` |
| `<PREV_TAG>` | 롤백 대상 이전 태그 | `v2.0.3` |
| `<DEPLOY_STRATEGY>` | prod 배포 전략 | `rolling` \| `recreate` |
| `<PROD_SSH_ALIAS>` | prod SSH 별칭(로그/psql) | `~/.ssh/config` 의 devops 별칭 |
| `<TEST_CMD>` | 릴리스 게이트 테스트 명령 | `uv run pytest -q` |
| `<RELEASE_FILES>` | 릴리스 커밋에 스테이징할 파일들 | version bump + release notes |

## 6. 섹션별 목표 내용 (구현용 초안)

> 렌더링: 단계 헤더 = `ux_section`; 명령어 라인 = **bare `printf '  %s\n'`**
> (복붙 verbatim 요구 — `_docker_help_recommend_print`/`_docker_help_raw` 선례, 정당화 주석 포함);
> 주석/포인터 = `ux_bullet`/`ux_info`. SSOT: `_git_help_rows_<section>()` 를
> `_git_help_full()` 와 `_git_help_section_rows()` 가 공유.

### 6.1 `deploy` (요구사항 1)
```
치환값: <DEV_WORKFLOW>, <REPO_COORD>
[Phase 0] Refresh origin/main
  # fork repo (사내 fork <-> 공개 upstream):
  git checkout main
  git fetch --all --prune
  git merge upstream/main          # 충돌/ruff drift → git-help pitfalls
  git push origin main
  # plain repo (upstream 없음):
  git checkout main
  git pull --ff-only
[Phase 1] Trigger dev deploy
  gh workflow run <DEV_WORKFLOW> --repo <REPO_COORD> -f ref=main
  # optional: -f no_cache=true  (Docker 강제 재빌드)
  # optional: -f reset_db=true  (DB 볼륨 초기화 — 데이터 삭제 주의)
[Phase 2] Check status
  gh run list --workflow=<DEV_WORKFLOW> --repo <REPO_COORD> --limit 3
footer: 근거·상세: docs/guide/deploy-workflow.md
```

### 6.2 `release` (요구사항 2, 범용 스켈레톤)
```
치환값: <PROD_WORKFLOW>, <REPO_COORD>, <TAG>, <DEPLOY_STRATEGY>, <PROD_SSH_ALIAS>, <TEST_CMD>, <RELEASE_FILES>
[Phase A] Refresh origin/main       -> git-help deploy 의 Phase 0 과 동일
[Phase B] Update release artifacts   -> git-help release-artifacts (프로젝트별)
[Phase C] Gate -> commit -> tag -> push -> deploy -> verify
  # C-1. test gate (프록시 env 오염 시 → git-help pitfalls)
  <TEST_CMD>
  # C-2. stage release artifacts only (다른 워킹트리 변경 넣지 말 것)
  git add <RELEASE_FILES>
  # C-3. commit + annotated tag
  git commit -m "release(<TAG>): ..."
  git tag -a <TAG> -m "<TAG>"
  # C-4. push tag first, then main
  git push origin <TAG>
  git push origin main
  # C-5. prod deploy (태그 직접 지정)
  gh workflow run <PROD_WORKFLOW> --repo <REPO_COORD> -f ref=<TAG> -f deploy_strategy=<DEPLOY_STRATEGY>
  #   rolling: 무중단 / recreate: down->up (파괴적 migration)
  # C-6. watch
  gh run list --workflow=<PROD_WORKFLOW> --repo <REPO_COORD> --limit 3
  gh run watch <run-id> --repo <REPO_COORD>
  # C-7. 사후검증: 푸터 <TAG> 표시 / prod 로그 무이상
  ssh <PROD_SSH_ALIAS> "docker logs \$(docker ps --format '{{.Names}}' | grep prod-api) --since 10m --tail 50"
footer: 공지 등 후처리 → git-help release-artifacts / 근거 → docs
```

### 6.3 `release-artifacts` (프로젝트-특화 체크리스트; 예시 = #1128 monorepo)
```
프로젝트별 릴리스 산출물 (예시 — 실제 파일은 프로젝트마다 상이):
  - version bump (버전 표기 단일 소스)     예: apps/web/vite.config.ts 의 APP_VERSION
  - release notes 신설                      예: docs/public/release-notes/<TAG>.md
  - release notes 목록 최상단 링크 추가     예: docs/public/release-notes/README.md
  - 인앱 공지 본문 작성 (리포 밖)           예: /tmp/announcement.json
  - (배포 성공 후) 공지 등록 — psql 접근    예: PROD_SSH=<PROD_SSH_ALIAS> <release-script> ...
  주의: 도메인 variable(APP_BASE_URL 등) 최신인지 확인 (옛 도메인 → 로그인 nonce_missing)
footer: 근거·상세: docs/guide/deploy-workflow.md
```

### 6.4 `rollback` (신규 — 원칙3 "태그=롤백 좌표"에서 도출)
```
치환값: <PROD_WORKFLOW>, <REPO_COORD>, <PREV_TAG>
1) 이전 태그 확인:
   git tag --sort=-v:refname | head
   gh release list --repo <REPO_COORD>
2) 이전 태그로 prod 재배포:
   gh workflow run <PROD_WORKFLOW> --repo <REPO_COORD> -f ref=<PREV_TAG> -f deploy_strategy=rolling
3) watch + 사후검증:
   gh run watch <run-id> --repo <REPO_COORD>
주의: 파괴적 DB migration 이 있었다면 코드 롤백만으로 복구 안 됨 → recreate + DB 복구 별도
footer: 근거·상세: docs/guide/deploy-workflow.md
```

### 6.5 `pitfalls` (한 줄 요약표 + 문서 포인터)
```
| 함정 | 대응 |
| upstream merge 시 ruff format drift | uv run --project <PKG> ruff format <파일> 재커밋 |
| pytest 게이트 프록시 env 오염 | env -u HTTP_PROXY -u http_proxy -u HTTPS_PROXY -u https_proxy -u NO_PROXY -u no_proxy 로 실행 |
| prod SSH 사용자명 인증 실패 | PROD_SSH=<PROD_SSH_ALIAS> (~/.ssh/config 별칭) 사용 |
| dev-deploy rolling 옵션 없음 | dev 는 no_cache/reset_db 만 유효 |
| 배포 커밋과 태그 불일치 | prod 는 -f ref=<TAG> 로 태그 직접 지정 |
| 릴리스 후 nonce_missing | APP_BASE_URL variable 이 신 도메인인지 확인 후 재배포 |
footer: 전체 함정·맥락: docs/guide/deploy-workflow.md
```

### 6.6 `principles` (핵심 원칙 3)
```
1) Fork sync = merge (rebase 금지) — origin/main 은 공용 브랜치, force-push/SHA 변경/stale tag 회피
2) 배포 = gh workflow run (branch push 아님) — 폐기된 dev-server/prod-server 브랜치 무시
3) prod=태그(-f ref=<TAG>), dev=main — 태그는 롤백·release·감사 로그의 좌표
footer: 근거 상세: docs/guide/deploy-workflow.md
```

## 7. 디스패처 배선 (`git_help.sh`)

1. **row 함수 추가:** `_git_help_rows_deploy`, `_git_help_rows_release`,
   `_git_help_rows_release_artifacts`, `_git_help_rows_rollback`,
   `_git_help_rows_pitfalls`, `_git_help_rows_principles`.
   (명령어 라인은 bare `printf`, 근거 주석 1줄 동반.)
2. **`_git_help_section_rows` case 확장:**
   `deploy) | release) | release-artifacts|artifacts) | rollback) | pitfalls) | principles)`.
3. **`_git_help_full`(--all):** 6개 `_git_help_render_section` 호출 추가.
4. **`_git_help_list_sections`(--list):** 6개 `ux_bullet_sub` 추가 (줄 수 제한 없음).
5. **`_git_help_summary`(기본, ≤15줄 제약):** 현재 13줄. deploy-family 를 **1줄로 묶어** 추가:
   ```sh
   ux_bullet_sub "deploy: deploy | release | release-artifacts | rollback | pitfalls | principles"
   ```
   → 14줄 (개별 6줄 추가는 19줄 → `test_default_help_within_15_lines` 위반이므로 묶기 필수).

## 8. 문서 `docs/guide/deploy-workflow.md` 구조

명령어 재나열 없이 **근거·맥락 SSOT**:
1. 개요 + `git-help deploy|release|rollback` 로 실제 명령을 조회하라는 안내.
2. 판단 정정 2가지 (merge vs rebase / branch-push 폐기 → gh workflow run).
3. 핵심 원칙 3 상세.
4. 함정 전체표(대응 + 실측 맥락).
5. release-artifacts 상세(각 산출물이 왜 필요한지 + #1128 monorepo 예시).
6. 실측 근거(2026-07-08 v2.1.0).
7. legacy `sync-to-deploy` 폐기 메모.

## 9. 테스트

- 기존 `git_help` 은 두 test 파일 `HELP_TOPICS` 목록에 이미 포함 → 15줄·표준 인터페이스 자동 회귀.
- **신규 추가** (bash+zsh): `git_help deploy|release|release-artifacts|rollback|pitfalls|principles`
  가 exit 0 + 비어있지 않은 출력. 내용 assertion 최소 1개 (예: `git_help deploy` 출력에
  `gh workflow run` 포함, `git_help principles` 에 `merge` 포함).
- `mise run lint`(shellcheck/shfmt) + `mise run test` 통과.
- 주의: `printf` 라인의 snake_case 문자열이 pre-commit `naming_check` 에 오탐될 수 있음 →
  docker-help 처럼 guard 주석/형태 조정으로 회피.

## 10. #1128 처리

이 작업이 #1128 을 구현. 후속 PR 이 `Closes #1128`. `sync-to-deploy`(legacy branch-push)는
코드 무수정, 문서에 폐기만 명시.

## 11. 구현 순서 개요 (writing-plans 로 상세화)

1. `git_help.sh` 에 6개 row 함수 + 디스패처/summary/list/full 배선.
2. `docs/guide/deploy-workflow.md` 작성 + 각 섹션 footer 포인터 확인.
3. 테스트 추가/갱신.
4. `mise run lint` + `mise run test` 통과.
5. 커밋(gh:commit) → PR(gh:pr) → #1128 close. (사용자 워크플로우: 직접 커밋 금지, 스킬 경유.)
