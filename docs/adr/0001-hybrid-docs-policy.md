---
status: approved
---

# ADR-0001: docs 문서 정책 하이브리드 확정

- **일자**: 2026-06-26
- **관련 이슈/PR**: #1027 (기반 결정: #660 5-tier 구조)

## 맥락 (Context)

다른 제품 프로젝트(avatar-system 을 가진 앱)가 채택한 "폴더=문서 종류,
파일명=기능" 의 7-폴더 kind-split 구조(`adr/`·`product/`·`design/`·
`architecture/{system,features}`·`testing/`·`guides/`·`public/`)를
이 dotfiles 레포에 도입할지 검토했다.

정통 방법론(IEEE 830, ISO/IEC/IEEE 12207)과 Docs-as-Code 트렌드를 반영해
docs 정책을 한층 견고히 하려는 요구가 배경이다.

## 결정 (Decision)

**전면 이주가 아니라, 기존 #660 5-tier 구조를 유지하면서 고가치·저위험
아이디어만 선별 채택하는 하이브리드 방식**을 채택한다. 도입 항목:

1. `adr/` 신설 — 굵직한 아키텍처 결정의 불변 로그.
2. front-matter `status:` 메타데이터 규칙 (`draft`/`review`/`approved`/`deprecated`).
   적용 대상: `requirement/`, `feature/`, `adr/`.
3. 파일명 kebab-case 린터 — `mise run lint` 에 docs 파일명 규칙 검사 추가, CI 게이트 포함.
4. ADR 상호링크 규칙 — `feature/` 문서에서 중대한 기술 전환 시 관련 ADR 번호 링크.
5. `docs/AGENTS.md` 정책을 5-tier → 6-tier (`adr/` 포함)로 갱신.

## 고려한 대안 (Alternatives)

**참조 구조 전면 이주** — 채택하지 않았다. 세 축에서 충돌한다:

1. **철학 충돌 (가장 중요)** — 이 레포는 #660 에서 `feature/<name>/` =
   "한 디렉토리 = 한 피처" 번들 철학을 확정했다. 참조 구조는 정반대로 한
   피처의 문서를 종류별로 흩뿌리고 파일명으로 묶는다. 채택 시 13개 feature
   번들을 전부 해체해야 하고 "관련 문서가 한곳에" 라는 장점을 잃는다.
2. **기존 자산이 갈 곳이 없음** — `.ssot/` 는 스킬·CLAUDE.md·AGENTS.md
   36개 파일에서 참조된다. 참조 구조엔 `.ssot/`·`requirement/`·`archive/`
   자리가 없어 대규모 링크 깨짐 + 마이그레이션 비용이 발생한다.
3. **도메인 불일치** — 셸 도구 dotfiles 레포다. 참조의 `product/`·`design/`·
   `testing/` 이 전제하는 산출물이 거의 없어 의례적 빈 폴더가 될 위험이 크다.

## 결과 (Consequences)

- **긍정**: 결정 이력이 `adr/` 한곳으로 일원화. `status:` 로 유효 SSOT 판별
  가능. 파일명 일관성을 CI 가 강제. 기존 5-tier 의 모든 장점·경로 보존.
- **경로 불변**: `.ssot/`·`requirement/`·`guide/`·`feature/`·`archive/` 그대로 —
  기존 36개 `docs/.ssot` 참조 무손상. `adr/` 는 순수 신설이라 깨질 링크 없음.
- **부정/후속**: 기존 docs 파일명에 다수의 kebab-case 위반이 존재한다. 린터는
  신설 tier(`adr/`·`requirement/`)만 강제하고 나머지는 warn-only 로 시작하며,
  레거시 일괄 정리는 별도 이슈로 분리한다.
- **롤백**: 각 항목이 독립적이라 항목 단위 revert 가능. 린터는 mise 태스크 +
  CI 단계 제거로 즉시 비활성화.
