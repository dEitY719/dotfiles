# gh:issue-create — Repo + host resolution

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
   step 3. Both come from that one URL — never from two sources:

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

Store the results as `TARGET_REPO` and `TARGET_HOST` for use in Step 2.5 /
Step 4 of the main workflow.

## Host targeting rule (issue #1403)

이 스킬의 **모든** `gh` 호출 — `gh issue create`, `gh label list`,
`gh api .../milestones`, ai-metrics 코멘트 POST — 은 host 와 repo 를 명시한다:

```bash
GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"
```

`--repo` 없는 `gh` 는 git 의 `origin` 이 아니라 gh CLI 자신의
`gh repo set-default` 를 따른다. github.com 과 GHES 에 동시에 로그인한
상태에서 둘이 어긋나면 **에러 없이 조용히 다른 host 에 붙는다**. 쓰기
스킬인 이 스킬에서는 그 결과가 "이슈가 엉뚱한 repo 에 생성됨" 이고, 되돌리려면
사람이 직접 지워야 한다 (#1403).

`export GH_HOST` 는 Discussion 경로가 sourcing 하는
`shell-common/functions/gh_discussion.sh` 의 GraphQL 호출까지 같은 host 로
보낸다 — Issue 는 GHES 에, Discussion 은 github.com 에 생기는 어긋남을 막는다.

## Failure rule

If the user-specified remote does not exist, fail immediately with the
list of available remotes. **Do not** fall back to `origin` silently —
that masks typos and creates issues in the wrong repo.

`TARGET_HOST` 가 빈 채로 Step 4 에 진입하지 않는다 — 빈 `GH_HOST` 는 정확히
#1403 의 조용한 오생성 상태다.
