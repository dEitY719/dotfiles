# 범용 git 배포 워크플로우 가이드 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** #1128 의 fork-sync → dev/prod 배포 실측 절차를 placeholder 기반 범용 가이드로 만들어, 기존 `git-help` 명령의 6개 신규 섹션(`deploy` `release` `release-artifacts` `rollback` `pitfalls` `principles`)과 근거 문서로 노출한다.

**Architecture:** 기존 `git_help` 디스패처(command-guidelines SSOT 패턴: row 함수 → `--all` 렌더러 + 단일 섹션 조회가 공유)를 확장한다. 명령어 순서는 셸 함수가 SSOT, 근거·맥락은 `docs/guide/deploy-workflow.md` 가 SSOT. 두 곳은 서로 명령어/설명을 재나열하지 않고 포인터로만 연결(drift 방지).

**Tech Stack:** POSIX sh (bash+zsh 양쪽 소싱), `ux_lib` 출력 함수, pytest 통합테스트(`tests/integration/`), mise 태스크(lint/test).

## Global Constraints

- POSIX 호환: `[ ]`(not `[[ ]]`), `>/dev/null 2>&1`(not `&>`), `source "${SHELL_COMMON}/..."` 형태만.
- 모든 출력 파일 상단 인터랙티브 가드 유지: `case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac` (git_help.sh 에 이미 존재).
- 출력은 `ux_lib` 함수 사용. **예외:** 복붙-verbatim 명령어 라인은 bare `printf '  %s\n'` (ux_lib 에 코드-라인 헬퍼 없음 — `_docker_help_recommend_print`/`_docker_help_raw` 선례). `echo` 는 금지(`ux_usage_check`).
- 이모지 전면 금지.
- **기본 help 출력(`git-help` 무인자)은 ≤15줄** (`test_help_compact_policy.py::test_default_help_within_15_lines`). 현재 13줄 → 신규 요약은 **정확히 1줄**만 추가.
- 언어: Phase/섹션 라벨은 영어, 주석·설명은 한글.
- 표준 인터페이스 유지: `git-help`(요약) / `--list` / `--all` / `<section>`.
- `naming_check` 회피: 명령어 literal 은 **작은따옴표**로, 정의 함수명을 큰따옴표 문자열에 넣지 않는다.
- lint/test 실패 시 `--no-verify` 금지, 근본 원인 수정.

---

## File Structure

- `shell-common/functions/git_help.sh` (수정) — `_git_help_cmd` 헬퍼 + 6개 row 함수 + 디스패처/summary/list/full 배선. **명령어 순서 SSOT.**
- `docs/guide/deploy-workflow.md` (신규) — 판단정정·원칙·함정·산출물·실측근거·legacy 메모. **근거 SSOT.**
- `tests/integration/test_help_topics.py` (수정) — 신규 섹션 회귀 테스트.

---

## Task 1: git_help.sh 에 배포 워크플로우 6개 섹션 추가

**Files:**
- Modify: `shell-common/functions/git_help.sh`
- Test: `tests/integration/test_help_topics.py`

**Interfaces:**
- Consumes: `ux_section`, `ux_table_row`, `ux_bullet`, `ux_info`, `ux_header` (ux_lib); 기존 `_git_help_render_section`, `_git_help_section_rows`, `_git_help_summary`, `_git_help_list_sections`, `_git_help_full`, `git_help`.
- Produces: 새 private 함수 `_git_help_cmd`, `_git_help_rows_deploy`, `_git_help_rows_release`, `_git_help_rows_release_artifacts`, `_git_help_rows_rollback`, `_git_help_rows_pitfalls`, `_git_help_rows_principles`. `git-help deploy|release|release-artifacts|rollback|pitfalls|principles` 사용 가능.

- [ ] **Step 1: 실패하는 테스트 추가**

`tests/integration/test_help_topics.py` 맨 끝에 아래 클래스를 추가:

```python
class TestGitDeployHelpSections:
    """git-help deploy/release workflow sections (issue #1128)."""

    GIT_DEPLOY_SECTIONS = [
        "deploy",
        "release",
        "release-artifacts",
        "rollback",
        "pitfalls",
        "principles",
    ]

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    @pytest.mark.parametrize("section", GIT_DEPLOY_SECTIONS)
    def test_section_callable(self, shell_runner, shell, section):
        """Each new git-help section exits 0 with non-empty output."""
        result = shell_runner(shell, f"git_help {section}")
        assert result.exit_code == 0, f"{shell}: git_help {section} failed"
        assert result.stdout.strip(), f"{shell}: git_help {section} produced no output"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_deploy_uses_workflow_run(self, shell_runner, shell):
        result = shell_runner(shell, "git_help deploy")
        assert "gh workflow run" in result.stdout, f"{shell}: deploy missing 'gh workflow run'"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_release_has_annotated_tag_step(self, shell_runner, shell):
        result = shell_runner(shell, "git_help release")
        assert "git tag -a" in result.stdout, f"{shell}: release missing annotated tag step"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_principles_mentions_merge(self, shell_runner, shell):
        result = shell_runner(shell, "git_help principles")
        assert "merge" in result.stdout.lower(), f"{shell}: principles missing merge rule"
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `pytest tests/integration/test_help_topics.py::TestGitDeployHelpSections -q`
Expected: FAIL — `git_help deploy` 등이 "Unknown git-help section" 으로 exit 1 (또는 content assertion 실패).

- [ ] **Step 3: `_git_help_cmd` 헬퍼 + 6개 row 함수 추가**

`shell-common/functions/git_help.sh` 의 `_git_help_notes_pick_strategy()` 정의 **직후**(즉 `_git_help_render_section` 정의 앞)에 아래를 삽입:

```sh
# Bare printf for copy-paste-verbatim command lines. ux_lib has no
# plain-text/code-line helper and the deploy guide requires the user to
# paste each command verbatim (same rationale as docker-help #777's
# _docker_help_recommend_print). Callers pass single-quoted literals so
# the pre-commit naming_check never mis-reads them as function refs.
_git_help_cmd() {
    printf '  %s\n' "$1"
}

_git_help_rows_deploy() {
    ux_section "치환값 (placeholder)"
    ux_table_row "<DEV_WORKFLOW>" "예: dev-deploy.yml" "dev 배포 workflow 파일"
    ux_table_row "<REPO_COORD>" "예: github.example.net/org/repo" "gh --repo 좌표 <GHE_HOST>/<ORG>/<REPO>"

    ux_section "[Phase 0] Refresh origin/main"
    ux_bullet "fork repo (사내 fork <-> 공개 upstream):"
    _git_help_cmd 'git checkout main'
    _git_help_cmd 'git fetch --all --prune'
    _git_help_cmd 'git merge upstream/main   # 충돌/ruff drift -> git-help pitfalls'
    _git_help_cmd 'git push origin main'
    ux_bullet "plain repo (upstream 없음):"
    _git_help_cmd 'git checkout main'
    _git_help_cmd 'git pull --ff-only'

    ux_section "[Phase 1] Trigger dev deploy"
    _git_help_cmd 'gh workflow run <DEV_WORKFLOW> --repo <REPO_COORD> -f ref=main'
    ux_bullet "optional: -f no_cache=true  (Docker 강제 재빌드)"
    ux_bullet "optional: -f reset_db=true  (DB 볼륨 초기화 — 데이터 삭제 주의)"

    ux_section "[Phase 2] Check status"
    _git_help_cmd 'gh run list --workflow=<DEV_WORKFLOW> --repo <REPO_COORD> --limit 3'

    ux_info "근거·상세: docs/guide/deploy-workflow.md"
}

_git_help_rows_release() {
    ux_section "치환값 (placeholder)"
    ux_table_row "<PROD_WORKFLOW>" "예: prod-deploy.yml" "prod 배포 workflow 파일"
    ux_table_row "<TAG>" "예: v2.1.0" "릴리스 태그"
    ux_table_row "<DEPLOY_STRATEGY>" "rolling | recreate" "prod 배포 전략"
    ux_table_row "<TEST_CMD>" "예: uv run pytest -q" "릴리스 게이트 테스트"
    ux_table_row "<RELEASE_FILES>" "version bump + notes" "릴리스 커밋에 스테이징할 파일"
    ux_table_row "<PROD_SSH_ALIAS>" "~/.ssh/config 별칭" "prod 로그/psql 접근"
    ux_table_row "<PROD_API_CONTAINER>" "예: prod-api" "prod api 컨테이너 이름"

    ux_section "[Phase A] Refresh origin/main"
    ux_bullet "git-help deploy 의 Phase 0 과 동일 (fork=merge / plain=pull)"

    ux_section "[Phase B] Update release artifacts"
    ux_bullet "프로젝트별 산출물 -> git-help release-artifacts"

    ux_section "[Phase C] Gate -> commit -> tag -> push -> deploy -> verify"
    ux_bullet "C-1. test gate (프록시 env 오염 시 -> git-help pitfalls)"
    _git_help_cmd '<TEST_CMD>'
    ux_bullet "C-2. stage release artifacts only (다른 변경 넣지 말 것)"
    _git_help_cmd 'git add <RELEASE_FILES>'
    ux_bullet "C-3. commit + annotated tag"
    _git_help_cmd 'git commit -m "release(<TAG>): ..."'
    _git_help_cmd 'git tag -a <TAG> -m "<TAG>"'
    ux_bullet "C-4. push tag first, then main"
    _git_help_cmd 'git push origin <TAG>'
    _git_help_cmd 'git push origin main'
    ux_bullet "C-5. prod deploy (태그 직접 지정)"
    _git_help_cmd 'gh workflow run <PROD_WORKFLOW> --repo <REPO_COORD> -f ref=<TAG> -f deploy_strategy=<DEPLOY_STRATEGY>'
    ux_bullet "rolling: 무중단 / recreate: down->up (파괴적 migration)"
    ux_bullet "C-6. watch"
    _git_help_cmd 'gh run list --workflow=<PROD_WORKFLOW> --repo <REPO_COORD> --limit 3'
    _git_help_cmd 'gh run watch <run-id> --repo <REPO_COORD>'
    ux_bullet "C-7. 사후검증: 푸터 <TAG> 표시 / prod 로그 무이상"
    _git_help_cmd 'ssh <PROD_SSH_ALIAS> "docker logs <PROD_API_CONTAINER> --since 10m --tail 50"'

    ux_info "공지 등 후처리: git-help release-artifacts / 근거: docs/guide/deploy-workflow.md"
}

_git_help_rows_release_artifacts() {
    ux_section "Release artifacts (프로젝트별 — 예시)"
    ux_bullet "version bump (버전 표기 단일 소스)  예: apps/web/vite.config.ts 의 APP_VERSION"
    ux_bullet "release notes 신설  예: docs/public/release-notes/<TAG>.md"
    ux_bullet "release notes 목록 최상단 링크 추가  예: docs/public/release-notes/README.md"
    ux_bullet "인앱 공지 본문 작성 (리포 밖)  예: /tmp/announcement.json"
    ux_bullet "(배포 성공 후) 공지 등록 — psql 접근  예: PROD_SSH=<PROD_SSH_ALIAS> <release-script>"
    ux_warning "도메인 variable(APP_BASE_URL 등) 최신인지 확인 — 옛 도메인이면 로그인 nonce_missing"
    ux_info "근거·상세: docs/guide/deploy-workflow.md"
}

_git_help_rows_rollback() {
    ux_section "치환값 (placeholder)"
    ux_table_row "<PROD_WORKFLOW>" "예: prod-deploy.yml" "prod 배포 workflow 파일"
    ux_table_row "<REPO_COORD>" "예: github.example.net/org/repo" "gh --repo 좌표"
    ux_table_row "<PREV_TAG>" "예: v2.0.3" "롤백 대상 이전 태그"

    ux_section "[Step 1] 이전 태그 확인"
    _git_help_cmd 'git tag --sort=-v:refname | head'
    _git_help_cmd 'gh release list --repo <REPO_COORD>'

    ux_section "[Step 2] 이전 태그로 prod 재배포"
    _git_help_cmd 'gh workflow run <PROD_WORKFLOW> --repo <REPO_COORD> -f ref=<PREV_TAG> -f deploy_strategy=rolling'

    ux_section "[Step 3] watch + 사후검증"
    _git_help_cmd 'gh run watch <run-id> --repo <REPO_COORD>'
    ux_warning "파괴적 DB migration 이 있었으면 코드 롤백만으로 복구 안 됨 -> recreate + DB 복구 별도"
    ux_info "근거·상세: docs/guide/deploy-workflow.md"
}

_git_help_rows_pitfalls() {
    ux_table_header "함정" "대응" ""
    ux_table_row "upstream merge ruff drift" "uv run --project <PKG> ruff format <파일> 재커밋" ""
    ux_table_row "pytest 프록시 env 오염" "env -u HTTP_PROXY -u http_proxy -u HTTPS_PROXY -u https_proxy -u NO_PROXY -u no_proxy" ""
    ux_table_row "prod SSH 인증 실패" "PROD_SSH=<PROD_SSH_ALIAS> (~/.ssh/config 별칭) 사용" ""
    ux_table_row "dev-deploy rolling 없음" "dev 는 no_cache/reset_db 만 유효" ""
    ux_table_row "배포 커밋-태그 불일치" "prod 는 -f ref=<TAG> 로 태그 직접 지정" ""
    ux_table_row "릴리스 후 nonce_missing" "APP_BASE_URL variable 이 신 도메인인지 확인 후 재배포" ""
    ux_info "전체 함정·맥락: docs/guide/deploy-workflow.md"
}

_git_help_rows_principles() {
    ux_bullet "1) Fork sync = merge (rebase 금지) — origin/main 공용, force-push/SHA/stale tag 회피"
    ux_bullet "2) 배포 = gh workflow run (branch push 아님) — 폐기된 dev-server/prod-server 무시"
    ux_bullet "3) prod=태그(-f ref=<TAG>), dev=main — 태그는 롤백·release·감사 좌표"
    ux_info "근거 상세: docs/guide/deploy-workflow.md"
}
```

- [ ] **Step 4: 디스패처/요약/목록/전체 배선**

(4a) `_git_help_summary()` 안, `ux_bullet_sub "ssh: ..."` 줄과 `ux_bullet_sub "details: ..."` 줄 **사이**에 정확히 1줄 삽입:

```sh
    ux_bullet_sub "deploy: deploy | release | release-artifacts | rollback | pitfalls | principles"
```

(4b) `_git_help_list_sections()` 안, `ux_bullet_sub "ssh"` 줄 **뒤**에 삽입:

```sh
    ux_bullet_sub "deploy"
    ux_bullet_sub "release"
    ux_bullet_sub "release-artifacts"
    ux_bullet_sub "rollback"
    ux_bullet_sub "pitfalls"
    ux_bullet_sub "principles"
```

(4c) `_git_help_section_rows()` 의 `case "$1" in` 에서 `ssh|auth)` 케이스 **뒤**, `*)` 앞에 삽입:

```sh
        deploy)
            _git_help_rows_deploy
            ;;
        release)
            _git_help_rows_release
            ;;
        release-artifacts|artifacts)
            _git_help_rows_release_artifacts
            ;;
        rollback)
            _git_help_rows_rollback
            ;;
        pitfalls)
            _git_help_rows_pitfalls
            ;;
        principles)
            _git_help_rows_principles
            ;;
```

(4d) `_git_help_full()` 안, 마지막 `_git_help_render_section "SSH & Authentication" _git_help_rows_ssh` 줄 **뒤**에 삽입:

```sh
    _git_help_render_section "Deploy (dev)" _git_help_rows_deploy
    _git_help_render_section "Release (prod)" _git_help_rows_release
    _git_help_render_section "Release Artifacts" _git_help_rows_release_artifacts
    _git_help_render_section "Rollback" _git_help_rows_rollback
    _git_help_render_section "Pitfalls" _git_help_rows_pitfalls
    _git_help_render_section "Principles" _git_help_rows_principles
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `pytest tests/integration/test_help_topics.py::TestGitDeployHelpSections -q`
Expected: PASS (모든 파라미터 조합).

- [ ] **Step 6: 15줄 정책 + 기존 인터페이스 회귀 확인**

Run: `pytest tests/integration/test_help_compact_policy.py -q -k git_help`
Expected: PASS — `git_help` 기본 출력 ≤15줄(14줄), 표준 템플릿/`--list`/`--all`/섹션 조회 유지.

- [ ] **Step 7: 셸 lint**

Run: `mise run lint-sh`
Expected: shellcheck + shfmt diff 통과. 실패 시 `mise run fix-sh` 후 재확인.

- [ ] **Step 8: 커밋**

```bash
git add shell-common/functions/git_help.sh tests/integration/test_help_topics.py
git commit -m "docs(git-help): add deploy/release/rollback workflow sections (#1128)"
```

---

## Task 2: 근거 문서 `docs/guide/deploy-workflow.md` 작성

**Files:**
- Create: `docs/guide/deploy-workflow.md`

**Interfaces:**
- Consumes: 없음 (독립 문서). Task 1 의 `git-help <section>` 명령을 텍스트로 참조.
- Produces: 각 `git-help` 섹션 footer 가 가리키는 근거 SSOT 문서.

- [ ] **Step 1: 문서 작성**

`docs/guide/deploy-workflow.md` 를 아래 내용으로 생성:

```markdown
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
| `PROD_SSH=<ip>` 인증 실패 | `PROD_SSH=<PROD_SSH_ALIAS>` (`~/.ssh/config` devops 별칭) 사용 | psql 접근은 devops 계정 별칭 필요 |
| dev-deploy rolling 걱정 | dev-deploy 는 rolling 개념 없음. `no_cache`·`reset_db` 만 유효 | dev/prod workflow 옵션 상이 |
| 배포 커밋과 태그 어긋남 | `gh workflow run prod-deploy.yml -f ref=<TAG>` 로 태그 직접 지정 | 실행 ref 가 main 이어도 checkout 은 태그 |
| 릴리스 후 nonce_missing | 저장소 variable `APP_BASE_URL` 이 신 도메인인지 확인, 옛 도메인이면 갱신 + 재배포 | 공지·링크 도메인이 옛 URL |

## 릴리스 산출물 상세

`git-help release-artifacts` 의 각 항목이 왜 필요한지 (#1128 monorepo 예시):

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
```

- [ ] **Step 2: footer 정합성 확인**

Run: `git_help deploy | grep -F 'docs/guide/deploy-workflow.md'`
Expected: footer 라인 출력 (Task 1 의 각 섹션 footer 가 이 파일을 가리킴). deploy/release/release-artifacts/rollback/pitfalls/principles 모두 동일 경로 참조.

- [ ] **Step 3: 커밋**

```bash
git add docs/guide/deploy-workflow.md
git commit -m "docs(guide): add deploy-workflow rationale doc (#1128)"
```

---

## Task 3: 전체 회귀 검증

**Files:** (없음 — 검증 전용)

- [ ] **Step 1: 전체 테스트**

Run: `mise run test`
Expected: bats + pytest + golden rules 전부 PASS. 특히 `test_help_topics.py`·`test_help_compact_policy.py` 그린.

- [ ] **Step 2: 전체 lint**

Run: `mise run lint`
Expected: ruff + mypy + shellcheck + shfmt 통과.

- [ ] **Step 3: 수동 스모크 (선택)**

Run: `bash -c 'DOTFILES_FORCE_INIT=1 source shell-common/functions/git_help.sh; git_help --list; git_help deploy; git_help'`
Expected: `--list` 에 신규 6섹션 노출 / `deploy` 워크플로우 출력 / 무인자 요약 ≤15줄.

- [ ] **Step 4: 실패 시 수정 후 재실행**

lint/test 실패는 근본 원인 수정(`--no-verify` 금지). 수정 시 관련 파일 재-add 후 amend 없이 새 커밋 또는 Task 1/2 커밋 전 단계로 회귀.

---

## Self-Review (작성자 점검 결과)

**1. Spec coverage:**
- 섹션 6개(deploy/release/release-artifacts/rollback/pitfalls/principles) → Task 1 Step 3 각 row 함수. ✓
- Phase 0 선택 프리루드(fork=merge/plain=pull) → `_git_help_rows_deploy` Phase 0. ✓
- placeholder + 범례표 → 각 row 함수 상단 `ux_table_row`. ✓
- 범용 스켈레톤 + artifacts 분리 → `release` vs `release-artifacts`. ✓
- 코드 + docs 병행, drift 규칙(포인터만) → Task 2 문서는 명령어 재나열 없이 `git-help` 참조; 코드 footer 는 문서 참조. ✓
- 15줄 제약 → Step 4a 1줄만 추가, Step 6 검증. ✓
- 언어(영어 라벨+한글) → 각 함수 라벨 영어, 설명 한글. ✓
- 문서 경로 `docs/guide/deploy-workflow.md` → Task 2. ✓
- #1128 close / sync-to-deploy 무수정 → 문서 legacy 메모, 코드 미변경. ✓
- 테스트 → Task 1 Step 1 + Task 3. ✓

**2. Placeholder scan:** "TBD"/"TODO"/"implement later" 없음. `<TAG>`/`<PKG>` 등은 의도된 사용자-치환 지점(가이드 내용). 모든 코드 스텝에 완전한 코드 포함. ✓

**3. Type/name consistency:** 함수명 6개 + `_git_help_cmd` 가 Step 3 정의 ↔ Step 4c/4d 호출에서 동일 철자 사용. 섹션 토큰(`release-artifacts|artifacts`)이 디스패처·테스트·요약에서 일치. ✓

## Execution Handoff (참고)

이 저장소 워크플로우상 커밋은 `gh:commit` 스킬 경유가 표준이다(대화 중 직접 커밋 지양). 위 커밋 스텝은 실행 에이전트가 훅을 거쳐 수행하며, 최종 PR 은 `gh:pr` 로 생성해 `Closes #1128` 를 건다. 대안으로 `gh:issue-flow 1128` 로 구현→커밋→PR 을 일괄 실행할 수 있다.
