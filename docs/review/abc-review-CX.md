# abc-review-CX

**Reviewer (Model):** GPT-5.2 (Codex CLI)  
**Date:** 2026-02-08  
**Scope:** `docs/review/abc-review-CM.md`, `docs/review/abc-review-R.md` 제안 검토 + 현재 저장소 상태(동일 워크스페이스) 대조

---

## 1. 프로젝트 구조 요약

- `bash/`: bash 초기화 및 bash 전용 모듈
- `zsh/`: zsh 초기화 및 zsh 전용 모듈
- `shell-common/`: 공용 env/aliases/functions/tools/projects
- `tests/`: 테스트
- `docs/`: 문서/리뷰
- `git/`: git 훅/설정
- `.github/workflows/`: CI

---

## 2. SOLID 평가 (각 10점 만점)

- **SRP:** 7/10  
  - 로더/통합이 정리되어 가는 방향은 좋지만, `shell-common/aliases/`에 함수/로직이 섞여 있어 책임 분리가 깨진 부분이 큼.
- **OCP:** 8/10  
  - `shell-common/util/loader.sh` + `shell-common/config/loader.conf` 형태로 확장 포인트가 이미 마련돼 있음.
- **LSP:** 8/10  
  - 래퍼/alias가 원래 커맨드 계약을 크게 깨지 않는 편. 다만 일부 alias 파일이 zsh에서 로딩 실패하면 기대 동작이 달라질 수 있음.
- **ISP:** 7/10  
  - `ux_lib` 단일 파일이 무겁다는 문제 제기는 타당하지만, 당장 분리의 실익 대비 변경면이 큼(테스트/훅 의존 포함).
- **DIP:** 7/10  
  - 공용 로더/설정 파일로 의존이 어느 정도 역전됐으나, 여전히 일부 파일이 `BASH_SOURCE` 등 구체 구현에 직접 의존.

**총점:** 37/50

---

## 3. 검토 결과 (제안 타당성 및 중복/시의성)

- `abc-review-CM.md`의 “플러그인형 로더 + skip 설정 파일” 방향은 타당하며, 현재 저장소에는 이미 `shell-common/util/loader.sh` 및 `shell-common/config/loader.conf` 형태로 상당 부분 반영돼 있다.
- `abc-review-R.md`의 일부 권고(예: `pyproject.toml` 추가, CI 워크플로 도입)는 현재 저장소에 이미 존재해 “새 리팩터링”으로 보기 어렵다.
- 따라서 “추가로 해야 할 일”은 **새 아키텍처를 더 만드는 것**보다, **규칙 위반/호환성 깨짐/가드 누락** 같은 “현재 실제 결함”을 먼저 정리하는 것이 우선이다.

---

## 4. 이슈 (필수 리팩터링만, 심각도별)

### High

1. **`shell-common/aliases/`에 함수/로직 혼재 + 비호환(bashism)**
   - 규칙: `shell-common/AGENTS.md`에 “aliases는 alias만”이 명시돼 있음.
   - 현재: `shell-common/aliases/git.sh`, `shell-common/aliases/core.sh`, `shell-common/aliases/kill.sh`, `shell-common/aliases/directory.sh` 등에서 함수 정의가 발견됨.
   - 특히 `shell-common/aliases/git.sh`는 `declare -f`, `source`, `local`, `BASH_SOURCE` 등으로 POSIX/zsh 호환성이 깨질 수 있고(로딩 실패 시 git alias 전체가 누락), “Portable” 주석과도 불일치.

2. **`shell-common/tools/custom/` 스크립트의 direct-exec guard 누락**
   - 규칙(루트 AGENTS): `shell-common/tools/custom/` 내 스크립트는 소스될 때 실행되지 않도록 guard 필요.
   - 현재: `shell-common/tools/custom/demo_ux.sh` 등 일부가 파일 끝에서 `main`을 바로 호출해, 실수로 `source`될 경우 부작용이 발생할 수 있음.

### Medium

3. **bash/zsh 로딩 로직 중복(드리프트 위험)**
   - `bash/main.bash`는 `shell-common/util/loader.sh`를 사용하지만, `zsh/main.zsh`는 유사 로직을 자체 구현(루프/에러 정책/카운터).
   - 단기적으로는 동작하지만, 로딩 정책이 바뀔 때 bash/zsh가 어긋나기 쉬움.

4. **`bash/setup.sh` vs `zsh/setup.sh` 공통 로직 중복**
   - 제안 자체는 타당. 다만 “필수” 기준에서는 High 이슈(호환성/가드/규칙 위반) 정리 후에 착수하는 편이 안전.

### Low (이번 문서에서 “필수” 제외)

- `ux_lib`를 다중 파일로 분리(ISP 개선): 변경면이 넓고 현재 훅/툴 의존이 있어 우선순위 낮음.
- `VERSION` 파일/배지, README 다이어그램 강화: 품질 개선이지만 기능/안정성 리스크 대비 우선순위 낮음.
- 신규 테스트 대폭 확장: 가치가 크지만, 우선 “로딩 실패/규칙 위반” 제거가 선행돼야 함.

---

## 5. 액션 아이템 (우선순위)

- [ ] **P0:** `shell-common/aliases/`에서 함수 제거(함수는 `shell-common/functions/`로 이동) + aliases는 alias만 남기기
- [ ] **P0:** `shell-common/aliases/git.sh`의 bashism 제거 및 zsh 로딩 실패 방지(UX 로드는 메인 로더에 맡기고 alias 파일은 선언만)
- [ ] **P0:** `shell-common/tools/custom/`의 실행형 스크립트에 direct-exec guard 추가(특히 `demo_ux.sh` 같이 `main`을 즉시 호출하는 파일)
- [ ] **P1:** `zsh/main.zsh`에서 공용 `shell-common/util/loader.sh` 재사용(로딩 정책/skip 설정을 bash와 SSOT로 맞추기)
- [ ] **P2:** `bash/setup.sh`/`zsh/setup.sh` 공통부 추출(`shell-common/tools/custom/setup_common.sh` 등) 및 테스트 보강

---

## 6. 결론

두 문서의 방향성 자체(SOLID/SSOT/중복 제거)는 대체로 타당하지만, 현재 저장소 상태를 기준으로 보면 “새 아키텍처 추가”보다 먼저 해결해야 할 필수 항목은 다음 2가지다:

1. `shell-common/aliases/` 규칙 위반(함수/로직 혼재)과 그로 인한 bash/zsh 호환성 문제
2. `shell-common/tools/custom/` direct-exec guard 누락으로 인한 부작용 위험

이 두 가지를 P0로 정리한 뒤에, zsh 로더 공통화(P1) 및 setup 스크립트 공통화(P2)를 진행하는 순서가 가장 비용 대비 효과가 좋다.
