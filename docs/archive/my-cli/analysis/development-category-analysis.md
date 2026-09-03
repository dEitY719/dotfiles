# Development Category Analysis

**카테고리**: Development
**Topics**: git, uv, py, nvm, npm, pp, cli, ux, du, psql, mytool
**총 11개**

---

## 1. Git ⭐⭐⭐⭐⭐ (Tier 1)

**파일**: `git_help.sh` (79줄)
**사용 빈도**: Daily (5~10회)

### 현황
```
7개 섹션 + 72줄 콘텐츠
- Basic Commands (11개)
- Fetch & Sync (5개)
- Logs (4개)
- Upstream (4개)
- Branch Configuration (4개)
- Cherry-pick (6개)
- Git LFS (2개)
```

### 콘텐츠 분석

| 섹션 | 항목 수 | 우선순위 | 설명 |
|------|--------|---------|------|
| Basic | 11 | ⭐⭐⭐⭐⭐ | 매일 사용 (status, add, commit, push) |
| Fetch & Sync | 5 | ⭐⭐⭐⭐ | 주 2-3회 사용 |
| Logs | 4 | ⭐⭐⭐ | 시각화 필요 시 사용 |
| Upstream | 4 | ⭐⭐⭐ | 멀티브랜치 작업 시 사용 |
| Branch Config | 4 | ⭐⭐ | 브랜치 설정 (초기 1회) |
| Cherry-pick | 6 | ⭐⭐ | 특수 작업 시에만 사용 |
| Git LFS | 2 | ⭐ | 드물게 사용 |

### 개선 방향

**Quick Mode (TUI 기본 표시)**
```
필수 7개 명령어만:
- gs   : git status
- ga   : git add
- gc   : git commit
- gp   : git push
- gpl  : git pull
- gco  : git checkout
- gd   : git diff
```

**Full Mode (--full 플래그)**
```
모든 섹션 포함 (현재 상태 유지)
```

**색상 복구**
- ANSI 컬러코드 유지
- Terminal에서 색상 표현

### 메타데이터
```yaml
importance: 5
frequency: "daily"
complexity: "complex"
quick_count: 7
full_count: 36
```

---

## 2. Python ⭐⭐⭐⭐⭐ (Tier 1)

**파일**: `py_help.sh` (38줄)
**사용 빈도**: Daily (2~5회)

### 현황
```
4개 섹션 + 34줄 콘텐츠
- Full Commands (5개)
- Short Aliases (5개)
- Setup Tools (2개)
- Quick Workflow (workflow example)
```

### 콘텐츠 분석

이미 최적화된 상태 ✅

| 섹션 | 항목 수 | 우선순위 | 설명 |
|------|--------|---------|------|
| Full Commands | 5 | ⭐⭐⭐⭐⭐ | 필수: cv, av, dv |
| Short Aliases | 5 | ⭐⭐⭐⭐ | 단축키 (매일 사용) |
| Setup Tools | 2 | ⭐⭐⭐ | Python 버전 관리 |
| Workflow | - | ⭐⭐⭐⭐⭐ | 실행 순서 표시 |

### 개선 방향

**현재 상태 유지** (이미 최적화됨)
```
Quick Mode = 현재 상태 (38줄 그대로)
Full Mode = 현재 상태 (동일)
```

**색상 복구만 필요**
- ANSI 컬러코드 유지
- 섹션 헤더 색상 표현

### 메타데이터
```yaml
importance: 5
frequency: "daily"
complexity: "simple"
quick_count: 5
full_count: 5
optimization_status: "✅ Already Optimal"
```

---

## 3. UV ⭐⭐⭐⭐ (Tier 1)

**파일**: `uv_help.sh` (34줄)
**사용 빈도**: Weekly+ (2~4회)

### 현황
```
분석 필요
```

### 분석 대기

---

## 4. NPM ⭐⭐⭐⭐ (Tier 2)

**파일**: `npm_help.sh` (127줄)
**사용 빈도**: Weekly (2~3회)

### 현황
```
예상 7개 섹션 + 120줄
- Info & Version
- Install
- Uninstall
- Maintenance
- Scripts
- Registry
- Tips
```

### 개선 방향

**Quick Mode (필수 명령어)**
```
- npm install (또는 npm i)
- npm install --save-dev (또는 npm isd)
- npm run {script}
- npm version
- npm outdated
총 5개
```

**Full Mode**
```
모든 섹션 포함
```

### 우선순위
- CL-7.4 (후순위 - 상세 분석 후)

---

## 5. NVM ⭐⭐⭐ (Tier 2)

**파일**: `nvm_help.sh` (20줄)
**사용 빈도**: Monthly (초기 설정)

### 현황
```
간단함 (20줄)
- Node 버전 관리 도구
- 설치 후 거의 사용 안 함
```

### 개선 방향
```
현재 상태 유지 (매우 간단)
```

---

## 6. PP ⭐⭐⭐ (Tier 2)

**파일**: `pp_help.sh` (35줄)
**사용 빈도**: Weekly (2회)

### 분석 대기

---

## 7. CLI ⭐⭐⭐ (Tier 2)

**파일**: `cli_help.sh` (46줄)
**사용 빈도**: Weekly (1~2회)

### 분석 대기

---

## 8. UX ⭐⭐⭐ (Tier 2)

**파일**: `ux_help.sh` (140줄)
**사용 빈도**: Reference (거의 사용 안 함)

### 분석 대기

---

## 9. DU ⭐⭐ (Tier 3)

**파일**: `du_help.sh` (20줄)
**사용 빈도**: Monthly

### 분석 대기

---

## 10. PSQL ⭐⭐ (Tier 2)

**파일**: `psql_help.sh` (35줄)
**사용 빈도**: Weekly (개발 시)

### 분석 대기

---

## 11. MYTOOL ⭐⭐ (Tier 2)

**파일**: `mytool_help.sh` (127줄)
**사용 빈도**: Weekly (특정 프로젝트)

### 분석 대기

---

## 📊 Summary

| Topic | Lines | Tier | Frequency | Status |
|-------|-------|------|-----------|--------|
| git | 79 | 1 | Daily | ✅ Analyzed |
| py | 38 | 1 | Daily | ✅ Analyzed |
| uv | 34 | 1 | Weekly+ | ⏳ Pending |
| npm | 127 | 2 | Weekly | ⏳ Pending |
| nvm | 20 | 2 | Monthly | ⏳ Pending |
| pp | 35 | 2 | Weekly | ⏳ Pending |
| cli | 46 | 2 | Weekly | ⏳ Pending |
| ux | 140 | 2 | Ref | ⏳ Pending |
| du | 20 | 3 | Monthly | ⏳ Pending |
| psql | 35 | 2 | Weekly | ⏳ Pending |
| mytool | 127 | 2 | Weekly | ⏳ Pending |

---

## 🎯 Next Steps

1. ✅ Git 분석 완료
2. ✅ Python 분석 완료
3. ⏳ UV 상세 분석
4. ⏳ NPM 상세 분석
5. ⏳ 나머지 항목 순차 분석
