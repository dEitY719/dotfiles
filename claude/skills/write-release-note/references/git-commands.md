# Git Commands for Release Notes

## 앵커 커밋 찾기

### 1) 태그 기반 (가장 신뢰할 수 있음)

```bash
# 로컬 태그
git tag --list '*<prev-version>*' --sort=-creatordate

# 원격에만 태그가 있을 수 있음
git fetch --tags
git tag --list '*<prev-version>*'
```

### 2) 이전 릴리즈 노트 문서 커밋

태그가 없는 프로젝트에서 가장 흔한 관례. 릴리즈 노트 커밋 자체가 릴리즈 경계 역할을 한다.

```bash
git log --oneline --format="%H %s" | grep -i "<prev-version>"
# 예시 출력: 073376f docs: add v0.1.0-alpha2 release notes
```

### 3) 사용자 확인

위 두 가지로 찾을 수 없으면 사용자에게 시작 커밋 해시 또는 날짜를 직접 확인한다.

## 커밋 수집

```bash
# 전체 커밋 (시간 순)
git log --oneline --reverse <anchor>..HEAD

# 개수
git log --oneline --reverse <anchor>..HEAD | wc -l

# 날짜 범위 (시작 / 끝)
git log --format="%ad" --date=short <anchor>..HEAD | sort | head -1
git log --format="%ad" --date=short <anchor>..HEAD | sort | tail -1
```

## 타입별 필터링 (conventional commits)

```bash
# 기능 추가
git log --oneline --reverse <anchor>..HEAD | grep -E "^[a-f0-9]+ feat:"

# 버그 수정
git log --oneline --reverse <anchor>..HEAD | grep -E "^[a-f0-9]+ fix:"

# 리팩토링
git log --oneline --reverse <anchor>..HEAD | grep -E "^[a-f0-9]+ refactor:"

# 문서/잡무
git log --oneline --reverse <anchor>..HEAD | grep -E "^[a-f0-9]+ (docs|chore):"

# ⚠️ 비관례 커밋 (놓치지 말 것)
git log --oneline --reverse <anchor>..HEAD | grep -vE "^[a-f0-9]+ (feat|fix|refactor|docs|chore|test|build|ci|perf|style):"
```

## 변경 파일 확인 (테마 그룹핑 시 유용)

```bash
# 특정 커밋이 어느 영역을 건드렸는지
git show --stat <commit-hash>

# 범위 전체에서 자주 변경된 파일 (핵심 변경 영역 파악)
git log --name-only --pretty=format: <anchor>..HEAD | sort | uniq -c | sort -rn | head -20
```

## 기여자 목록

```bash
git log --format="%an" <anchor>..HEAD | sort -u
```
