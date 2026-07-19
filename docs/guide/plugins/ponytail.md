# ponytail 플러그인 가이드

과도한 엔지니어링(over-engineering)을 막는 "게으른 시니어 개발자" 페르소나 플러그인.
YAGNI → stdlib → native → 한 줄 → 최소 구현 순으로 가장 단순한 해법을 강제한다.

- Marketplace: [`DietrichGebert/ponytail`](https://github.com/DietrichGebert/ponytail)
- 이 dotfiles 저장소 SSOT: `claude/plugin/plugins.json` (`ponytail@ponytail`), `claude/plugin/marketplaces.json`

## 1. 설치 방법

```
/plugin marketplace add DietrichGebert/ponytail
/plugin install ponytail@ponytail
/reload-plugins
```

`claude/plugin/plugins.json`·`marketplaces.json`은 `plugin-sync.sh` / `plugin-sync-session.sh` hook이
세션 종료 시 자동으로 동기화한다 (`claude/AGENTS.md` → "Plugin Manifest" 참조) — 수동으로 SSOT 파일을
편집할 필요 없음. 신규 PC에는 `./claude/plugin/restore.sh`로 일괄 복원된다.

## 2. 스킬 설명

| 스킬 | 성격 | 하는 일 |
|------|------|---------|
| `ponytail` | 지속 모드 (기본 `full`) | 코드 작성/수정 시 가장 단순한 해법을 강제. `lite`/`full`/`ultra` 3단계 |
| `ponytail-review` | 일회성, diff 대상 | 지금 diff에서 과잉설계만 콕 집어 리뷰 (`delete:`/`stdlib:`/`native:`/`yagni:`/`shrink:` 태그) |
| `ponytail-audit` | 일회성, 저장소 전체 | 레포 전체를 훑어 삭제/단순화 가능한 곳을 랭킹 리스트로 보고 |
| `ponytail-debt` | 일회성, 이력 추적 | 코드 내 `ponytail:` 주석(의도적 단축)을 모아 부채 장부로 정리 |
| `ponytail-gain` | 일회성, 스코어보드 | 벤치마크 중앙값 기준 절감 효과(코드량/비용/속도)를 표시 |
| `ponytail-help` | 일회성, 레퍼런스 | 위 전체 요약 카드 + 설정법 안내 |

공통 규칙: `ponytail`/`ponytail-review`/`ponytail-audit`는 "stop ponytail" 또는 "normal mode"라고 말하면 해제된다.
review/audit/debt/gain/help는 파일을 수정하지 않는 보고 전용(read-only) 스킬이다.

## 3. 사용법 예제

**평소 코딩 (지속 모드)**
```
/ponytail
"API 응답 캐시 추가해줘"
→ @lru_cache(maxsize=1000) 한 줄로 처리, 커스텀 캐시 클래스는 스킵 사유와 함께 생략
```

**PR 올리기 전 diff 점검**
```
/ponytail-review
→ L12-38: stdlib: 27줄짜리 EmailValidator 클래스. "@" 포함 여부 1줄로 충분.
→ net: -26 lines possible.
```

**레포 전체 대청소 대상 찾기**
```
/ponytail-audit
→ yagni: AbstractRepository, 구현체 1개뿐. repo.py
→ net: -230 lines, -3 deps possible.
```

**미뤄둔 단축 목록 확인**
```
/ponytail-debt
→ auth.py:42, global lock 사용. ceiling: 단일 프로세스. upgrade: 멀티프로세스 배포 시.
→ 3 markers, 1 with no trigger.
```

**효과 확인 / 전체 명령어 참조**
```
/ponytail-gain   # 벤치마크 기반 절감 스코어보드
/ponytail-help   # 전체 스킬·레벨·설정 레퍼런스 카드
```

## 참고

- 기본 모드 변경: `PONYTAIL_DEFAULT_MODE` env var 또는 `~/.config/ponytail/config.json`의 `defaultMode`
- 정확성 버그/보안/성능은 ponytail-review·ponytail-audit 범위 밖 — `/code-review`로 별도 리뷰
