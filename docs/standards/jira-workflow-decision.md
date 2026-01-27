# Jira 워크플로우 결정 분석: "Jira First" vs "Code First"

**작성자**: 팀
**일시**: 2026-01-27
**용도**: 팀 검토 및 합의

---

## 핵심 질문

> **작업을 시작할 때, Jira 티켓(SWINNOTEAM-906)을 먼저 생성한 후 Git 작업을 시작해야 하는가?**

---

## 두 가지 접근 방식

### 방식 A: "Jira First" ⭐⭐⭐⭐⭐ (권장)

**워크플로우**:
```
1. Jira에서 티켓 create
   Status: To Do
   예: SWINNOTEAM-906 생성 (회사 키 형식)

2. Git 작업 시작 (키를 소문자로 변환)
   git checkout -b swinnoteam-906-feature

3. 개발 + 커밋 (키를 대문자로 사용)
   git commit -m "[SWINNOTEAM-906] feat: ..."

4. Hook 자동 실행
   ↓
   work_log.txt 기록

5. PR/Merge 후 Jira 업데이트
   Status: Done
```

**장점**:
- ✅ **역할 명확**: Jira = 계획, Git = 실행
- ✅ **자동 추적**: work_log.txt 자동 생성
- ✅ **증거 남음**: Git commit = 작업 증거
- ✅ **주간보고 자동화**: Git 로그 → 주간보고 변환 가능
- ✅ **팀장 병목 제거**: 개인이 티켓 생성
- ✅ **Jira ↔ Git 일관성**: 1:1 매핑
- ✅ **다중 프로젝트 추적**: SWINNOTEAM-906 vs SWINNOTEAM-907 구분 명확
- ✅ **자동화 최대화**: make-jira 스킬로 Jira 자동 업데이트

**단점**:
- ⚠️ Jira 티켓 생성 필수 (약 2-3분)
- ⚠️ "생각만 하다가" Jira가 쌓일 가능성
- ⚠️ 소규모 작업(1-2줄 수정)도 티켓 필요할 수 있음

---

### 방식 B: "Code First"

**워크플로우**:
```
1. 코드 작업 시작 (Jira 미생성)
   git checkout -b temp-feature

2. 개발 + 커밋
   git commit -m "WIP: feature description"

3. 작업 완료 후 Jira 생성
   SWINNOTEAM-906 create

4. 커밋 수정 (선택)
   git commit --amend -m "[SWINNOTEAM-906] ..."
```

**장점**:
- ✅ 빠른 시작 (Jira 생성 불필요)
- ✅ 작은 작업에 유연함

**단점**:
- ❌ Git ↔ Jira 시간 차이 발생
- ❌ 커밋 로그에 키 미포함 (추적 어려움)
- ❌ work_log.txt에 기록 안 됨
- ❌ 주간보고 자동화 불가능
- ❌ 팀장이 나중에 Jira 정리해야 함
- ❌ "누가 뭘 했는지" 추적 어려움

---

## 당신 회사 상황 분석

| 요소 | 현황 | 방식 A 적합도 |
|------|------|------------|
| **Jira 필수 | ✅ 주간보고 필수 | ✅✅✅ 매우 적합 |
| **팀장 역할** | ✅ Jira/Confluence 관리 | ✅✅✅ 병목 해결 |
| **다중 프로젝트** | ✅ A, B, C, dotfiles | ✅✅✅ 추적 필수 |
| **Copy-Paste 문제** | ✅ 현재 비효율 | ✅✅✅ 자동화로 해결 |
| **팀 규모** | 팀장 + 개발자(s) | ✅✅✅ 적절 |

**결론**: **방식 A "Jira First" 강력 권장** ⭐⭐⭐⭐⭐

---

## 실행 계획

### Phase 1: 팀 합의 (이번 주)
- [ ] 이 문서 팀과 공유
- [ ] Jira First 워크플로우 discussion
- [ ] SWINNO-XXX 키 포맷 확인
- [ ] 예외 케이스 정의 (예: 1줄 버그 수정)

### Phase 2: 표준화 (1주)
- [ ] docs/standards/commit-message-standard.md 확정
- [ ] 팀원 온보딩 (15분)
- [ ] 첫 3개 커밋으로 practice

### Phase 3: 자동화 (2-3주)
- [ ] make-jira 스킬 구현
- [ ] work_log.txt → Jira 업데이트
- [ ] 주간보고 자동 생성

---

## 예외 케이스 (팀 논의 필요)

### Q1: 1줄 수정도 Jira 티켓이 필요한가?

**제안**:
- `[HOTFIX] type: description` (Jira 키 없음)
- Hook이 `[HOTFIX]` 감지하면 work_log.txt 기록
- 나중에 팀장이 batch 처리

### Q2: 외부 요청 작업은?

**제안**:
- 반드시 Jira 티켓 create
- 요청자가 Jira에 입력하도록 요청

### Q3: 긴급 버그는?

**제안**:
- Emergency Jira 템플릿 만들기 (생성 1분 이내)
- 우선순위 High로 설정

---

## 팀 체크리스트

### 검증해야 할 사항

- [ ] 현재 Jira 프로세스와 충돌 없는가?
- [ ] SWINNO-XXX 키 포맷이 맞는가?
- [ ] 누가 Jira 티켓을 create할 권한이 있는가?
- [ ] 티켓 생성 프로세스가 2-3분 이내인가?
- [ ] Jira Status workflow (To Do → In Progress → Done) 확인?
- [ ] 예외 케이스 (핫픽스, 긴급)는 어떻게 처리할 것인가?

### 동료 의견 수집

**CX(실무 중심)에게**:
- "Daily 루틴이 현실적인가?"
- "2분 오버헤드가 허용 가능한가?"

**G(메타포 중심)에게**:
- "'Jira First' 메타포가 적절한가?"
- "Work Log 추적성이 명확한가?"

**O(간결함 중심)에게**:
- "체크리스트가 너무 길지 않은가?"
- "더 단순하게 할 수 있는가?"

---

## 최종 권장사항

### 결정

```
✅ 채택: "Jira First" 워크플로우

이유:
1. 당신 회사의 Jira 주간보고 필수 = 자동화 효과 극대
2. 팀장 병목 해결 (개인이 티켓 생성)
3. 다중 프로젝트 추적 필수 (A, B, C, dotfiles)
4. Copy-Paste 비효율 80% 감소
5. Git ↔ Jira ↔ Confluence 자동 연결
```

### 당신이 해야 할 일

1. 이 문서를 팀과 공유
2. 팀 discussion 진행 (1시간)
3. 피드백 수집 및 수정
4. docs/standards/commit-message-standard.md 최종 확정
5. P1 단계 시작

---

**상태**: 팀 검토 대기
**담당**: 당신 + 팀장 + 동료들
**일정**: 이번 주 중 결정
