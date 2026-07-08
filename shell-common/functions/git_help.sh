#!/bin/sh
# shell-common/functions/git_help.sh

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_git_help_summary() {
    ux_info "Usage: git-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "basic: gs | ga | gc | gca | gp | gpl | gco | gd | grs | gb | grmc"
    ux_bullet_sub "sync: gf | gfu | gfa | gsw | gr"
    ux_bullet_sub "logs: gl | gl1 | gl2 | glref"
    ux_bullet_sub "upstream: gupa | gupdel | glum | glub"
    ux_bullet_sub "branch: gset-main | gset-dev | gset | gb -D local | gb -D remote"
    ux_bullet_sub "stash: git stash list | show -p | pop | apply | drop"
    ux_bullet_sub "pick: gcp scan | gcp theirs | gcp ours | gcp author | gcp pick"
    ux_bullet_sub "special: gpf_dev_server | gpfu"
    ux_bullet_sub "lfs: git_lfs_install | glfs"
    ux_bullet_sub "ssh: git_ssh_check | git_ssh_setup"
    ux_bullet_sub "deploy: deploy | release | release-artifacts | rollback | pitfalls | principles"
    ux_bullet_sub "details: git-help <section>  (example: git-help stash)"
}

_git_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "basic"
    ux_bullet_sub "sync"
    ux_bullet_sub "logs"
    ux_bullet_sub "upstream"
    ux_bullet_sub "branch"
    ux_bullet_sub "stash"
    ux_bullet_sub "pick"
    ux_bullet_sub "special"
    ux_bullet_sub "lfs"
    ux_bullet_sub "ssh"
    ux_bullet_sub "deploy"
    ux_bullet_sub "release"
    ux_bullet_sub "release-artifacts"
    ux_bullet_sub "rollback"
    ux_bullet_sub "pitfalls"
    ux_bullet_sub "principles"
}

_git_help_rows_basic() {
    ux_table_row "gs" "git status -sb" "Short status"
    ux_table_row "ga" "git add ." "Stage all changes"
    ux_table_row "gc" "git commit -m" "Commit with message"
    ux_table_row "gca" "git commit --amend" "Amend last commit"
    ux_table_row "gp" "git push" "Push to remote"
    ux_table_row "gpl" "git pull" "Pull from remote"
    ux_table_row "gco" "git checkout" "Checkout branch/commit"
    ux_table_row "gd" "git diff" "Show changes"
    ux_table_row "grs" "git restore <file>" "Discard working dir changes"
    ux_table_row "grs --staged" "git restore --staged <file>" "Unstage file (undo git add)"
    ux_table_row "gb" "git branch" "List branches"
    ux_table_row "grmc" "git rm --cached" "Unstage, keep file"
}

_git_help_rows_sync() {
    ux_table_row "gf [remote]" "gf / gf u / gf <name>" "Fetch & prune (default: origin, u=upstream)"
    ux_table_row "gfu" "git fetch upstream" "Fetch upstream"
    ux_table_row "gfa" "git fetch --all" "Fetch all & prune"
    ux_table_row "gsw" "git switch -c" "Switch to remote branch"
    ux_table_row "gr" "git remote -v" "List remotes"
}

_git_help_rows_logs() {
    ux_table_row "gl" "git-log" "Graph log (default 11)"
    ux_table_row "gl1" "log --oneline" "One-line graph log"
    ux_table_row "gl2" "git-log2" "Alternative log format"
    ux_table_row "glref" "log ref/main" "Ref log for main"
}

_git_help_rows_upstream() {
    ux_table_row "gupa" "remote add upstream" "Add upstream remote"
    ux_table_row "gupdel" "gupdel <remote>" "Remove remote"
    ux_table_row "glum" "git-log-upstream" "Upstream main log"
    ux_table_row "glub" "glub [branch]" "Upstream branch log"
}

_git_help_rows_branch() {
    ux_table_row "gset-main" "set-upstream main" "Track origin/main"
    ux_table_row "gset-dev" "set-upstream dev" "Track origin/dev"
    ux_table_row "gset" "gset [branch]" "Track origin/[branch]"
    ux_table_row "gb -D local" "git_branch -D local" "Delete local branches (keeps: main/master + current + keywords)"
    ux_table_row "gb -D remote [<r>]" "git_branch -D remote" "Delete remote-tracking branches (default: origin, keeps: main/master)"
    ux_table_row "gb -h" "git_branch --help" "Show gb sub-command help"
}

_git_help_rows_stash() {
    ux_table_row "git stash list" "git stash list" "List saved stashes"
    ux_table_row "git stash show -p" "git stash show -p [stash]" "Show stashed patch (default: latest)"
    ux_table_row "git stash pop" "git stash pop [stash]" "Apply stash and remove it"
    ux_table_row "git stash apply" "git stash apply [stash]" "Apply stash and keep it"
    ux_table_row "git stash drop" "git stash drop [stash]" "Delete a stash entry"
}

_git_help_rows_pick() {
    ux_table_row "gcp pick" "gcp pick <commit>..." "Cherry-pick commits"
    ux_table_row "gcp theirs" "gcp theirs <commit>..." "Cherry-pick with -X theirs (incoming)"
    ux_table_row "gcp ours" "gcp ours <commit>..." "Cherry-pick with -X ours (current)"
    ux_table_row "gcp author" "gcp author <range> [author]" "Cherry-pick by author"
    ux_table_row "gcp scan" "gcp scan [base] [src] [--author=<name|all>]" "Compare & pick missing (default: main <- upstream/main, author=dEitY719)"
    ux_table_row "gcp -h" "gcp help [section]" "Show gcp sub-command help"
}

_git_help_rows_special() {
    ux_table_row "gpf_dev_server" "push force dev" "Force push dev-server"
    ux_table_row "gpfu" "push --force-with-lease" "Force push main"
}

_git_help_rows_lfs() {
    ux_table_row "git_lfs_install" "Install LFS" "Ubuntu setup"
    ux_table_row "glfs" "track <pattern>" "Track files with LFS"
}

_git_help_rows_ssh() {
    ux_table_row "git_ssh_check" "Test GitHub SSH" "Verify GitHub SSH connection"
    ux_table_row "git_ssh_setup" "Setup SSH" "Manual SSH configuration guide"
}

_git_help_notes_pick_strategy() {
    ux_bullet "gcp theirs: ${UX_ERROR}Conflict${UX_RESET} 발생시 ${UX_WARNING}incoming(cherry-pick되는 커밋의 변경)${UX_RESET} 선택"
    ux_bullet "gcp ours: ${UX_ERROR}Conflict${UX_RESET} 발생시 ${UX_SUCCESS}current branch(현재 브랜치의 변경)${UX_RESET} 선택"
}

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
    ux_table_row "<REPO_COORD>" "예: github.example.net/org/repo" "gh --repo 좌표"
    ux_table_row "<TAG>" "예: v2.1.0" "릴리스 태그"
    ux_table_row "<DEPLOY_STRATEGY>" "rolling | recreate" "prod 배포 전략"
    ux_table_row "<TEST_CMD>" "예: uv run pytest -q" "릴리스 게이트 테스트"
    ux_table_row "<RELEASE_FILES>" "version bump + notes" "릴리스 커밋에 스테이징할 파일"
    ux_table_row "<PROD_SSH_ALIAS>" "예: devops-prod" "prod 로그/psql 접근 (~/.ssh/config 별칭)"
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

_git_help_render_section() {
    ux_section "$1"
    "$2"
}

_git_help_section_rows() {
    case "$1" in
        basic)
            _git_help_rows_basic
            ;;
        sync|fetch)
            _git_help_rows_sync
            ;;
        logs|log)
            _git_help_rows_logs
            ;;
        upstream)
            _git_help_rows_upstream
            ;;
        branch|branches)
            _git_help_rows_branch
            ;;
        stash)
            _git_help_rows_stash
            ;;
        pick|cherrypick|cherry-pick)
            _git_help_rows_pick
            ;;
        special)
            _git_help_rows_special
            ;;
        lfs)
            _git_help_rows_lfs
            ;;
        ssh|auth)
            _git_help_rows_ssh
            ;;
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
        *)
            ux_error "Unknown git-help section: $1"
            ux_info "Try: git-help --list"
            return 1
            ;;
    esac
}

_git_help_full() {
    ux_header "Git Quick Commands"

    _git_help_render_section "Basic Commands" _git_help_rows_basic
    _git_help_render_section "Fetch & Sync" _git_help_rows_sync
    _git_help_render_section "Logs" _git_help_rows_logs
    _git_help_render_section "Upstream" _git_help_rows_upstream
    _git_help_render_section "Branch Configuration" _git_help_rows_branch
    _git_help_render_section "Stash" _git_help_rows_stash
    _git_help_render_section "Cherry-pick" _git_help_rows_pick
    _git_help_render_section "Cherry-pick -X (Merge Strategy)" _git_help_notes_pick_strategy
    _git_help_render_section "Special" _git_help_rows_special
    _git_help_render_section "Git LFS" _git_help_rows_lfs
    _git_help_render_section "SSH & Authentication" _git_help_rows_ssh
    _git_help_render_section "Deploy (dev)" _git_help_rows_deploy
    _git_help_render_section "Release (prod)" _git_help_rows_release
    _git_help_render_section "Release Artifacts" _git_help_rows_release_artifacts
    _git_help_render_section "Rollback" _git_help_rows_rollback
    _git_help_render_section "Pitfalls" _git_help_rows_pitfalls
    _git_help_render_section "Principles" _git_help_rows_principles
}

git_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _git_help_summary
            ;;
        --list|list|section|sections)
            _git_help_list_sections
            ;;
        --all|all)
            _git_help_full
            ;;
        *)
            _git_help_section_rows "$1"
            ;;
    esac
}

alias git-help='git_help'
