# Step 5 — `review-passed` 무효화 (soft-fail)

Step 4 의 `git push --force-with-lease` 가 **성공했을 때만** 실행한다. Step 2 의
already-clean no-op(exit 0), `CONFLICTING` 위임(exit 3), 리베이스 충돌 중단
(exit 4), push 거부(exit 6) 경로에서는 head 가 그대로이므로 판정도 그대로
유효하다 — 아무것도 하지 않는다.

규칙의 SSOT 는 `shell-common/functions/gh_pr_edit_safe.sh` 헤더의
"Verdict-label invalidation — SSOT for issue #1563" 절이다. 요약: `review-passed`
는 **특정 head 커밋 하나**가 리뷰를 통과했다는 주장이다. 깨끗한 리베이스라도
force-push 는 그 커밋을 새 SHA 로 갈아치우므로 주장이 거짓이 된다. PR #1529 가
정확히 이 경로로 리뷰된 커밋 위에 force-push 하고도 라벨을 그대로 뒀다.

Caller contract: `PR_NUMBER`, `TARGET_REPO`, `TARGET_HOST` 는 Step 1 이
`references/github-target.md` 대로 이미 export 한 상태여야 한다 (#1403).

## `review-blocked` 는 절대 건드리지 않는다

이 스킬은 base 를 따라잡을 뿐, 리뷰어가 제기한 블로커가 처리됐는지에 대한
**증거를 하나도 갖고 있지 않다**. 리베이스 뒤에 `review-blocked` 가 남아 있는
것은 버그가 아니라 안전한 방향이다. `gh:pr-reply` 는 Step 5(코멘트 전원 답변)를
완주하면 이 라벨을 무조건 뗀다(#1634) — 하지만 그건 그 스킬이 실제로 리뷰
코멘트에 답변했다는 별도의 증거를 갖고 있기 때문이다. 이 스킬은 그 증거가
없으므로 손대지 않는다.

라벨을 **붙이는** 것도 금지다. `review-passed` / `review-blocked` 의 유일한
발급자는 `devx:pr-review-all` 이다.

## 명령

공유 헬퍼 `_gh_pr_drop_label` 을 쓴다 — REST DELETE 관용구를 스킬마다 복사하지
않기 위한 단일 구현체다. `gh pr edit --remove-label` 이 아닌 이유는 후자가
classic Projects 보드가 붙은 repo 에서 GraphQL deprecation 때문에 **조용히
실패**하기 때문이다 (#326 Bug B). 404(라벨이 애초에 없음)는 **경고가 아니라
정상**으로 흡수되므로 사전 확인 분기가 필요 없다.

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_edit_safe.sh"

if _vl_err=$(_gh_pr_drop_label "$PR_NUMBER" review-passed \
        "$TARGET_REPO" "$TARGET_HOST" 2>&1); then
    echo "[OK] \`review-passed\` 무효화됨 — force-push 로 head 가 바뀌어 이전 판정은 만료"
else
    echo "[WARN] \`review-passed\` 제거 실패 — 리뷰되지 않은 커밋에 판정이 남아 있다: ${_vl_err}"
fi
```

Soft-fail 이다: 실패해도 Step 5 의 검증/보고는 그대로 진행한다.

## 호스트 고정

네 번째 인자 `TARGET_HOST` 가 `GH_HOST` 를 고정한다. 넘기지 않으면 dual-host
로그인에서 `gh` 가 `gh repo set-default` 로 폴백해 **에러 없이 엉뚱한 서버의
라벨을 지운다** (#1403 / #1407). `gh api` 는 `--repo` 플래그를 받지 않으므로
repo 는 경로에 들어간다 (#658) — 헬퍼가 대신 처리한다.
