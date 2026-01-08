# shell-common 리팩터링 계획 (P0/P1)

목표: `shell-common/`을 단순·견고한 구조로 재정비하여 오배치(AGENTS.md Common Mistakes) 방지, 자동 로딩 일관성 확보, 1st-party 커맨드와 3rd-party 래퍼를 명확히 분리.  
P1 = 디렉터리/명명 정리, P0 = robust 로딩 모델(자동/명시 실행 구분, bash/zsh 분리).

## 현재 문제

- `tools/external/` 이름이 모호함: git/apt 같은 래퍼가 우리 코드처럼 보임.
- `tools/custom/` vs `functions/` vs `aliases/` 경계가 헷갈려 잘못 이동되는 사례(AGENTS Common Mistakes 반복).
- `devx` 이중 위치(`functions/devx.sh` vs `tools/custom/devx.sh`)로 기여자가 혼동.
- 로딩 모델이 암묵적이라 무엇이 auto-source 되는지 모호하고, 테스트는 경로를 하드코딩.
- AGENTS.md 실수 패턴이 제한적: 하드코딩 경로, external/custom 혼동, bash-only 구문 미포함.

## 설계 원칙

- 단순한 멘탈 모델: “자동 소스되는 커맨드는 한 곳, 실행 스크립트는 다른 곳.”
- 소유권 분리: 1st-party와 3rd-party가 눈에 띄게 구분.
- bash/zsh 호환성과 기존 로딩 순서(Env → UX → Alias → App) 유지.
- 점진적 마이그레이션 + 호환성 심(symlink)으로 경로 변경 리스크 축소.

## 제안 대상 레이아웃

```
shell-common/
  env/
  ux/                    # 신규: UX 헬퍼 통합(ux_lib 이전/별칭)
  functions/             # 자동 소싱되는 유저 커맨드/헬퍼
  aliases/               # functions/를 가리키는 얇은 별칭
  tools/
    custom/              # 1st-party 실행 스크립트(현행 명칭 유지)
    integrations/        # 구 tools/external (3rd-party 래퍼, 통합 의미로 명확화)
    ux_lib/              # 당분간 유지, 이후 ux/로 흡수 가능
  projects/
```

- `functions/`: 자동 소싱 함수만(bash/zsh 안전). 예) `devx`, `my_help`.
- `tools/custom/`: 우리가 만든 실행 스크립트(자동 소싱 금지, 명시적 실행).
- `tools/integrations/`: 외부 CLI 래퍼(필요 시에만 소싱, 아니면 함수 경유 실행).
- `ux/`: UX 헬퍼의 단일 거점(점진 이전).

## 마이그레이션 플랜

1. **인벤토리/분류**: `functions`, `tools/custom`, `tools/external`, `aliases` 전체를 ①자동 소싱 함수 ②1st-party 실행 스크립트 ③통합 래퍼로 태깅. `devx` 같은 중복 명칭은 역할을 명확히 표기(예: wrapper).
2. **디렉터리 생성/이동**: `tools/integrations/` 생성 후 `external/*`→`integrations/`. `tools/custom/` 명칭은 유지. 필요 시 `ux/` 생성(ux_lib 점진 이전).
3. **로더 수정**: `bash/main.bash`, `zsh/main.zsh`에서 자동 소싱 대상을 `functions/`, `aliases/`, `tools/integrations/`(필요 시)로 한정. `tools/custom/`은 절대 자동 소싱 금지(명시 실행 전용).
4. **별칭/경로 정리**: 외부 경로(`tools/external`) 참조를 `tools/integrations`로 변경. `source`는 `$SHELL_COMMON/tools/custom` 또는 `/integrations` 사용. 필요 시 `tools/external` 심을 단기 유지.
5. **AGENTS.md 강화**: Common Mistakes에 하드코딩 경로, external/custom 혼동, bash-only 구문, 관심사 혼합 추가. Decision Tree에 `custom/`, `integrations/` 반영.
6. **테스트/문서 업데이트**: 하드코딩 경로가 `tools/external`을 참조하는 부분을 `tools/integrations`로 수정. README/헬프 출력 경로 갱신. 필요 시 `devx` wrapper/명칭도 업데이트.
7. **호환성 심(옵션, 기간 한정)**: `tools/external -> integrations` 심 제공. 모든 참조 수정/테스트 통과 후 제거 시점 명시(한 릴리스 사이클 제안).
8. **검증**: `devx test` 전체 실행. bash/zsh에서 `declare -f devx`, `mytool_help`, 통합 래퍼(`git_help` 등) 스모크. 인터랙티브 가드(`[[ $- == *i* ]]`) 확인. 필요 시 bash/zsh 인터랙티브 수동 확인(apt-help, devx --help).

### 실행 페이즈(체크리스트)

- Baseline: 현 상태에서 `devx test` 통과 확인.
- Phase 1: 디렉터리 생성 및 이동(`external`→`integrations`), 필요 시 심 설치.
- Phase 2: 로더 수정(bash/zsh), alias/경로 수정(mytool 헬프 포함).
- Phase 3: AGENTS/README/헬프/테스트 경로 업데이트 + Decision Tree 확장.
- Phase 4: 선택적 bash/zsh 특화 파일 이동(필요 시).
- Phase 5: `devx test` 재실행 + 인터랙티브 스모크(bash/zsh).

## 열린 결정

- `tools/ux_lib/`를 지금 `ux/`로 옮길지, 심 뒤에 둘지?
- integrations를 자동 소싱할지, `functions/` 경유 실행할지? (권장: 최소 래퍼만 소싱, 무거운 로직은 실행 스크립트).
- 호환성 심 유지 기간? (제안: 한 릴리스 사이클).
- `devx` wrapper를 명시적 이름(예: `devx_wrapper.sh`)으로 둘지, functions 쪽으로 흡수할지?

## 리스크/대응

- **경로 변경으로 테스트/툴 깨짐**: 심 + 테스트 동시 수정, 하드코딩 경로(테스트/헬프/alias) 즉시 업데이트.
- **잘못된 자동 소싱**: 로더에서 `functions/`·`integrations/`만 소싱하도록 강제, `custom/` 실행 스크립트는 제외.
- **bash/zsh 드리프트**: 두 셸 모두에서 로더 검증, `$SHELL_COMMON` 기반 소싱 유지. bash-only 구문은 bash/로 이동.
- **devx 이중 존재 혼동**: 역할을 문서화하고 검색 용이하게 이름 변경 또는 흡수.

## 다음 액션

- 목표 레이아웃/플랜 승인 후, 심/테스트 업데이트를 같은 PR에서 수행하여 다운타임 없이 단계 실행. 승인 시 위 페이즈에 따라 즉시 착수.\*\*\*
