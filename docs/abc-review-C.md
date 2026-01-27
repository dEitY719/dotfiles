# 개발 업무 관리 및 팀 공유 전략 (Development Workflow & Team Knowledge Sharing)

## 👋 Executive Summary

**상황**: Claude Code로 작업 → Git pull → 수동으로 Jira/Confluence 등록
**문제**: Copy & Paste 비효율, 정보 손실, 팀장 병목
**해결**: Git 중심 자동화 → Jira/Confluence 자동 동기화
**효과**: 30분/day 단축 + 팀 협업 강화 + 정보 투명성 확보

---

## 1단계: 즉시 실행 (이번 주, 5분)

### A. Git Commit Message 표준화

```bash
# .gitmessage 파일 생성
cat > .gitmessage << 'EOF'
[JIRA-XXX] type: description

상세 설명
- 주요 변경사항 1
- 주요 변경사항 2

메타정보:
- Category: {Testing/Infrastructure/Documentation}
- TimeSpent: {시간}h
- Audience: {All/Dev/QA}
EOF

# 적용
git config commit.template .gitmessage
```

**예시** (이번 작업):
```
[PROJ-245] feat: parallel testing with pytest-xdist

Implemented 3-4x faster test execution by:
- Adding pytest-xdist for parallel test runs
- Creating isolated test environments per worker
- Documenting 1682 lines of technical guides

메타정보:
- Category: Testing Infrastructure
- TimeSpent: 4.5h
- Audience: All
```

### B. Post-commit Hook 자동화

```bash
cat > .git/hooks/post-commit << 'EOF'
#!/bin/bash
MSG=$(git log -1 --pretty=%B)
JIRA=$(echo "$MSG" | grep -oP '\[PROJ-\d+\]' | head -1)
TIME=$(echo "$MSG" | grep "TimeSpent:" | cut -d: -f2 | xargs)
echo "[$(date '+%Y-%m-%d %H:%M')] $JIRA | $TIME" >> ~/work_log.txt
EOF

chmod +x .git/hooks/post-commit
```

**효과**: 커밋할 때마다 자동으로 작업 기록 생성

### C. 작업별 README 템플릿

```markdown
# {작업 제목}

**Jira**: [PROJ-245](https://jira.yourcompany.com/browse/PROJ-245)
**Status**: ✅ Complete

## 산출물
- [x] 코드 구현
- [x] 테스트 (275 passing)
- [x] 문서 (1682줄)

## 시간 투입
- 구현: 2h
- 테스트: 1h
- 문서: 1.5h
- **총**: 4.5h
```

---

## 2단계: 자동화 스킬 설계 (2-3주)

### make-jira 스킬 (제안)

```yaml
# skills/make-jira.yaml
name: make-jira
description: Git commit을 Jira에 자동 업데이트

usage: |
  /make-jira PROJ-245
  → Commit 파싱 → Jira 업데이트 → 완료

features:
  - Commit message 자동 파싱
  - Jira TimeSpent 기록
  - Status 자동 변경
  - 관련 문서 링크 추가
```

### make-confluence 스킬 (제안)

```yaml
# skills/make-confluence.yaml
name: make-confluence
description: Markdown을 Confluence에 자동 게시

usage: |
  /make-confluence docs/technic/parallel-testing-with-xdist.md
  → 변환 → 게시 → 팀 알림

features:
  - Markdown → Confluence 변환
  - 자동 메타데이터 추가
  - 팀원 자동 알림
```

---

## 3단계: 개선된 워크플로우

### Before (현재)

```
1. Claude Code 작업 완료
2. Git push
3. ❌ 여기서 멈춤
4. (팀장이) Jira 수동 등록 (15분)
5. (팀장이) Confluence 수동 작성 (15분)
6. (팀장이) 팀원에 공유 (5분)
   → 총 35분 낭비
```

### After (개선)

```
1. Claude Code 작업 완료
2. Git commit (표준 메시지) + push
3. ✅ 자동화 시작!
   - Jira 자동 업데이트 (make-jira)
   - Confluence 자동 게시 (make-confluence)
   - 팀원 자동 알림
4. 팀장 검토 (5분, 품질만 확인)
   → 효율성 7배 향상!
```

---

## 핵심 아키텍처: Git이 Single Source of Truth

```
┌──────────────────────┐
│  Git Repository      │
│  (Source of Truth)   │
│  - Commits           │
│  - Metadata          │
│  - History           │
└──────────┬───────────┘
           │
    ┌──────┴──────┐
    │             │
    ▼             ▼
 [Jira]      [Confluence]
 (자동)      (자동)
  - Status    - Guides
  - Time      - Docs
  - Comments  - Knowledge
    │             │
    └──────┬──────┘
           │
           ▼
    [Team Dashboard]
    - Real-time view
    - Metrics
    - Notifications
```

**이점**:
1. 중복 제거 (하나의 소스)
2. 자동화 (파생 데이터)
3. 버전 관리 (Git 이력)
4. 감사 추적 (모두 기록)
5. 팀 투명성 (모두 볼 수 있음)

---

## 회사 내부 적용 (Copy & Paste)

### 최소 필수 요소

```bash
# 1. Commit message 표준 문서
docs/commit-message-standard.md

# 2. Python 스크립트 (자체 구현)
scripts/github_to_jira.py
scripts/markdown_to_confluence.py

# 3. 설정 파일
.gitmessage (공유)
.git/hooks/post-commit (공유)
```

### Python 예시

```python
# scripts/github_to_jira.py (회사에서 자체 구현)
import requests
import re

def parse_commit(msg):
    """[PROJ-245] feat: ... → {jira_key, time_spent, ...}"""
    match = re.search(r'\[PROJ-(\d+)\]', msg)
    jira_key = match.group(0) if match else None
    time = re.search(r'TimeSpent:\s*(\d+\.?\d*)h', msg)
    return {
        'jira_key': jira_key,
        'time_spent': time.group(1) if time else '0'
    }

def update_jira(jira_key, metadata):
    """Jira API로 업데이트"""
    api = f"https://jira.yourcompany.com/rest/api/3/issues/{jira_key}"
    requests.put(api, json={
        'fields': {
            'timetracking': {'timeSpent': f"{metadata['time_spent']}h"},
            'status': 'In Review'
        }
    })

if __name__ == '__main__':
    msg = os.popen('git log -1 --pretty=%B').read()
    metadata = parse_commit(msg)
    if metadata['jira_key']:
        update_jira(metadata['jira_key'], metadata)
        print(f"✅ {metadata['jira_key']} updated")
```

---

## 3주 실행 계획

| 주차 | 목표 | 효과 |
|------|------|------|
| **Week 1** | 템플릿 + Hook 구현 | 15분/작업 절약 |
| **Week 2-3** | make-jira/make-confluence 개발 | 자동화 90% |
| **Week 4** | 팀 도입 | 팀 협업 강화 |

### Week 1 Checklist

- [ ] .gitmessage 작성 & 공유
- [ ] Post-commit hook 작성 & 테스트
- [ ] 이번 작업에 적용 & 검증
- [ ] README 템플릿 생성

---

## 더 나은 전략: 팀장의 역할 변화

### Before (현재)
```
팀장:
- 수작업 Jira 등록 (15분)
- 수작업 Confluence 작성 (15분)
- 정보 추적 (5분)
━━━━━━━━━━━━━━━━━━━━━
- 일일 작업: 35분 × N명
- 고부가 업무: 없음
- 병목: 심각
```

### After (개선)
```
팀장:
- 자동화 감시 (1분)
- 품질 리뷰 (4분)
- 전략 수립 (30분)
━━━━━━━━━━━━━━━━━━━━━
- 일일 작업: 35분 → 5분 (85% 절약!)
- 고부가 업무: 전략, 리더십
- 병목: 해결
```

---

## 이번 작업의 예시 적용

### Jira 기록

```
🔑 PROJ-245: Parallel Testing Infrastructure
Status: ✅ Done
Priority: High | Complexity: Medium

⏱️ Time Spent: 4h 30m
📊 Results:
  ✅ Tests: 15 fixed, 275 passing
  ✅ Docs: 1682 lines, 4 files
  ✅ Speed: 3-4x improvement

🔗 Links:
  - Git: https://github.com/.../commit/...
  - Confluence: https://confluence/.../
  - Related: PROJ-246 (Blocked by this)
```

### Confluence 페이지

```
📘 기술 가이드 > 테스팅 > 병렬 테스트

✍️ 작성자: You | 📅 2026-01-27
🔗 Git: {link} | 📊 조회수: 42 | ⭐ 즐겨찾기: 5

📌 개요
병렬 테스트로 3-4배 빠른 실행 (250s → 8s)

📚 세부 가이드
1. pytest-xdist 구현 (400+ 줄)
2. 아키텍처 분석 (350+ 줄)
3. AI 프롬프트 (450+ 줄)
```

---

## 즉시 시작하기 (Next 3 Actions)

### ✅ Action 1: .gitmessage 추가 (2분)

```bash
cat > .gitmessage << 'EOF'
[JIRA-XXX] type: description

상세 설명

메타정보:
- Category:
- TimeSpent:
EOF

git config commit.template .gitmessage
git add .gitmessage && git commit -m "chore: add commit message template"
```

### ✅ Action 2: Hook 추가 (2분)

```bash
cat > .git/hooks/post-commit << 'EOF'
#!/bin/bash
MSG=$(git log -1 --pretty=%B)
JIRA=$(echo "$MSG" | grep -oP '\[PROJ-\d+\]' | head -1)
TIME=$(echo "$MSG" | grep "TimeSpent:" | cut -d: -f2)
echo "[$(date)] $JIRA | $TIME" >> ~/work_log.txt
EOF

chmod +x .git/hooks/post-commit
```

### ✅ Action 3: 이번 작업 Jira 기록 (5분)

```
제목: Parallel Testing Infrastructure & Documentation
상태: ✅ Done
시간: 4.5h
산출물: 275 tests passing, 1682줄 문서
```

---

## 최종 권장사항

1. **Git을 Single Source of Truth로**: 모든 정보를 Git commit에 포함
2. **메타데이터 구조화**: [JIRA-KEY] type: subject + 구조화된 메타정보
3. **3단계 자동화**: Week 1 (템플릿) → Week 2-3 (스킬) → Week 4+ (팀 도입)
4. **팀장의 역할 변화**: 수작업 → 자동화 감시 → 전략 수립
5. **회사 내부 구현**: Python 스크립트로 자체 구현 (Git → Jira/Confluence)

---

**상태**: Ready for Implementation
**투입 시간**: Week 1: 30분, Week 2-3: 10h, Week 4+: 유지보수
**기대 효과**: 30분/day 절약 + 팀 협업 강화
**ROI**: 매우 높음 (초기 투자 낮음)

**마지막 업데이트**: 2026-01-27
**다음 단계**: Week 1 체크리스트 실행 👉
