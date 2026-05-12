# Git Commit & Branch Naming Standard

## 목표

모든 작업을 Git에 추적 가능하게 기록하여 SSOT 확보.

---

## 1. 브랜치 명명 규칙

### 형식

```
{jira-key-lowercase}-{short-description}
```

### 예시

**회사 Jira 키 사용** (소문자로 브랜치명 작성):
```bash
# 기능 개발 (Jira: SWINNOTEAM-906)
git checkout -b swinnoteam-906-parallel-testing

# 버그 수정 (Jira: SWINNOTEAM-907)
git checkout -b swinnoteam-907-login-bug

# 리팩토링 (Jira: SWINNOTEAM-908)
git checkout -b swinnoteam-908-auth-module
```

### 규칙

- **Jira 키**: 회사 형식 그대로 (예: SWINNOTEAM-906)
- **Git 브랜치**: 소문자로 변환 (예: swinnoteam-906-...)
- 단어는 `-` (하이픈)으로 구분
- 최대 50자
- 의미있는 설명 포함

**참고**:
- Jira에는 대문자 키(SWINNOTEAM-906)가 표시됨
- Git에는 소문자로 작성(swinnoteam-906) = Git 관례
- Post-commit hook이 둘 다 인식하도록 설정됨

### 규칙

- 소문자만 사용
- 단어는 `-` (하이픈)으로 구분
- 최대 50자
- 의미있는 설명 포함

---

## 2. 커밋 메시지 형식

### 기본 템플릿

```
[SWINNOTEAM-XXX] type: description

상세 설명
- 주요 변경사항 1
- 주요 변경사항 2

메타정보:
- Category: {Testing/Infrastructure/Documentation/Performance/Security/Communication/Coordination/Training/Other}
- TimeSpent: {시간}h (시간 단위)
- WorkLogTime: {시간}h (시간 단위)
- Audience: {All/Dev/QA/Internal}

태그 (선택):
- [결정] 중요한 의사결정
- [변경] 주요 변경사항
- [리스크] 잠재적 위험
- [검증] 테스트/검증 방법
```

### 실전 예시

**회사 상황 예시**:
```
[SWINNOTEAM-906] feat: implement parallel testing with pytest-xdist

Implemented 3-4x faster test execution:
- pytest-xdist 설정 추가
- 격리된 test environment 구축
- 1682줄 기술 문서 작성

메타정보:
- Category: Testing
- TimeSpent: 4.5h
- WorkLogTime: 4.5h
- Audience: All

태그:
- [결정] pytest-xdist 선택 이유: 가장 활발한 커뮤니티, AWS 추천
- [변경] conftest.py에 worker_id, temp_dir fixture 추가
- [리스크] Worker 간 파일 충돌 가능성 → 격리로 해결
- [검증] 275개 테스트 모두 통과, 순차 250s → 병렬 8s 확인
```

**비개발 업무 예시** (Jira First + CLI 도구 사용):
```
[SWINNOTEAM-903] coordination: prepare AX BI-Weekly presentation

Context:
- W3 AX BI-Weekly 회의에서 할당받은 Action Item
- 센서사업팀의 핵심 AX 3건을 선정하여 PPT 형식으로 준비
- 템플릿: AX Bi-Weekly 사업팀 template.pptx

메타정보:
- Category: Communication
- TimeSpent: 2.5h
- Audience: Stakeholder

태그:
- [협업] 센서사업팀 (송형근 TL) 협의 진행 중
- [검증] 2월 6일 BI-Weekly 발표 스케줄 확정

📝 기록 방법 (Git commit 불가능한 경우):
   CLI 도구로 수동 기록:
   $ work-log add SWINNOTEAM-903 \
       --type coordination \
       --category Communication \
       --time 2.5h
```

**워크플로우**:
```
1. Jira에서 작업 티켓 확인/생성
   예: SWINNOTEAM-906 생성 (Status: To Do)

2. 브랜치 생성 (Jira 키 소문자로 변환)
   git checkout -b swinnoteam-906-parallel-testing

3. 개발 후 커밋 (Jira 키 대문자로 사용)
   git commit -m "[SWINNOTEAM-906] feat: ..."

4. Hook 자동 실행
   ↓
   work_log.txt에 기록
   [2026-01-27 HH:MM:SS] [SWINNOTEAM-906] | branch | 4.5h | hash

5. PR/Merge 후 Jira 업데이트
   Status: Done (make-jira 스킬로 자동)
```

---

## 3. Type 분류

### 개발 업무

| Type | 설명 | 예시 |
|------|------|------|
| **feat** | 새 기능 | 병렬 테스트 추가 |
| **fix** | 버그 수정 | 테스트 실패 해결 |
| **refactor** | 코드 개선 | 함수명 변경 |
| **docs** | 문서 작성 | README 추가 |
| **test** | 테스트 추가 | 테스트 케이스 추가 |
| **chore** | 유지보수 | 의존성 업데이트 |
| **ci** | CI/CD 설정 | GitHub Actions 추가 |
| **perf** | 성능 개선 | 쿼리 최적화 |

### 비개발 업무

| Type | 설명 | 예시 |
|------|------|------|
| **coordination** | 팀간 협력/조율 | AX BI-Weekly 자료 정리 |
| **assessment** | 검토/평가 | 자료 검토, 방안 평가 |
| **approval** | 승인/결재 | 팀장 승인, 방안 승인 |
| **meeting** | 회의 진행 | BI-Weekly 회의, 팀 미팅 |

---

## 4. Category 분류

### 개발 관련

| Category | 대상 | 예시 |
|----------|------|------|
| **Testing** | 테스트 관련 | pytest-xdist, conftest 설정 |
| **Infrastructure** | 인프라 | Docker, Kubernetes, CI/CD |
| **Documentation** | 문서 | README, API 문서, 가이드 |
| **Performance** | 성능 | 최적화, 벤치마크 |
| **Security** | 보안 | 인증, 암호화 |

### 비개발 관련

| Category | 대상 | 예시 |
|----------|------|------|
| **Communication** | 소통/보고 | BI-Weekly, 주간보고, 회의록 |
| **Coordination** | 협력/조율 | 팀간 협력, 다부서 작업 |
| **Training** | 교육/온보딩 | 팀 교육, 신입 온보딩 |
| **Other** | 기타 | 기타 작업 |

---

## 5. Audience 분류

| Audience | 대상 | 예시 |
|----------|------|------|
| **All** | 전체 팀 | 공개 기능, 문서 |
| **Dev** | 개발자 | 개발 환경 설정 |
| **QA** | QA 팀 | 테스트 기능 |
| **Internal** | 내부 전용 | 회사 정책 |

---

## 6. Daily 루틴

### 작업 시작 시 (2분) - "Jira First"

```bash
# 1️⃣ Jira에서 오늘의 티켓 확인/생성
# 예시 1 (개발): SWINNOTEAM-906 (Status: To Do, 병렬 테스트 구현)
# 예시 2 (협업): SWINNOTEAM-903 (Status: To Do, AX BI-Weekly 준비)
# 예상시간: 4.5h 또는 2.5h

# 2️⃣ Git 작업이 필요한 경우: 브랜치 생성 (소문자로 변환)
git checkout -b swinnoteam-906-parallel-testing

# 💡 Git 작업이 불필요한 경우: CLI 도구로 기록만 진행
# (예: 협업, 회의, 검토 등은 Git branch가 없을 수 있음)

# 3️⃣ 오늘 할 일 3개 작성 (임시 메모)
echo "- [SWINNOTEAM-906] 테스트 수정
- [SWINNOTEAM-903] AX 자료 정리
- [SWINNOTEAM-907] 문서 작성" > /tmp/today.txt
```

### 작업 중 (0분 오버헤드)

```bash
# 1️⃣ 작은 단위로 자주 커밋
git add <file>
git commit  # .gitmessage 템플릿 사용

# 예: git commit
# → 에디터에 .gitmessage 템플릿 자동 로드
# → [SWINNO-943] type: description 형식 입력
# → 저장하면 post-commit hook 자동 실행

# 2️⃣ 메시지에 태그 추가 (선택)
# [결정] 선택한 이유
# [변경] 무엇을 변경했는지
# [리스크] 잠재적 위험
# [검증] 테스트 방법
```

### 작업 종료 전 (5분)

```bash
# 1️⃣ 3줄 정리 (중요!)
# Jira에 댓글로 작성:
오늘 한 일: 15개 테스트 수정 완료
내일 할 일: 문서 작성
막힌 것: 없음

# 2️⃣ Git push (브랜치는 소문자)
git push origin swinnoteam-906-parallel-testing

# 3️⃣ work_log.txt 자동 생성 확인 (hook)
cat ~/work_log.txt | tail -5
# 결과 예시:
# [2026-01-27 17:29] [SWINNOTEAM-906] | swinnoteam-906-parallel-testing | 4.5h | abc1234
#   └─ Category: Testing
```

**⚠️ 중요: "Jira First" 워크플로우**:
- 작업 시작 전에 **반드시** Jira 티켓 생성/확인
- **개발 업무**: Git 브랜치명과 커밋 메시지에 Jira 키 포함 → Hook 자동 기록
- **비개발 업무**: CLI 도구(`work-log add`) 또는 수동 기록
- 모든 work_log.txt 기록은 주간보고, Jira 업데이트 자동화에 사용됨

---

## 7. work_log.txt 자동 기록

### Git 커밋 방식 (개발 업무)

Post-commit hook이 자동으로 검증 및 기록:

✅ 커밋 메시지 포맷 검증
✅ Jira 키 존재 여부 확인
✅ 불필요한 공백 제거
✅ work_log.txt에 자동 기록

```
[2026-01-27 HH:MM:SS] [SWINNOTEAM-906] | branch | 4.5h | hash
  └─ Category: Testing
```

### CLI 도구 방식 (비개발 업무)

Git commit이 없는 경우 CLI 도구로 수동 기록:

```bash
# 작업 완료 후
work-log add SWINNOTEAM-903 \
  --type coordination \
  --category Communication \
  --time 2.5h

# 결과: work_log.txt에 기록됨
# [2026-01-27 HH:MM:SS] [SWINNOTEAM-903] | coordination | Communication | 2.5h | manual
```

---

## 8. 팀 적용

### Week 1

- [ ] 이 문서 공유
- [ ] 팀원과 규칙 논의
- [ ] 예시 커밋 몇 개 함께 작성
- [ ] Pre-commit hook 설정

### Week 2+

- [ ] 자동 보고 스크립트 적용
- [ ] Jira/Confluence 동기화
- [ ] 팀 피드백 수집

---

**상태**: v2.0 완성 (개발/비개발 업무 통합)
**다음**:
- CLI 도구 (work-log add) 개발 (P2)
- 팀 검토 및 피드백 수집
