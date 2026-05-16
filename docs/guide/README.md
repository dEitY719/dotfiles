# Guide — 사람-팀원 가이드 인덱스

`docs/guide/` 는 dotfiles 사용자·팀원이 읽는 가이드를 모은 디렉토리입니다. AI 에이전트 instruction (영어) 이 아니라 **사람용 한국어 문서** 가 정본입니다.

## 진입 가이드 (루트 레벨 파일)

- [setup.md](./setup.md) — 초기 설치 + `setup.sh` / `install.sh` 실행 순서
- [team-git.md](./team-git.md) — 팀 Git Hooks 가이드 (커밋 표준, branch naming, FAQ)
- [internal-pc.md](./internal-pc.md) — 사내 PC 환경 셋업 차이점
- [dotfiles-setup-guide.html](./dotfiles-setup-guide.html) — `setup.sh` 의 사람 친화 HTML 변환본

## 하위 디렉토리

- [learnings/](./learnings/) — 실제 PR/커밋에서 추출한 짧은 재사용 패턴 (50–80 줄). 한국어, 동료팀 공유 목적. 출처(PR/commit/issue/리뷰 URL) 표기 필수.
- [playbooks/](./playbooks/) — 실행 절차·셋업 순서·운영 체크리스트
- [technic/](./technic/) — 검증된 스택 중심 기술 문서 (수백 줄). 전체 셋업 + tradeoff
- [superpowers-ko/](./superpowers-ko/) — superpowers 플러그인 14 개 스킬의 한글 가이드 (`SKILL_ko.md` + 동료 공유용 `README.md`)

## 디렉토리 분담 (vs 다른 docs 영역)

| 영역 | 위치 | 성격 |
|------|------|------|
| 정책 SSOT | [`docs/.ssot/`](../.ssot/README.md) | 정책 본문 (한국어 + 영어 키워드) |
| 제품 요구사항 | [`docs/requirement/`](../requirement/product-requirements.md) | D/F/NF/O 4-섹션 entry SSOT |
| 피처별 설계 | [`docs/feature/`](../feature/) | 피처 번들 (한 디렉토리 = 한 피처) |
| 사람 가이드 | **이 디렉토리** | 사용자·팀원 학습 자료 |
| 보관 자료 | [`docs/archive/`](../archive/README.md) | 이력·완료·내부 자료 격리 |
