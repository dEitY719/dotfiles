# git

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/git_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic git --force`

## 호출

- Help 진입점: `git-help [section|--list|--all]`
- 통합 라우팅: `my-help git [section]`
- Alias: `git-help`

## 요약 (git-help)

- Usage: git-help [section|--list|--all]
- sections
    - basic: gs | ga | gc | gca | gp | gpl | gco | gd | grs | gb | grmc
    - sync: gf | gfu | gfa | gsw | gr
    - logs: gl | gl1 | gl2 | glref
    - upstream: gupa | gupdel | glum | glub
    - branch: gset-main | gset-dev | gset | gb -D local | gb -D remote
    - stash: git stash list | show -p | pop | apply | drop
    - pick: gcp scan | gcp theirs | gcp ours | gcp author | gcp pick
    - special: gpf_dev_server | gpfu
    - lfs: git_lfs_install | glfs
    - ssh: git_ssh_check | git_ssh_setup
    - deploy: deploy | release | release-artifacts | rollback | pitfalls | principles
    - details: git-help <section>  (example: git-help stash)

## 섹션

### basic

- **gs** — git status -sb — Short status
- **ga** — git add . — Stage all changes
- **gc** — git commit -m — Commit with message
- **gca** — git commit --amend — Amend last commit
- **gp** — git push — Push to remote
- **gpl** — git pull — Pull from remote
- **gco** — git checkout — Checkout branch/commit
- **gd** — git diff — Show changes
- **grs** — git restore <file> — Discard changes (친절 래퍼: untracked/오타/staged/no-op 사전 경고)
- **grs --staged** — git restore --staged <file> — Unstage file (undo git add)
- **gb** — git branch — List branches
- **grmc** — git rm --cached — Unstage, keep file

### sync

- **gf [remote]** — gf / gf u / gf <name> — Fetch & prune (default: origin, u=upstream)
- **gfu** — git fetch upstream — Fetch upstream
- **gfa** — git fetch --all — Fetch all & prune
- **gsw** — git switch -c — Switch to remote branch
- **gr** — git remote -v — List remotes

### logs

- **gl** — git-log — Graph log (default 11)
- **gl1** — log --oneline — One-line graph log
- **gl2** — git-log2 — Alternative log format
- **glref** — log ref/main — Ref log for main

### upstream

- **gupa** — remote add upstream — Add upstream remote
- **gupdel** — gupdel <remote> — Remove remote
- **glum** — git-log-upstream — Upstream main log
- **glub** — glub [branch] — Upstream branch log

### branch

- **gset-main** — set-upstream main — Track origin/main
- **gset-dev** — set-upstream dev — Track origin/dev
- **gset** — gset [branch] — Track origin/[branch]
- **gb -D local** — git_branch -D local — Delete local branches (keeps: main/master + current + keywords)
- **gb -D remote [<remote>]** — git_branch -D remote — Delete remote-tracking branches (default: origin, e.g. origin, upstream, keeps: main/master)
- **gb -h** — git_branch --help — Show gb sub-command help

### stash

- **git stash list** — git stash list — List saved stashes
- **git stash show -p** — git stash show -p [stash] — Show stashed patch (default: latest)
- **git stash pop** — git stash pop [stash] — Apply stash and remove it
- **git stash apply** — git stash apply [stash] — Apply stash and keep it
- **git stash drop** — git stash drop [stash] — Delete a stash entry

### pick

- **gcp pick** — gcp pick <commit>... — Cherry-pick commits
- **gcp theirs** — gcp theirs <commit>... — Cherry-pick with -X theirs (incoming)
- **gcp ours** — gcp ours <commit>... — Cherry-pick with -X ours (current)
- **gcp author** — gcp author <range> [author] — Cherry-pick by author
- **gcp scan** — gcp scan [base] [src] [--author=<name|all>] — Compare & pick missing (default: main <- upstream/main, author=dEitY719)
- **gcp -h** — gcp help [section] — Show gcp sub-command help

### special

- **gpf_dev_server** — push force dev — Force push dev-server
- **gpfu** — push --force-with-lease — Force push main

### lfs

- **git_lfs_install** — Install LFS — Ubuntu setup
- **glfs** — track <pattern> — Track files with LFS

### ssh

- **git_ssh_check** — Test GitHub SSH — Verify GitHub SSH connection
- **git_ssh_setup** — Setup SSH — Manual SSH configuration guide

### deploy

**치환값 (placeholder)**

- **<DEV_WORKFLOW>** — 예: dev-deploy.yml — dev 배포 workflow 파일
- **<REPO_COORD>** — 예: github.example.net/org/repo — gh --repo 좌표 <GHE_HOST>/<ORG>/<REPO>
**[Phase 0] Refresh origin/main**

- fork repo (사내 fork <-> 공개 upstream):
  git checkout main
  git fetch --all --prune
  git merge upstream/main   # 충돌/ruff drift -> git-help pitfalls
  git push origin main
- plain repo (upstream 없음):
  git checkout main
  git pull --ff-only
**[Phase 1] Trigger dev deploy**

  gh workflow run <DEV_WORKFLOW> --repo <REPO_COORD> -f ref=main
- optional: -f no_cache=true  (Docker 강제 재빌드)
- optional: -f reset_db=true  (DB 볼륨 초기화 — 데이터 삭제 주의)
**[Phase 2] Check status**

  gh run list --workflow=<DEV_WORKFLOW> --repo <REPO_COORD> --limit 3
- 근거·상세: docs/guide/deploy-workflow.md

### release

**치환값 (placeholder)**

- **<PROD_WORKFLOW>** — 예: prod-deploy.yml — prod 배포 workflow 파일
- **<REPO_COORD>** — 예: github.example.net/org/repo — gh --repo 좌표
- **<TAG>** — 예: v2.1.0 — 릴리스 태그
- **<DEPLOY_STRATEGY>** — rolling | recreate — prod 배포 전략
- **<TEST_CMD>** — 예: uv run pytest -q — 릴리스 게이트 테스트
- **<RELEASE_FILES>** — version bump + notes — 릴리스 커밋에 스테이징할 파일
- **<PROD_SSH_ALIAS>** — 예: devops-prod — prod 로그/psql 접근 (~/.ssh/config 별칭)
- **<PROD_API_CONTAINER>** — 예: prod-api — prod api 컨테이너 이름
**[Phase A] Refresh origin/main**

- git-help deploy 의 Phase 0 과 동일 (fork=merge / plain=pull)
**[Phase B] Update release artifacts**

- 프로젝트별 산출물 -> git-help release-artifacts
**[Phase C] Gate -> commit -> tag -> push -> deploy -> verify**

- C-1. test gate (프록시 env 오염 시 -> git-help pitfalls)
  <TEST_CMD>
- C-2. stage release artifacts only (다른 변경 넣지 말 것)
  git add <RELEASE_FILES>
- C-3. commit + annotated tag
  git commit -m "release(<TAG>): ..."
  git tag -a <TAG> -m "<TAG>"
- C-4. push tag first, then main
  git push origin <TAG>
  git push origin main
- C-5. prod deploy (태그 직접 지정)
  gh workflow run <PROD_WORKFLOW> --repo <REPO_COORD> -f ref=<TAG> -f deploy_strategy=<DEPLOY_STRATEGY>
- rolling: 무중단 / recreate: down->up (파괴적 migration)
- C-6. watch
  gh run list --workflow=<PROD_WORKFLOW> --repo <REPO_COORD> --limit 3
  gh run watch <run-id> --repo <REPO_COORD>
- C-7. 사후검증: 푸터 <TAG> 표시 / prod 로그 무이상
  ssh <PROD_SSH_ALIAS> "docker logs <PROD_API_CONTAINER> --since 10m --tail 50"
- 공지 등 후처리: git-help release-artifacts / 근거: docs/guide/deploy-workflow.md

### release-artifacts

**Release artifacts (프로젝트별 — 예시)**

- version bump (버전 표기 단일 소스)  예: apps/web/vite.config.ts 의 APP_VERSION
- release notes 신설  예: docs/public/release-notes/<TAG>.md
- release notes 목록 최상단 링크 추가  예: docs/public/release-notes/README.md
- 인앱 공지 본문 작성 (리포 밖)  예: /tmp/announcement.json
- (배포 성공 후) 공지 등록 — psql 접근  예: PROD_SSH=<PROD_SSH_ALIAS> <release-script>
- 도메인 variable(APP_BASE_URL 등) 최신인지 확인 — 옛 도메인이면 로그인 nonce_missing
- 근거·상세: docs/guide/deploy-workflow.md

### rollback

**치환값 (placeholder)**

- **<PROD_WORKFLOW>** — 예: prod-deploy.yml — prod 배포 workflow 파일
- **<REPO_COORD>** — 예: github.example.net/org/repo — gh --repo 좌표
- **<PREV_TAG>** — 예: v2.0.3 — 롤백 대상 이전 태그
**[Step 1] 이전 태그 확인**

  git tag --sort=-v:refname | head
  gh release list --repo <REPO_COORD>
**[Step 2] 이전 태그로 prod 재배포**

  gh workflow run <PROD_WORKFLOW> --repo <REPO_COORD> -f ref=<PREV_TAG> -f deploy_strategy=rolling
**[Step 3] watch + 사후검증**

  gh run watch <run-id> --repo <REPO_COORD>
- 파괴적 DB migration 이 있었으면 코드 롤백만으로 복구 안 됨 -> recreate + DB 복구 별도
- 근거·상세: docs/guide/deploy-workflow.md

### pitfalls

- **함정** — 대응
- **upstream merge ruff drift** — uv run --project <PKG> ruff format <파일> 재커밋
- **pytest 프록시 env 오염** — env -u HTTP_PROXY -u http_proxy -u HTTPS_PROXY -u https_proxy -u NO_PROXY -u no_proxy
- **prod SSH 인증 실패** — PROD_SSH=<PROD_SSH_ALIAS> (~/.ssh/config 별칭) 사용
- **dev-deploy rolling 없음** — dev 는 no_cache/reset_db 만 유효
- **배포 커밋-태그 불일치** — prod 는 -f ref=<TAG> 로 태그 직접 지정
- **릴리스 후 nonce_missing** — APP_BASE_URL variable 이 신 도메인인지 확인 후 재배포
- 전체 함정·맥락: docs/guide/deploy-workflow.md

### principles

- 1) Fork sync = merge (rebase 금지) — origin/main 공용, force-push/SHA/stale tag 회피
- 2) 배포 = gh workflow run (branch push 아님) — 폐기된 dev-server/prod-server 무시
- 3) prod=태그(-f ref=<TAG>), dev=main — 태그는 롤백·release·감사 좌표
- 근거 상세: docs/guide/deploy-workflow.md

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/git.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/git_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
