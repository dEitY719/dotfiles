# Git Hooks 전략 가이드: 개발자들이 많이 사용하는 검증된 Hooks

**문서 목적:** 이미 구현된 pre-commit을 보완하는 추가 hooks 기능 제안
**대상자:** 팀 리더, 개발자
**작성일:** 2026-01-29

---

## 개요: Git Hooks의 가치

**현재 상황:**
- ✅ `pre-commit` hooks: 커밋 전 파일 검증 (이미 구현됨)
- ❓ 추가 hooks: 커밋 메시지, push, merge 등 다양한 단계에서 검증 가능

**왜 미리 적용해야 하는가?**
```
버그 발생 후 수정 << 검증된 hooks를 미리 적용
                   (사후 대응 vs 사전 예방)
```

---

## 📋 Git Hooks 라이프사이클

```
git add files
    ↓
[1. pre-commit] ← 현재 구현 ✅
    ↓
git commit -m "message"
    ↓
[2. prepare-commit-msg] ← 가능 (커밋 메시지 템플릿)
    ↓
[3. commit-msg] ← 권장 (커밋 메시지 검증)
    ↓
[4. post-commit] ← 가능 (커밋 후 정리)
    ↓
git push
    ↓
[5. pre-push] ← 권장 (push 전 최종 검증)
    ↓
git merge
    ↓
[6. post-merge] ← 권장 (병합 후 자동화)
```

---

## 🎯 권장 Hooks 기능 5가지

### 1️⃣ **commit-msg** - 커밋 메시지 검증 ⭐⭐⭐ 높은 우선순위

**목적:** 모든 커밋이 일관된 메시지 규칙을 따르도록 강제

**검증 항목:**
```
✓ 메시지 길이: 1줄 < 50자, 본문 < 72자
✓ 규칙: feat:, fix:, docs: 등으로 시작
✓ 금지: "WIP", "tmp", "test" 등 임시 메시지
✓ 구조: 제목, 빈 줄, 본문, footer
```

**예시 (좋음 vs 나쁨):**
```bash
# ✅ 좋음
feat(auth): add OAuth2 login integration

  - Implement JWT token generation
  - Add session management
  - Refs: #123

# ❌ 나쁨
WIP: something
tmp fix
Update stuff
```

**이점:**
- 깔끔한 git log 유지
- 자동 changelog 생성 가능
- 버그 추적 용이 (commit message로 issue 링크)
- 코드 리뷰 컨텍스트 명확

**구현 복잡도:** ⭐⭐ (중간)
**팀 규모:** 3명 이상 권장

---

### 2️⃣ **pre-push** - Push 전 최종 검증 ⭐⭐⭐ 높은 우선순위

**목적:** 로컬에서만 테스트하던 것들을 remote 전에 검증

**검증 항목:**
```
✓ 모든 테스트 통과 (선택사항)
✓ 린트 검사 통과
✓ 특정 파일이 실수로 commit되지 않았는지 확인
✓ Branch 정책 준수 (main에 직접 push 금지 등)
✓ 커밋 메시지 형식 최종 검증
```

**시나리오:**
```bash
# 사용자가 입력
git push

# pre-push hook이 자동 실행
[pre-push] Running tests...
[pre-push] ✗ Test failed: src/api.test.js
✗ Push aborted (fix tests first)

# 사용자는 로컬에서 먼저 수정
npm test  # 수정 후 통과
git push  # 성공
```

**이점:**
- CI/CD 서버 부하 감소 (로컬에서 먼저 걸러냄)
- remote 오염 방지 (실패한 커밋이 원격에 안 갈라짐)
- 팀의 신뢰도 증가

**구현 복잡도:** ⭐⭐⭐ (중간~높음)
**팀 규모:** 5명 이상 권장 (CI/CD 비용 절감)

---

### 3️⃣ **post-checkout** - 자동 작업 수행 ⭐⭐ 중간 우선순위

**목적:** 다른 branch로 전환하거나 pull할 때 자동으로 필요한 작업 실행

**자동 수행 작업:**
```
✓ branch 변경 후 package-lock.json이 바뀌었으면 npm install 자동 실행
✓ Gemfile이 바뀌었으면 bundle install 자동 실행
✓ .env.example이 바뀌었으면 .env 업데이트 안내
✓ db/migrations 폴더 변경 감지 후 마이그레이션 알림
```

**시나리오:**
```bash
git checkout feature/new-dependencies

# hook이 자동 실행
[post-checkout] Detected dependency changes
[post-checkout] Running: npm install
[post-checkout] ✓ Dependencies updated

# 개발자는 수동으로 할 필요 없음!
```

**이점:**
- 개발자의 실수 방지 (의존성 설치 깜빡함 등)
- 개발 환경 자동 정기화
- 새로운 팀원 온보딩 시간 단축

**구현 복잡도:** ⭐⭐ (중간)
**팀 규모:** 3명 이상 권장

---

### 4️⃣ **post-merge** - 병합 후 자동화 ⭐⭐ 중간 우선순위

**목적:** PR merge 후 자동으로 필요한 작업 수행

**자동 수행 작업:**
```
✓ main에 병합되면 버전 번호 자동 업데이트
✓ CHANGELOG.md 자동 생성 (conventional commits 기반)
✓ 병합된 branch 자동 삭제
✓ 배포 필요 시 자동 배포 트리거
✓ Slack 알림 (누구가 뭘 merge했는지)
```

**시나리오:**
```bash
# GitHub에서 PR merge (또는 로컬에서 git merge main)

# hook이 자동 실행
[post-merge] Merged feature branch detected
[post-merge] Updating CHANGELOG.md...
[post-merge] Bumping version: 1.2.3 → 1.2.4
[post-merge] Running tests on merged code...
[post-merge] ✓ All checks passed

# 자동으로 배포 준비 완료!
```

**이점:**
- 수동 릴리스 단계 제거
- CHANGELOG 항상 최신 상태 유지
- 배포 자동화로 human error 감소
- 팀의 릴리스 속도 향상

**구현 복잡도:** ⭐⭐⭐ (높음)
**팀 규모:** 5명 이상, 지속적 배포하는 팀 권장

---

### 5️⃣ **prepare-commit-msg** - 커밋 메시지 템플릿 ⭐⭐⭐ 높은 우선순위

**목적:** 커밋할 때 자동으로 템플릿 제공

**자동 생성 메시지:**
```
# PR에서 branch → 자동으로 PR 번호 포함
#123: [Title from PR]

# Merge commit → 자동으로 reviewer 정보 포함
Merge pull request #456 from feature/auth

Reviewed-by: @alice
Reviewed-by: @bob

# Squash commit → 자동으로 모든 PR 메시지 포함
- Fix: auth bug
- Feat: add login
- Docs: update readme
```

**시나리오:**
```bash
git commit -m "temp"

# 에디터 열리면 이미 템플릿이 있음
feat(#123):

  -
  -
  -

Co-Authored-By: @team_member

# 개발자는 빈칸만 채우면 됨
```

**이점:**
- 개발자가 규칙을 기억할 필요 없음 (자동 제공)
- 메시지 일관성 98% 자동 달성
- 신규 입사자도 쉽게 따를 수 있음
- 커밋 메시지 품질 향상

**구현 복잡도:** ⭐⭐ (중간)
**팀 규모:** 3명 이상 권장

---

## 📊 Hooks 선택 매트릭스

| Hook | 우선순위 | 구현 난도 | 효과 | 최소팀규모 |
|------|---------|---------|------|----------|
| **pre-commit** | ⭐⭐⭐ | ⭐⭐ | 매우높음 | 1명 |
| **commit-msg** | ⭐⭐⭐ | ⭐⭐ | 높음 | 3명 |
| **prepare-commit-msg** | ⭐⭐⭐ | ⭐⭐ | 높음 | 3명 |
| **pre-push** | ⭐⭐⭐ | ⭐⭐⭐ | 매우높음 | 5명 |
| **post-checkout** | ⭐⭐ | ⭐⭐ | 중간 | 3명 |
| **post-merge** | ⭐⭐ | ⭐⭐⭐ | 높음 | 5명 |

---

## 🚀 구현 계획 (단계별)

### Phase 1: 기초 (즉시 시작) ✅ 이미 구현됨
```
[기간] 1주일
[적용 항목]
  ✓ pre-commit hook (ShellCheck 포함)
[효과] 코드 품질 보장
```

### Phase 2: 메시지 검증 (1개월 내)
```
[기간] 2주일
[적용 항목]
  - commit-msg hook
  - prepare-commit-msg hook
[효과] 커밋 로그 일관성, 자동 changelog 가능
[팀 영향] 약간의 학습 곡선 필요
```

### Phase 3: Push 검증 (1-2개월)
```
[기간] 3주일
[적용 항목]
  - pre-push hook
  - 간단한 테스트 자동화
[효과] CI/CD 서버 부하 감소, 리모트 품질 보장
[팀 영향] 중간 (로컬 테스트 필수화)
```

### Phase 4: 자동화 (2-3개월)
```
[기간] 1-2개월
[적용 항목]
  - post-merge hook
  - 버전 관리 자동화
  - 릴리스 자동화
[효과] 배포 자동화, 수동 작업 최소화
[팀 영향] 높음 (릴리스 프로세스 변경)
```

---

## 💡 구현 시 주의사항

### 개발자 경험 (DX) 최우선
```
❌ 너무 많은 hook 추가 → 개발 속도 저하
❌ hook 실패 메시지가 불명확 → 개발자 좌절
❌ hook 실행 시간이 너무 김 → 매번 커피 마시기

✅ 가장 중요한 것부터 시작
✅ 명확한 오류 메시지
✅ 빠른 실행 속도 (< 2초)
```

### 조직 전환
```
Phase별 팀 미팅
  ↓
새 hook 설명 및 이점 공유
  ↓
1주일 시범 기간 (경고만 함)
  ↓
본격 적용 (실제 차단)
  ↓
1주일 후 피드백 수집
```

### 문제 대응 계획
```
만약 hook이 너무 엄격하면:
  1. Hook 규칙 완화 (일부 경고로 변경)
  2. 사례별 무시 옵션 추가 (SKIP_HOOKS=1 등)
  3. 예외 상황 정의

만약 팀원이 불평하면:
  1. 그들의 사용 사례 이해
  2. hook 메시지 개선
  3. 필요시 단계별 적용 또는 철회
```

---

## 📚 참고: 업계 표준 (다른 팀들의 선택)

### 스타트업/소규모 팀
```
적용: pre-commit + commit-msg
무시: 복잡한 자동화
이유: 속도 vs 안정성의 균형
```

### 스케일업 팀 (50-200명)
```
적용: pre-commit + commit-msg + pre-push + post-merge
무시: post-rewrite, post-rebase (복잡함)
이유: 팀 규모에 맞는 자동화
```

### 엔터프라이즈
```
적용: 모든 hook + 추가 커스텀 hook
무시: 없음
이유: 규제, 감사, 품질 관리 필수
```

### 오픈소스 프로젝트
```
적용: commit-msg + pre-push (로컬용)
주의: hook 강제 금지 (기여자 자유도 보장)
이유: 기여자 진입 장벽 낮추기
```

---

## ✅ 체크리스트: 새 Hook 도입 전

각 hook을 도입하기 전에 다음을 확인하세요:

```
Hook: [hook 이름]

1. 이 hook이 해결할 실제 문제가 있는가?
   [ ] 예 → 구체적으로 어떤 문제? ___________
   [ ] 아니오 → 도입 보류

2. 팀이 이 규칙을 따를 준비가 되어있는가?
   [ ] 예 → 모두 동의?
   [ ] 아니오 → 먼저 팀 미팅

3. hook을 무시할 수 있는 방법이 있는가?
   [ ] 예 → SKIP_HOOKS=1 git commit 등
   [ ] 아니오 → 추가 필요

4. 오류 메시지가 명확한가?
   [ ] 예 → 문제와 해결책을 모두 설명
   [ ] 아니오 → 개선 필요

5. 성능 영향이 무시할 수준인가?
   [ ] 예 → < 2초
   [ ] 아니오 → 최적화 필요

6. CI/CD와 충돌하지 않는가?
   [ ] 예 → 중복 검사 없음
   [ ] 아니오 → 조정 필요
```

---

## 🎯 우리 팀을 위한 추천안

**현재 상황:** 3-5명의 활동적인 개발 팀

**즉시 추천 (다음 1개월):**
1. ✅ **pre-commit** (이미 구현)
   - ShellCheck 포함하여 매우 좋음

2. 🔄 **commit-msg** (추가 권장)
   - 이유: 커밋 로그 품질이 즉시 개선됨
   - 난도: 낮음
   - 효과: 높음

3. 🔄 **prepare-commit-msg** (추가 권장)
   - 이유: 개발자 경험 향상
   - 난도: 낮음
   - 효과: 중간~높음

**중기 계획 (2-3개월):**
4. 📋 **pre-push** (팀 규모 5명 이상일 때)
   - 이유: CI/CD 서버 부하 절감
   - 난도: 중간
   - 효과: 높음

**장기 계획 (3-6개월):**
5. 🔧 **post-merge** (배포 자동화 시작할 때)
   - 이유: 릴리스 자동화
   - 난도: 높음
   - 효과: 매우 높음

---

## 📞 다음 단계

1. **이 문서 리뷰:** 팀 전체가 읽고 의견 제시
2. **선택 투표:** 어떤 hook을 먼저 추가할지
3. **구현 담당자 배정:** 각 hook별 owner 정하기
4. **1주일 시범 기간:** 경고 모드로 시작
5. **피드백 수집:** 1주일 후 팀 미팅
6. **본격 적용:** 문제 해결 후 차단 모드 활성화

---

**작성자:** Claude (AI Assistant)
**최종 검토 대기:** 팀 리더/DevOps 담당자
**예상 실행 시간:** 1-6개월 (단계별)
