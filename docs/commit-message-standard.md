# Git Commit & Branch Naming Standard

## 목표

모든 작업을 Git에 추적 가능하게 기록하여 SSOT 확보.

---

## 1. 브랜치 명명 규칙

### 형식

```
{jira-key}-{short-description}
```

### 예시

```bash
# 기능 개발
proj-245-parallel-testing
proj-246-docker-optimization

# 버그 수정
hotfix-123-login-bug
hotfix-124-memory-leak

# 리팩토링
refactor-145-auth-module
```

### 규칙

- 소문자만 사용
- 단어는 `-` (하이픈)으로 구분
- 최대 50자
- 의미있는 설명 포함

---

## 2. 커밋 메시지 형식

### 기본 템플릿

```
[JIRA-XXX] type: description

상세 설명
- 주요 변경사항 1
- 주요 변경사항 2

메타정보:
- Category: {Testing/Infrastructure/Documentation/Other}
- TimeSpent: {시간}h
- WorkLogTime: {시간}h
- Audience: {All/Dev/QA/Internal}

태그 (선택):
- [결정] 중요한 의사결정
- [변경] 주요 변경사항
- [리스크] 잠재적 위험
- [검증] 테스트/검증 방법
```

### 실전 예시

```
[PROJ-245] feat: implement parallel testing with pytest-xdist

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

---

## 3. Type 분류

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

---

## 4. Category 분류

| Category | 대상 | 예시 |
|----------|------|------|
| **Testing** | 테스트 관련 | pytest-xdist, conftest 설정 |
| **Infrastructure** | 인프라 | Docker, Kubernetes, CI/CD |
| **Documentation** | 문서 | README, API 문서, 가이드 |
| **Performance** | 성능 | 최적화, 벤치마크 |
| **Security** | 보안 | 인증, 암호화 |
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

### 작업 시작 시 (2분)

```bash
# 1. 브랜치 생성 (티켓 키 포함)
git checkout -b proj-245-parallel-testing

# 2. 오늘 할 일 3개 작성 (임시 메모)
echo "- [PROJ-245] 테스트 수정
- [PROJ-246] 문서 작성
- [PROJ-247] 리뷰 반영" > /tmp/today.txt
```

### 작업 중 (0분 오버헤드)

```bash
# 1. 작은 단위로 자주 커밋
git add <file>
git commit  # .gitmessage 템플릿 사용

# 2. 메시지에 태그 추가 (선택)
# [결정], [변경], [리스크], [검증]
```

### 작업 종료 전 (5분)

```bash
# 1. 3줄 정리 (중요!)
오늘 한 일: 15개 테스트 수정 완료
내일 할 일: 문서 작성
막힌 것: 없음

# 2. Git push
git push origin proj-245-parallel-testing

# 3. work_log.txt 자동 생성 확인 (hook)
cat ~/work_log.txt | tail -5
```

---

## 7. Pre-commit Hook 검증

커밋 전 자동으로 검증됨:

✅ 커밋 메시지 포맷
✅ 티켓 키 존재 여부
✅ 불필요한 공백 제거
✅ 파일 크기 제한

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

**상태**: 초안 완성
**다음**: .gitmessage 파일 생성
