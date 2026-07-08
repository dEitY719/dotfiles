# 배포 워크플로우 (upstream → origin/main → dev/prod)

fork 저장소(사내 fork ↔ 공개 upstream) 및 일반 저장소의 dev/prod 배포에 대한 **근거와 맥락**.
복붙 가능한 실제 명령어 순서는 셸에서 조회한다:

- `git-help deploy` — dev 배포 (upstream → origin/main → dev)
- `git-help release` — prod 릴리스 (dev 흐름 + tag + prod)
- `git-help release-artifacts` — 릴리스 산출물 체크리스트 (프로젝트별)
- `git-help rollback` — 태그 기반 롤백
- `git-help pitfalls` — 실측 함정 요약
- `git-help principles` — 핵심 원칙 3

## 판단 정정 2가지

### 1. Fork sync 는 merge 가 정답 (rebase 아님)

- `origin/main` 은 이미 push 된 공용 브랜치 → rebase 는 히스토리 재작성이라 force-push 필요, 협업자 로컬 파손.
- Merge 는 upstream 커밋 출처 보존 (`git log --graph` 로 추적 가능).
- 매 sync 마다 rebase 하면 fork-only 커밋 SHA 변경 → 발급된 태그·PR reference 가 stale.
- rebase 가 맞는 경우는 별개: 첫 push 전 로컬 feature 브랜치를 최신 main 위로 얹을 때 (fork sync 아님).

### 2. 배포는 브랜치 push 가 아니라 `gh workflow run`

- 과거 관례(`origin/dev-server`·`origin/prod-server` 브랜치 push → 자동 배포)는 폐기됨.
- `dev-deploy.yml` / `prod-deploy.yml` 은 `push:` 트리거 제거, `workflow_dispatch` 전용.
- 따라서 배포는 항상 `gh workflow run`.

## 핵심 원칙 3 (상세)

1. **Fork sync = merge, rebase 금지** — 판단 정정 1 참조.
2. **배포 = `gh workflow run`, branch push 아님** — 판단 정정 2 참조.
3. **prod=태그, dev=main** — 태그는 롤백 좌표·release 좌표·감사 로그의 근거. prod 배포는
   `-f ref=<TAG>` 로 태그를 직접 지정한다(실행 ref 가 main 이어도 checkout 은 태그).

## 함정 전체표 (실측 기반)

| 함정 | 대응 | 맥락 |
| --- | --- | --- |
| `git merge upstream/main` 시 ruff format drift | `uv run --project <PKG> ruff format <파일>` 재포맷 후 재커밋 | upstream 이 CI ruff 버전을 pin 안 해 로컬과 포맷 drift |
| pytest 게이트에서 env 상속 실패 | `env -u HTTP_PROXY -u http_proxy -u HTTPS_PROXY -u https_proxy -u NO_PROXY -u no_proxy` 후 실행 | shell 프록시 env 가 테스트에 상속되어 sanitize 테스트 실패 |
| prod SSH 인증 실패 | `PROD_SSH=<PROD_SSH_ALIAS>` (`~/.ssh/config` devops 별칭) 사용 | psql 접근은 devops 계정 별칭 필요 |
| dev-deploy rolling 걱정 | dev-deploy 는 rolling 개념 없음. `no_cache`·`reset_db` 만 유효 | dev/prod workflow 옵션 상이 |
| 배포 커밋과 태그 어긋남 | `gh workflow run prod-deploy.yml -f ref=<TAG>` 로 태그 직접 지정 | 실행 ref 가 main 이어도 checkout 은 태그 |
| 릴리스 후 nonce_missing | 저장소 variable `APP_BASE_URL` 이 신 도메인인지 확인, 옛 도메인이면 갱신 + 재배포 | 공지·링크 도메인이 옛 URL |

## 릴리스 산출물 상세

`git-help release-artifacts` 의 각 항목이 왜 필요한지 (예시는 monorepo 구조 기준):

- **version bump** — 푸터 버전 표기의 유일 소스(예: `apps/web/vite.config.ts` 의 `APP_VERSION`). 사후검증에서 이 값으로 배포 확인.
- **release notes** — `docs/public/release-notes/<TAG>.md` 신설 + `README.md` 최상단 링크. 사용자 공개 변경 이력.
- **인앱 공지** — 본문 JSON 을 리포 밖(예: `/tmp/announcement.json`)에 작성 후, 배포 성공 뒤 psql 로 INSERT. psql 접근에 `PROD_SSH=<PROD_SSH_ALIAS>` 필요.
- 프로젝트마다 파일 경로/개수는 다르다 — 위는 예시일 뿐, 각 프로젝트 값으로 치환.

## 사후검증

- 푸터에 `<TAG>` 표시 확인 (`https://<PROD_DOMAIN>/`).
- 첫 진입 시 공지 팝업 노출 확인.
- prod api 로그 무이상: `ssh <PROD_SSH_ALIAS> "docker logs <PROD_API_CONTAINER> --since 10m --tail 50"`.

## 실측 근거

2026-07-08 v2.1.0 릴리스: upstream/main 20커밋 merge → tag v2.1.0 → rolling prod-deploy → 공지 INSERT 전체 흐름 성공.

## Legacy: `sync-to-deploy` (폐기)

`sync-to-deploy` / `sync-to-deploy-help` 는 구식 branch-push 자동배포(deploy 브랜치에 force-with-lease push). 사내 fork 에서 push 트리거가 제거되어 폐기됨. 신규 프로젝트는 `git-help deploy` / `git-help release` 의 `gh workflow run` 방식을 사용한다.
