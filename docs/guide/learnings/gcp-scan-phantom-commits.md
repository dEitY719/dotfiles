# gcp-scan phantom 커밋 자기참조 루프

## Context

PR·이슈 추적: Discussion [#927](https://github.com/dEitY719/dotfiles/discussions/927),
관련 이슈 #763, #903, #907, #908, #913, #916.

`gcp scan` 이 `upstream/main` → `origin/main` cherry-pick 동기화를 수행할 때,
**자기 자신을 배포하는 도구** 특성 때문에 fix 커밋이 phantom 커밋 뒤에 갇혀
일주일·10회 이상 같은 자리에서 충돌이 반복된 사례.

## Pattern

"fix 자체를 배포하는 도구"는 fix 커밋이 phantom 커밋 뒤에 갇히면
자기 참조 루프에 빠진다:

```
phantom 커밋이 충돌로 막힘
    → 뒤에 있는 fix 커밋이 origin에 진입 불가
        → 다음 scan도 옛날 코드로 실행
            → 또 phantom 커밋에서 충돌
                → (무한 반복)
```

루프 진단 신호: **같은 커밋에서 3회 이상 충돌** + 충돌 해결 후 working tree가
HEAD와 완전히 동일 (net-zero).

## Code

### 1. `--continue` vs `--skip` 판별

cherry-pick 충돌 해결 후 HEAD와 동일하면(net-zero) `--continue`는 실패한다.
반드시 `--skip`.

```bash
git diff --quiet HEAD -- <충돌파일> \
  && echo "EMPTY → --skip" \
  || echo "HAS CHANGES → --continue"
```

### 2. phantom 커밋 수동 우회 절차

```bash
# 1) phantom을 --skip으로 건너뜀
git cherry-pick --skip

# 2) 뒤에 갇힌 실 커밋들을 수동 cherry-pick
for sha in <sha1> <sha2> ...; do
  git cherry-pick "$sha" && echo "OK $sha" || { echo "CONFLICT $sha"; break; }
done

# 3) fix 코드 진입 확인 후 push
git push origin main
```

### 3. `git cherry-pick -n` no-op 판정

기존 텍스트 휴리스틱(L2/L3) 대신 git 머지 엔진 자체로 판정:

```bash
# staged diff가 비어있으면 no-op (이미 HEAD에 있는 내용)
git cherry-pick -n <sha> 2>/dev/null
git diff --quiet --cached && echo "NO-OP → skip" || echo "REAL WORK → keep"
git cherry-pick --abort 2>/dev/null; git reset --hard HEAD
```

### 4. Cheat sheet

| 상황 | 진단 | 해결 |
|---|---|---|
| 같은 커밋 3회 이상 충돌 | phantom 자기참조 루프 의심 | 수동 `--skip` → 뒤 커밋 수동 적용 |
| 충돌 해결 후 `--continue` 거부 | net-zero (빈 커밋) | `git cherry-pick --skip` |
| scan fix가 적용 안 됨 | phantom이 fix 앞에 있어서 | 위 수동 우회 절차 실행 |
| `git cherry` 출력에 `+` | 내용이 달라서 중복 미인식 | preflight probe로 no-op 확인 |

## When to use

- cherry-pick 충돌이 3회 이상 같은 커밋에서 반복될 때
- 충돌 해결 후 `git diff HEAD -- <file>` 가 비어있을 때
- 배포 스크립트·CI·package manager 자체 업그레이드 등 "자기 자신을 수정하는 도구" 전반

**반대 조건:** 충돌 파일에 실제 내용 차이가 있으면 정상 해결 후 `--continue`.

## Related

- `shell-common/functions/gcp_scan.sh` — `_gcp_scan_preflight_is_noop` (line ~40)
- Discussion #927 (원본 전체 분석·로그 포함)
- #913 (preflight probe 구현 PR)
