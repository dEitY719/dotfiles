# gh:issue-implement — Repo + host resolution

Detailed procedure for Step 1 "Detect Repo Context" — remote validation and
owner/repo **plus host** extraction. SKILL.md keeps only the workflow; this
file holds the substeps and error-message shape.

## Substeps

1. `git rev-parse --show-toplevel` — confirm we're in a git repo.

2. Determine the target remote:
   - If the user passed an argument, use it as remote name.
   - Otherwise default to `origin`.

3. Validate the remote and resolve owner/repo:

   ```bash
   git remote get-url <remote-name>
   ```

   If this fails, list available remotes (`git remote -v`) and stop with
   an error like:

   ```
   Error: remote '<remote-name>' not found. Available remotes:
   origin  https://github.com/user/repo.git (fetch)
   upstream  https://github.com/org/repo.git (fetch)
   ```

4. Extract `owner/repo` **and the host** from the remote URL returned in
   step 3. Both must come from that one URL — never from two sources:

   ```bash
   . "${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/gh_host.sh"
   REMOTE_URL=$(git remote get-url <remote-name>) || exit 1
   TARGET_REPO=$(_gh_parse_owner_repo_url "$REMOTE_URL") || exit 1
   TARGET_HOST=$(_gh_host_from_url "$REMOTE_URL") || TARGET_HOST=$(_gh_resolve_host)
   export GH_HOST="$TARGET_HOST"
   export TARGET_REPO TARGET_HOST
   ```

   - `https://github.com/<owner>/<repo>.git` → `github.com` + `<owner>/<repo>`
   - `git@github.samsungds.net:<owner>/<repo>.git` → `github.samsungds.net`
     + `<owner>/<repo>`

   `gh_host.sh` 는 host/URL 매핑의 SSOT 다 — 정규식이나 도메인 목록을 이
   파일에 복제하지 않는다. `_gh_resolve_host` (setup-mode → host) 는 파싱할
   remote URL 이 아예 없을 때만 쓰는 fallback 이다.

Store the results as `TARGET_REPO` and `TARGET_HOST` for use in Step 3 of
the main workflow.

## Host targeting rule (issue #1403)

이 스킬이 실행하는 **모든** `gh` 호출은 host 와 repo 를 명시한다:

```bash
GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"
```

`--repo` 없이 부른 `gh` 는 git 의 `origin` 이 아니라 gh CLI 자신의
`gh repo set-default` 값을 따른다. github.com 과 GHES 두 host 에 동시에
로그인한 상태에서 그 둘이 어긋나면 **에러 없이 조용히 엉뚱한 host 를 조회한다**
— OPEN 인 이슈가 "not found" 로 돌아온 #1403 이 그 사례다.

Step 1 의 `export GH_HOST` 는 이 스킬이 source 하는 헬퍼
(`gh_project_status.sh` 등) 까지 같은 host 를 상속시킨다. 그래도 아래 참조
파일들의 예제 명령은 복사-붙여넣기 안전을 위해 접두사를 그대로 표기한다.

## Failure rule

If the user-specified remote does not exist, fail immediately with the
list of available remotes. **Do not** fall back to `origin` silently —
that masks typos and creates issues in the wrong repo.

`_gh_host_from_url` 이 실패(github 계열이 아닌 remote)하면 `_gh_resolve_host`
로 폴백하되, `TARGET_HOST` 를 비운 채 진행하지 않는다 — 빈 `GH_HOST` 는
바로 #1403 의 조용한 오조회 상태다.
