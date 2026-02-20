# My-CLI Legacy Migration Analysis

**분석 완료일**: 2026-02-20
**분석가**: AI Agent (Claude Code)
**상태**: Discovery Phase ✅ 완료

---

## 📚 문서 가이드

### 1. **LEGACY_ANALYSIS.md** (종합 분석)
- 전체 34개 help 파일 개요
- 카테고리별 분류
- Tier 우선순위 정의
- 마이그레이션 전략

👉 **먼저 읽어야 할 문서**

---

### 2. **01-DEVELOPMENT.md** (Development 카테고리)
- Git (79줄, ⭐⭐⭐⭐⭐ Tier 1)
  - 기본 7개 명령어 정리 완료
  - Full Mode 구현 계획 수립
- Python (38줄, ⭐⭐⭐⭐⭐ Tier 1)
  - 이미 최적화된 상태 ✅
  - 색상 복구만 필요
- NPM, NVM, UV 등 분석 대기

---

### 3. **02-DEVOPS.md** (DevOps 카테고리)
- Docker, Proxy, Sys, MySQL 등
- Tier 2 우선순위
- Quick + Full Mode 계획 수립

---

### 4. **03-AI_LLM.md** (AI/LLM 카테고리)
- Claude, Gemini, Codex, Ollama 등
- 대부분 Tier 3 (낮은 우선순위)
- 향후 처리

---

### 5. **04-CLI_TOOLS.md** (CLI Tools 카테고리)
- Bat, GC, Zsh, Fzf, Fd 등
- Tier 2 우선순위
- 상세 분석 진행 중

---

### 6. **05-CONFIG_SYSTEM_META.md** (나머지)
- Config, System, Meta, Docs 카테고리
- 통합 우선순위 정의
- 향후 처리 계획

---

### 7. **IMPLEMENTATION_ROADMAP.md** (구현 계획) ⭐ 중요
- Phase 1~4 상세 로드맵
- CL-7.1 ~ CL-7.9 일정
- Tier별 구현 순서
- 데이터 모델 설계

👉 **개발 시작 전에 꼭 읽어야 할 문서**

---

## 🎯 핵심 요약

### 발견사항

| 항목 | 내용 |
|------|------|
| 총 Help 파일 | 34개 |
| 총 라인 수 | ~2,000줄 |
| 카테고리 | 8개 |
| Tier 1 (Critical) | 2개 (Git, Python) |
| Tier 2 (High) | 10~12개 |
| Tier 3 (Medium) | 12~14개 |

### 문제점

1. **색상 손실**: Legacy는 ANSI 색상 o, my-cli는 색상 x
2. **정보 과다**: 모든 내용을 그대로 표시 (사용자 부담 증가)
3. **레이아웃**: 의미없는 테두리가 공간 낭비
4. **탐색성**: Quick/Full 모드 구분 없음

### 해결책

✅ **Quick + Full Mode 도입**
```
Quick Mode: 필수 5~7개만 표시
Full Mode: --full 플래그로 전체 보기
```

✅ **색상 복구**
```
ShellFunctionAdapter에서 ANSI 보존
TopicDetail에서 색상 렌더링
```

✅ **레이아웃 개선**
```
의미없는 테두리 제거
필요한 정보만 표시
```

---

## 📊 우선순위 요약

### Phase 1: Foundation (CL-7.1~7.2) - 1주일
```
목표: 기본 UX + 데이터 모델 개선
- UI 문제 해결 (색상, 레이아웃)
- HelpTopic 모델 확장
```

### Phase 2: Tier 1 최적화 (CL-7.3~7.4) - 2주일
```
목표: Git, Python, NPM 정제
- Git: Quick Mode (7개) + Full Mode (36개)
- Python: 색상만 복구 (이미 최적화)
- NPM: 분석 후 Quick Mode 구현
```

### Phase 3: Tier 2 정제 (CL-7.5~7.7) - 3주일
```
목표: 나머지 주간 사용 항목 정제
- DevOps: docker, proxy 등
- CLI: bat, gc, zsh 등
```

### Phase 4: Release (CL-7.8~7.9) - 1주일
```
목표: 통합 테스트 + 최종 문서화
```

---

## 🚀 Next Action Items

### 당장 할 일

1. ✅ **분석 문서 검토**
   - 위 6개 분석 문서 읽기
   - IMPLEMENTATION_ROADMAP.md 정독

2. ⏳ **Phase 1 구체화**
   - `PHASE_1_DETAIL.md` 작성
   - 구체적인 파일/코드 변경 내용 정의
   - 예상 시간 재계산

3. ⏳ **CL-7.1 시작**
   - TopicDetail.tsx 리팩토링 시작
   - ANSI 색상 복구
   - 의미없는 테두리 제거

---

## 📌 중요한 결정 사항

### 1. 데이터 포맷 (Option B 선택)
```
✅ 기존 HELP_CONTENT 유지
✅ 신규 변수 추가 (HELP_CONTENT[x__quick] 등)
⏳ 향후 JSON 구조화 (CL-8.x에서)
```

### 2. Quick Mode 정의
```
✅ Tier 1: 5~7개 필수 항목
✅ Tier 2: 5~8개 필수 항목
✅ 나머지: 현재 상태 유지
```

### 3. UI 모드 선택
```
🔄 검토 필요: TUI에서 모드 선택하는 방법
- 옵션 1: PgUp/PgDn 대신 Q/F (Quick/Full)
- 옵션 2: 팝업 메뉴 (보기 모드 선택)
- 옵션 3: --full 플래그만 (CLI 방식)
```

---

## 💡 작업 시 팁

### 분석 문서 활용법

1. **개발 전**
   - IMPLEMENTATION_ROADMAP.md 읽기
   - 해당 카테고리 분석 문서 검토

2. **개발 중**
   - 항목별 "개선 방향" 섹션 참고
   - Tier/Priority 확인

3. **테스트 후**
   - 분석 문서에 실제 결과 반영
   - "Status" 업데이트

### 좋은 습관

- [ ] 각 CL-x 시작 전에 해당 분석 문서 읽기
- [ ] 데이터 변경 시 이 문서도 함께 업데이트
- [ ] 분석과 구현을 분리해서 진행

---

## 📞 Contact / Questions

질문이 있다면:
1. 관련 분석 문서 검색
2. LEGACY_ANALYSIS.md 재검토
3. IMPLEMENTATION_ROADMAP.md의 FAQ 섹션 확인

---

**작성**: 2026-02-20
**마지막 업데이트**: 2026-02-20
**다음 마일스톤**: CL-7.1 시작 (Phase 1)
