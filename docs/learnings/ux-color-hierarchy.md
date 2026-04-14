# UX 색 계층으로 "읽는 순서" 만들기

## Context

- **출처**: [PR #130](https://github.com/dEitY719/dotfiles/pull/130) — `gwt teardown` 의 path-arg 에러 메시지를 컨텍스트 기반 가이드로 교체
- **커밋**: `de96848` (초기 설계), `6ea9531` (리뷰 반영)
- **파일**: `shell-common/functions/git_worktree.sh:592-624`

terse 한 1–2줄 에러로는 사용자가 **왜 잘못했는지**를 재학습하지 못하는 경우가
많습니다. 이 PR 에서 멀티라인 에러를 설계하면서 색을 3–4단계로 나눠 시각적
"읽는 순서"를 강제하는 방법을 검증했습니다.

## Pattern

`ux_lib` 의 semantic 함수를 **색 강도 순서대로** 호출해 시선을 자연스럽게 이동시킴:

1. **빨강 (`ux_error`, ❌, bold)** — 최상단 주의 환기 ("뭔가 잘못됐다")
2. **시안 (`ux_info`, ℹ️)** — 현재 상태 사실 ("당신은 지금 X 에 있다")
3. **노랑 (`ux_warning`, ⚠️)** — 지키지 못한 원칙 재강조 ("이 명령은 Y 규약이다")
4. **파랑 (`ux_bullet`, ◆)** — 실행 가능한 대안 ("이렇게 하세요")

한 블록에 3–4개 색이 동시에 있어도 혼잡하지 않은 이유는 **순서가 고정**되어
있기 때문 — 사용자의 눈은 빨강을 먼저 잡고, 이후 아래로 내려가며 원인·대안을
순차적으로 읽습니다.

## Code

```sh
ux_error "'gwt teardown' does not accept a path argument."
echo ""
# 사실: 현재 상태
ux_info "You are in:  main repo ($_gwt_loc)"
ux_info "You passed:  $1"
echo ""
# 원칙 재강조
ux_warning "'gwt teardown' is SELF-CLEANUP — it tears down the worktree"
ux_warning "you are currently inside (cd into it first, then run)."
echo ""
# 실행 가능한 대안 2개
ux_info "Did you mean:"
ux_bullet "cd \"$1\" && gwt teardown     # full cleanup"
ux_bullet "gwt remove \"$1\"             # remove only"
```

## When to use

**적용하기 좋은 경우**
- 멀티라인 에러·가이드 메시지 (3줄 이상)
- 사용자가 같은 실수를 반복할 가능성이 있는 상황
- "문제 → 원인·상태 → 원칙 → 대안" 플로우로 설명이 가능할 때

**과할 수 있는 경우**
- 단순 1줄 에러 (`ux_error` 하나면 충분)
- 성공 메시지 — 순서 유도 불필요, `ux_success` 하나로
- 빠른 진행이 핵심인 progress 표시 — 색 계층은 인지 부하를 늘림

## Related

- **가이드라인**: [`shell-common/tools/ux_lib/UX_GUIDELINES.md`](../../shell-common/tools/ux_lib/UX_GUIDELINES.md) — Color Semantics 섹션
- **스킬**: [`claude/skills/ux-guidelines/README.md`](../../claude/skills/ux-guidelines/README.md)
- **구현 참조**: `shell-common/functions/git_worktree.sh:592-624` (fix/gwt-teardown-path-error-ux 브랜치)
- **ux_lib 함수 정의**: `shell-common/tools/ux_lib/ux_lib.sh:131-181`
