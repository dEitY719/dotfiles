# My-CLI Implementation Roadmap

**목적**: Legacy my-help 기능을 my-cli로 마이그레이션하기 위한 구현 로드맵
**작성일**: 2026-02-20
**상태**: Discovery Phase 완료

---

## 📊 Tier 분류 (재정의)

### Tier 1 (Critical - Must Do First)
```
일일 사용, 매우 높은 복잡도
- Git (79줄, 매우 복잡)
- Python (38줄, 이미 최적화)
```

### Tier 2 (High - Do After T1)
```
주간 사용, 중간~높은 복잡도
- NPM (127줄)
- Docker (64줄)
- UV, NVM, Proxy, etc.
```

### Tier 3 (Medium - Do Later)
```
월간 사용 또는 참고용
- 나머지 Docs, Config, CLI Tools
```

---

## 🎯 Implementation Phase

### Phase 1: Foundation (CL-7.1~7.2) ✨

**목표**: 기본 UX 개선 + 데이터 모델 확장
**예상 기간**: 1주일
**담당**: 현재 (UI 레이어)

#### CL-7.1: UI 개선
```yaml
Task:
  - ANSI 색상 복구 (TopicDetail에서 렌더링)
  - 의미없는 테두리 제거 (╔══╗ 등)
  - 페이지네이션 개선 (필요시)

Files:
  - packages/cli/src/tui/screens/TopicDetail.tsx
  - packages/core/src/adapters/ShellFunctionAdapter.ts

Time: 2-3시간
```

#### CL-7.2: 데이터 모델 확장
```yaml
Task:
  - HelpTopic에 필드 추가:
    * summary: 한 줄 요약
    * tier: Tier 1/2/3
    * sections: [{title, items}] (구조화)
    * quick_items: [5개 필수 명령어]

  - 새로운 HelpContent 포맷 정의:
    * HELP_CONTENT[py__summary]
    * HELP_CONTENT[py__quick]
    * HELP_CONTENT[py__full]

Files:
  - packages/core/src/registry/types.ts
  - shell-common/functions/*.sh (데이터 포맷 변경)

Time: 4-5시간
```

---

### Phase 2: Tier 1 Optimization (CL-7.3~7.4) 🎯

**목표**: 가장 자주 사용하는 항목(Git, Python) 최적화
**예상 기간**: 2주일
**담당**: 데이터 정제

#### CL-7.3: Git 리팩토링
```yaml
Topic: git
Current: 79줄 (7섹션)
Target: Quick Mode (7줄) + Full Mode (79줄)

Quick Mode Items:
  - gs (git status)
  - ga (git add)
  - gc (git commit)
  - gp (git push)
  - gpl (git pull)
  - gco (git checkout)
  - gd (git diff)

Implementation:
  - git_help.sh 구조화 (섹션별)
  - TUI에서 모드 선택 UI 추가
  - CLI --quick / --full 플래그

Time: 3-4시간
```

#### CL-7.4: Python 확인 + 나머지 Tier 1 처리
```yaml
Topic: py, uv, nvm, npm
Current: 분석 상태
Target: 각 항목별 Quick + Full 모드

Items to Analyze:
  - UV: npm과 유사?
  - NVM: 간단함 (20줄)
  - NPM: 127줄 (축약 필요)

Time: 5-6시간
```

---

### Phase 3: Tier 2 Optimization (CL-7.5~7.7) 🚀

**목표**: 주간 사용 항목들 정제
**예상 기간**: 3주일
**담당**: 순차적 데이터 정제

#### CL-7.5: DevOps 카테고리
```
Topics: docker, proxy, sys, mysql, gpu
Target: Quick Mode 구현
```

#### CL-7.6: CLI Tools 카테고리
```
Topics: bat, gc, zsh, fzf, fd
Target: Quick Mode 구현
```

#### CL-7.7: 나머지 (Docs, Config, System)
```
Topics: 모든 나머지 항목
Target: 최소화 또는 참고용 유지
```

---

### Phase 4: Polish & Release (CL-7.8~7.9) 🎉

**목표**: 전체 통합 테스트 + 문서화
**예상 기간**: 1주일
**담당**: 품질 보증

#### CL-7.8: 통합 테스트
```
- 모든 카테고리/토픽 확인
- 색상 렌더링 검증
- 페이지네이션 동작
- 성능 측정 (cold start)
```

#### CL-7.9: 최종 문서화
```
- User Guide 작성
- API 문서 생성
- Migration Guide (legacy → my-cli)
```

---

## 📈 Timeline Overview

```
Week 1 (CL-7.1~7.2):  Foundation 구축
├─ UI 개선 (2h)
└─ 데이터 모델 확장 (4h)
  → 모든 기능이 더 잘 보임

Week 2 (CL-7.3~7.4):  Tier 1 완성
├─ Git 최적화 (3h)
└─ 나머지 Tier 1 (5h)
  → 일일 사용 항목 완벽

Week 3-5 (CL-7.5~7.7):  Tier 2, 3 정제
├─ DevOps (3h)
├─ CLI Tools (3h)
└─ 나머지 (4h)
  → 전체 카테고리 최적화

Week 6 (CL-7.8~7.9):  Polish & Release
├─ 통합 테스트 (2h)
└─ 문서화 (3h)
  → 프로덕션 준비 완료
```

---

## 🎁 Data Model Example

### Before (Legacy)
```bash
HELP_CONTENT[py]="╔════...
║ Python Virtual Environment Commands
...
40줄 전체 콘텐츠
"
```

### After (New)
```bash
# 요약 (한 줄)
HELP_CONTENT[py__summary]="Python 가상 환경 관리"

# Quick Mode (5줄)
HELP_CONTENT[py__quick]="cv  | create venv
av  | activate venv
dv  | deactivate venv
pip install | install package
ev  | show path"

# Full Mode (기존 그대로)
HELP_CONTENT[py__full]="╔════...
40줄 전체
"

# 메타데이터
HELP_TIER[py]="1"
HELP_FREQUENCY[py]="daily"
```

---

## 🔄 Data Format Strategy

### Option A: 파일 수정 최소화
```
기존 _help.sh 파일 그대로 유지
→ 파싱 로직만 개선
```

**장점**: 변경 최소
**단점**: 파싱 복잡도 증가

### Option B: 새로운 HELP_* 변수 추가
```
기존 HELP_CONTENT 유지
추가로 HELP_CONTENT[{topic}__quick] 등 추가
```

**장점**: 기존 코드 호환
**단점**: 파일 크기 증가

### Option C: 구조화된 포맷 (추천)
```
JSON/YAML 포맷으로 재정의
각 topic별로 섹션 구조화
```

**장점**: 가장 깔끔함
**단점**: 기존 코드 전면 리팩토링 필요

---

## 🚀 Recommended Approach

**지금**: Option B (신규 변수 추가)
- 기존 호환성 유지
- 단계적 마이그레이션 가능
- CL-7.x에서 검증 후 Option C로 전환

**향후**: Option C (구조화)
- 완전한 모던화
- 더 나은 확장성
- CL-8.x에서 대규모 리팩토링

---

## 📋 Checklist

### Phase 1: Foundation ✅
- [ ] ANSI 색상 복구
- [ ] 의미없는 테두리 제거
- [ ] HelpTopic 모델 확장
- [ ] 새로운 HELP_* 변수 문서화

### Phase 2: Tier 1 ⏳
- [ ] Git 분석 완료
- [ ] Git 데이터 포맷 변경
- [ ] Git Quick Mode 구현 + 테스트
- [ ] Python 최종 확인
- [ ] NVM, UV 분석

### Phase 3: Tier 2 🔄
- [ ] NPM 상세 분석
- [ ] Docker 상세 분석
- [ ] 각 항목별 Quick Mode 구현

### Phase 4: Release 📦
- [ ] 전체 통합 테스트
- [ ] 문서화
- [ ] 성능 측정

---

## 💾 Files to Modify

### 핵심 파일
```
packages/cli/src/tui/screens/TopicDetail.tsx  (색상/레이아웃)
packages/core/src/registry/types.ts           (HelpTopic 모델)
packages/core/src/adapters/ShellFunctionAdapter.ts (색상 처리)
shell-common/functions/*.sh                  (데이터 포맷)
```

### 생성될 파일
```
docs/feature/my-cli/analysis/legacy-analysis.md                       ✅ 완료
docs/feature/my-cli/analysis/development-category-analysis.md         ✅ 완료
docs/feature/my-cli/analysis/devops-category-analysis.md              ✅ 완료
docs/feature/my-cli/analysis/ai-llm-category-analysis.md              ✅ 완료
docs/feature/my-cli/analysis/cli-tools-category-analysis.md           ✅ 완료
docs/feature/my-cli/analysis/config-system-meta-category-analysis.md  ✅ 완료
docs/feature/my-cli/planning/implementation-roadmap.md                ✅ 완료
docs/feature/my-cli/planning/phase-1-detail.md                        (다음)
docs/feature/my-cli/planning/phase-2-detail.md                        (다음)
```

---

## 🎓 Key Learnings

1. **분석이 먼저**: 코드 먼저 작성하면 나중에 큰 리팩토링 필요
2. **단계적 진행**: 모든 것을 한 번에 하려고 하면 복잡도 증가
3. **호환성 유지**: 기존 코드 활용하면서 점진적으로 개선
4. **데이터 중심**: UI 변경보다 데이터 구조가 더 중요

---

**다음 단계**: 이 로드맵을 바탕으로 CL-7.1부터 시작!
