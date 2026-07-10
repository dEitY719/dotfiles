# Host Resolution (GHES / GitHub)

origin 시스템은 하드코딩하지 않고 SSOT 함수로 해석한다.

    . "$DOTFILES_ROOT/shell-common/functions/gh_host.sh"
    HOST="$(_gh_resolve_host)"        # internal→github.samsungds.net, 그 외→github.com

- 모든 `gh` 호출은 해석된 host 로 라우팅한다. gh CLI 는 `GH_HOST` 또는 repo 의 remote URL 로
  host 를 판단하므로, 이슈/PR 생성 전 대상 repo 가 그 host 에 있는지 remote 로 확인한다.
- owner/repo 파싱도 gh_host.sh 의 파서를 재사용(별도 정규식 복제 금지).
- setup-mode 판정은 `_dotfiles_setup_mode` 를 따른다(gh_host.sh 내부에서 처리).
- gh_host.sh 부재/기타 모드 → github.com fail-safe(회귀 0).

근거: gh_host.sh 파일 주석(issue #703/#704) — "미래 GHE 도메인 추가 시 이 파일만 수정".
