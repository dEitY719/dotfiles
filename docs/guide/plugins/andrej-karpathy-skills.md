# andrej-karpathy-skills 플러그인 가이드

LLM 코딩에서 반복되는 실수(과잉구현·불필요한 리팩터·숨긴 가정·모호한 성공 기준)를
줄이기 위한 행동 지침 플러그인. Andrej Karpathy가 정리한 LLM 코딩 함정 관찰에서 파생됐다.

- Marketplace: [`forrestchang/andrej-karpathy-skills`](https://github.com/forrestchang/andrej-karpathy-skills)
- 이 dotfiles 저장소 SSOT: `claude/plugin/plugins.json` (`andrej-karpathy-skills@karpathy-skills`), `claude/plugin/marketplaces.json`

## 1. 설치 방법

```
/plugin marketplace add forrestchang/andrej-karpathy-skills
/plugin install andrej-karpathy-skills@karpathy-skills
/reload-plugins
```

`claude/plugin/plugins.json`·`marketplaces.json`은 `plugin-sync.sh` / `plugin-sync-session.sh` hook이
세션 종료 시 자동으로 동기화한다 (`claude/AGENTS.md` → "Plugin Manifest" 참조) — 수동으로 SSOT 파일을
편집할 필요 없음. 신규 PC에는 `./claude/plugin/restore.sh`로 일괄 복원된다.

## 2. 스킬 설명

| 스킬 | 성격 | 하는 일 |
|------|------|---------|
| `karpathy-guidelines` | 지속 지침 (코드 작성/리뷰/리팩터 시) | 코딩 전 가정·트레이드오프를 명시(assume 금지), 요청된 최소 코드만(단순성 우선), 요청과 무관한 부분은 건드리지 않는 외과적 수정, 검증 가능한 성공 기준을 세워 통과까지 반복 — 네 가지 행동 규칙을 강제 |

이 플러그인은 스킬 1개로 구성된다. `karpathy-guidelines`는 파일을 직접 수정하지 않는
행동 지침(behavioral guideline)으로, 다른 코딩 작업의 품질 가드레일로 함께 적용한다.
사소한 작업에는 판단에 따라 생략 가능(속도보다 신중함으로 편향된 지침이라는 점을 명시).

## 3. 사용법 예제

**기능 구현 전 가정·단순성 점검**
```
/karpathy-guidelines
"이 모듈에 검증 로직 추가해줘"
→ 가정을 먼저 명시하고 모호하면 질문, 요청 범위 밖 추상화/설정은 배제,
  "잘못된 입력에 대한 테스트 작성 → 통과" 형태의 검증 가능한 목표로 변환
```

**기존 코드 편집 시 외과적 수정 강제**
```
/karpathy-guidelines
"버그 수정하면서 근처 코드도 정리해줘"
→ 인접 코드/포맷은 손대지 않음, 내 변경이 만든 orphan(미사용 import 등)만 정리,
  기존 dead code는 삭제 대신 언급만 — 변경된 모든 줄이 요청에 직접 대응하는지 검증
```

## 참고

- 트레이드오프: 이 지침은 속도보다 신중함(caution)으로 편향된다. 정말 사소한 작업이면
  판단에 따라 완화한다.
- 정확성 버그·보안·성능 리뷰는 이 지침의 범위 밖 — `/code-review`로 별도 확인.
