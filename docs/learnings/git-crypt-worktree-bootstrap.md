# git-crypt + worktree 부트스트랩 함정

## Context

- **출처**: [Issue #153](https://github.com/dEitY719/dotfiles/issues/153) — 한 세션에서 `Agent({ isolation: "worktree" })`로 두 작업(PR #154, PR #151 리뷰 응대)을 병렬 디스패치하려다 두 에이전트 모두 worktree 생성 단계에서 실패
- **에러 위치**: `git worktree add` 시점에 `.env` smudge filter 호출, git-crypt가 새 worktree에서 키를 못 찾음
- **관련 파일**: `.gitattributes` (git-crypt 필터 매핑), `shell-common/tools/integrations/git_crypt.sh`, `shell-common/tools/custom/install_git_crypt.sh`
- **스킬 컨텍스트**: `superpowers:dispatching-parallel-agents`의 "shared state → sequential" 결정 노드가 왜 그렇게 권고하는지의 구체적 예시

메인 워크스페이스에서 git-crypt가 unlocked 상태라 `.env`가 정상 작동해도,
새 worktree를 만드는 순간 checkout-time filter가 개별 worktree 컨텍스트에서
키를 못 찾아 smudge 단계 전체가 중단됩니다. 사용자 노트 상 **재발성 이슈**
— 한 번 "해결"해도 setup이 휘발되면 다시 나타나는 함정.

## Pattern

**Checkout-time filter가 걸린 repo에서 새 worktree는 자동 부트스트랩이
안 된다.** git-crypt·git-lfs처럼 `.gitattributes`로 `filter=` 매핑된 파일은
각 worktree마다 필터 환경(키 파일 접근, LFS 매니페스트 등)을 별도로
준비해야 하고, `git worktree add`는 그 단계를 대신 해주지 않는다.

AI 에이전트가 `isolation: "worktree"`로 병렬 작업을 띄울 때 이 벽에
부딪히면 현재 harness에는 우회 훅이 없으므로 **sequential 인라인 실행으로
전환**하거나 수동 부트스트랩을 선행해야 한다.

## Code

실패 증상 — 새 worktree 생성이 smudge에서 fatal:

```text
Preparing worktree (checking out 'main')
git-crypt: Error: Unable to open key file - have you unlocked/initialized this repository yet?
error: external filter '"git-crypt" smudge' failed 1
error: external filter '"git-crypt" smudge' failed
fatal: .env: smudge filter git-crypt failed
```

우회 — 수동 부트스트랩 시퀀스:

```sh
# 1) 체크아웃 없이 worktree 골격만 생성
git worktree add --no-checkout /tmp/wt-task main

# 2) worktree 안으로 이동해 git-crypt unlock (키 경로는 환경마다 다름)
cd /tmp/wt-task
git-crypt unlock ~/.config/git-crypt/dotfiles.key

# 3) 이제 필터가 동작하므로 명시적으로 체크아웃
git checkout -- .
```

## When to use

**적용 (sequential fallback 또는 수동 부트스트랩)**:
- `Agent({ isolation: "worktree" })`가 `fatal: .env: smudge filter git-crypt failed`로 종료됐을 때
- git-lfs, git-crypt 등 checkout-time filter가 걸린 repo에서 병렬 AI 에이전트를 띄우려 할 때
- `.gitattributes`에 `filter=` 라인이 있는지 **worktree 만들기 전에** 확인

**미적용 (그대로 worktree 사용 가능)**:
- `.gitattributes`에 `filter=` 매핑이 없는 일반 repo
- 수동 부트스트랩 단계를 skill·harness·setup 스크립트에 훅으로 심어둔 이후
- 단일 에이전트 세션 — isolation 자체가 필요 없는 경우

## Related

- [Issue #153](https://github.com/dEitY719/dotfiles/issues/153) — 4가지 fix plan (auto-unlock 훅 / `--no-checkout` + manual unlock / AGENTS.md 워크어라운드 문서화 / per-repo export-key 자동 import)
- `superpowers:dispatching-parallel-agents` 스킬의 "shared state → sequential" 결정 트리
- `shell-common/tools/integrations/git_crypt.sh`, `shell-common/tools/custom/install_git_crypt.sh` — repo 내 git-crypt 통합 지점 (부트스트랩 훅을 심을 후보 위치)
- [git-worktree-detection.md](./git-worktree-detection.md) — worktree 내부인지 감지하는 반대 방향 패턴, 쌍으로 구성
- git-crypt upstream: https://github.com/AGWA/git-crypt
