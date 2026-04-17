# Paste-Ready JIRA Stories (2026 AI Enable)

JIRA 티켓 생성 시 **복사/붙여넣기 전용** 파일들. 원본 템플릿(`docs/company/JIRA_Story_draft_2026.md`)에서 파트원 letter 를 치환하여 확장한 완성형.

## 파일 구조

| 영역 | 파일 | Story 수 | 비고 |
|------|------|---------|------|
| **파트 독립 영역** | `part_independent.md` | 9 | P-1..P-5 (평가 4 + tracking 1) + K-1..K-4 — letter 치환 없음 |
| **개인별 독립 영역** | `AIE-γ.md` ~ `AIE-ψ.md` (9개) | 4 × 9 = 36 | 각 파트원별 M-1..M-4 |
| **합계** | 10개 파일 | **45 Story** | |

## 사용 방법

1. **파트 Story (P-1..P-4) 생성 시**: `part_independent.md` 열고 해당 Story 섹션의 `### Summary` 와 `### Description` 을 각각 복사해서 JIRA 에 붙여넣기.
2. **핵심제품 Story (K-1..K-4) 생성 시**: 동일 파일의 K-섹션 사용. Parent 는 P-1 의 JIRA key 로 설정.
3. **파트원 Story (M-1..M-4) 생성 시**: 해당 파트원의 `AIE-{letter}.md` 파일 열고 4개 Story 각각 복사.

## M-1 주의사항 — K-담당 번호 치환 필요

M-1 Summary 는 `[K?-{letter}]` 로 되어 있음. `?` 를 담당 핵심제품 번호(1~4)로 치환 필수:
- Agent App Store 담당 → `[K1-δ]` 형태
- Alpha Agent 담당 → `[K2-δ]` 형태
- Cowork 담당 → `[K3-δ]` 형태
- MCP/Skill Hub 담당 → `[K4-δ]` 형태

K-담당 배정은 `AIE_member_code_mapping.md` (PL 전용) 의 "담당 제품 매핑" 섹션 참조.

## 파일 명명 규칙

- 파일명은 파트원의 Greek letter 코드 기반 (`AIE-δ.md` 등)
- 이름 노출 없음 — 실명 매핑은 `AIE_member_code_mapping.md` 에만 존재

## 재생성 절차

원본 템플릿(`JIRA_Story_draft_2026.md`)이 수정되면 이 파일들은 **자동 갱신되지 않음**. 다음 상황에서 수동 재생성 필요:

- Description 본문 변경 (평가 기준, 권한 Level, 성과 측정 등)
- Summary 패턴 변경
- 파트원 추가/letter 재배정

재생성 방법: `JIRA_Story_draft_2026.md` 의 해당 Story Description 블록을 복사해서 이 파일들에 반영. 연 1회성 작업이므로 스크립트 자동화 대신 수작업 진행.

## 참고 문서

- **원본 템플릿**: `../JIRA_Story_draft_2026.md`
- **letter ↔ 실명 매핑**: `../AIE_member_code_mapping.md` (PL 전용)
- **기획/의사결정 이력**: GitHub Issue #142
