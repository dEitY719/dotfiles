# Code Review: Commit `0a92083` (global pre-commit hook 리팩토링)

## Reviewer

- Model: GPT-5.2 (Codex CLI)
- Date: 2026-01-19
- Scope:
  - `git/global-hooks/pre-commit`
  - `docs/abc-review-C-improvements.md` (문서 품질/일관성 관점)

## Summary

- Global hook에서 무거운 작업(tox)을 제거하고, staged 파일 기반의 안전 체크(공백/충돌/대용량 등)를 넣은 방향은 좋습니다.
- 다만 “전역 hook”이라는 특성상 OS/파일명/부분 스테이징 케이스에서의 안전성과 휴대성이 더 중요해서, 몇 가지 보완을 권장합니다.

## Strengths

- 전역 hook의 역할을 “가볍고 범용적인 안전 체크 + 프로젝트 hook 위임”으로 명확히 분리했습니다.
- `GIT_HOOKS_SKIP_GLOBAL`, `GIT_HOOKS_DEBUG`로 우회/디버깅 경로를 제공해 운영 편의성이 좋아졌습니다.
- project hook 위임 시 self-execution loop 방지를 넣어 안정성이 좋아졌습니다.

## Issues (By Severity)

### High

1. 파일명 안전성: 공백/특수문자/개행이 포함된 파일명에서 오동작 가능
   - 현재 `STAGED_FILES`를 newline 텍스트로 만들고 `xargs`에 그대로 전달합니다.
   - 결과: 파일명에 공백이 있으면 분리되어 잘못된 경로로 검사하거나, 잘못된 차단/누락이 생길 수 있습니다.
   - 권장: `git diff --cached --name-only -z ...` + `xargs -0` 또는 `while IFS= read -r -d '' ...` 패턴으로 NUL-safe 처리.

2. “staged 기준”이 아니라 “working tree 기준”으로 검사될 수 있음 (부분 스테이징에서 false positive/negative)
   - `grep`가 실제 파일 경로를 읽기 때문에, index(스테이징) 내용이 아니라 현재 워킹트리 내용을 스캔합니다.
   - 부분 스테이징(`git add -p`)일 때 특히 문제가 됩니다.
   - 권장:
     - 텍스트 패턴 검사(시크릿/충돌/디버그)는 `git grep --cached` 사용, 또는 `git show :path | grep ...`로 index 내용을 검사.

3. macOS 휴대성: `readlink -f` 미지원 환경에서 loop 방지 정확도가 떨어질 수 있음
   - `readlink -f`는 GNU coreutils 기준이며, 기본 macOS(BSD readlink)에서는 `-f`가 동작하지 않는 경우가 많습니다.
   - 현재는 실패 시 `echo "$0"`로 fallback 되지만, symlink/realpath 비교 정확도가 낮아집니다.
   - 권장: `realpath`(존재 시) → Python(`os.path.realpath`) → `pwd -P` 기반의 단계적 fallback 함수로 통일.

### Medium

1. `git diff --cached --check`를 여러 번 호출 (불필요한 중복 비용)
   - 결과 출력/라인수 계산을 위해 동일 명령을 2~3회 실행합니다.
   - 권장: 결과를 변수에 1회 저장하고 재사용.

2. 대용량 파일 체크 구현이 비용/정확성 측면에서 애매함
   - `find "$REPO_ROOT/{}" -size +10M`는 파일당 `find` 호출이라 비용이 커질 수 있습니다.
   - 또한 index blob 크기가 아니라 워킹트리 파일 크기를 봅니다(부분 스테이징/리네임/필터에서 혼선 가능).
   - 권장: index blob 크기(`git cat-file -s :path`) 기반으로 판단하거나, 최소한 NUL-safe + `stat` 기반으로 단순화.

3. “텍스트만 검사” 주석과 달리 바이너리 파일도 grep 대상으로 포함될 수 있음
   - 권장: `grep -I`(바이너리 무시) 또는 `git grep --cached -I` 사용.

### Low

1. 출력/문서에서 유니코드 심볼(체크마크/경고 아이콘 등) 사용
   - 이 레포의 “No Emojis” 정책과 충돌 소지가 있습니다.
   - 권장: `[OK]`, `[WARN]`, `[FAIL]` 같은 ASCII 마커로 통일.

2. `echo -e` 의존
   - 쉘/환경에 따라 `-e` 해석이 달라질 수 있어 메시지 출력이 깨질 수 있습니다.
   - 권장: `printf`로 일관되게 출력(또는 hook에 대한 예외 정책을 문서화).

## Docs Feedback (`docs/abc-review-C-improvements.md`)

- 문서가 매우 상세해서 “왜 tox를 전역에서 빼야 하는지”가 잘 전달됩니다.
- 다만 `docs/abc-review-G.md`가 현재 비어있다면(0 bytes) “검토 기준” 참조가 독자를 혼란스럽게 할 수 있어, (a) 요약을 문서에 포함하거나 (b) 참조를 조정하는 편이 좋습니다.

## Action Items (Suggested)

- P0: NUL-safe staged 파일 처리(`-z`/`-0`)로 전환.
- P0: 패턴 검사(시크릿/충돌/디버그)를 `git grep --cached`로 전환해 index 기준으로 검사.
- P1: `readlink -f` 휴대성 개선용 `realpath` helper 도입.
- P1: 중복 `git diff --cached --check` 호출 제거.
- P2: 출력 마커 ASCII 통일 + hook 출력 정책(ux_lib 사용 여부) 문서화.
