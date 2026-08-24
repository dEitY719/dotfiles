# gh:issue-read — Repo + host resolution

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
   step 3. Both must be read from that same URL — never from two sources:

   ```bash
   . "${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/gh_host.sh"
   REMOTE_URL=$(git remote get-url <remote-name>) || exit 1
   TARGET_REPO=$(_gh_parse_owner_repo_url "$REMOTE_URL") || exit 1
   TARGET_HOST=$(_gh_host_from_url "$REMOTE_URL") || TARGET_HOST=$(_gh_resolve_host)
   export GH_HOST="$TARGET_HOST"
   ```

   - `https://github.com/<owner>/<repo>.git` → `github.com` + `<owner>/<repo>`
   - `git@github.samsungds.net:<owner>/<repo>.git` → `github.samsungds.net`
     + `<owner>/<repo>`

   `gh_host.sh` 가 host/URL 매핑의 SSOT 다 — 정규식이나 도메인 목록을 여기에
   복제하지 않는다. `_gh_resolve_host` (setup-mode → host) 는 파싱할 remote
   URL 이 없을 때만 쓰는 fallback 이다.

Store the results as `TARGET_REPO` and `TARGET_HOST` for use in Step 2 of
the main workflow.

## Host targeting rule (issue #1403)

이 스킬의 **모든** `gh` 호출은 host 와 repo 를 명시한다:

```bash
GH_HOST="$TARGET_HOST" gh issue view <N> --repo "$TARGET_REPO" ...
```

`--repo` 없는 `gh` 는 git 의 `origin` 이 아니라 gh CLI 자신의
`gh repo set-default` 를 따른다. github.com 과 GHES 에 동시에 로그인한
상태에서 그 둘이 어긋나면 **에러 없이 조용히 다른 host 를 조회한다** —
읽기 전용 스킬인 만큼 결과가 그대로 사용자에게 "이슈 없음" 으로 보고되고,
실제로는 OPEN 인 이슈였던 것이 #1403 이다.

## Failure rule

If the user-specified remote does not exist, fail immediately with the
list of available remotes. **Do not** fall back to `origin` silently —
that masks typos and reads the wrong repo.

같은 이유로 `TARGET_HOST` 가 비어 있는 채로 진행하지 않는다 — 빈 `GH_HOST`
는 정확히 #1403 의 조용한 오조회 상태다.
