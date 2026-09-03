# Legacy Help System Analysis

**목적**: my-cli 마이그레이션을 위한 legacy `my-help` 기능 분석
**작성일**: 2026-02-20
**상태**: 분석 중 (CL-7.0 Discovery)

---

## 📊 Overview

### 현황
- **Total Help Files**: 34개 (my_help.sh + 33개 topic helpers)
- **Categories**: 8개 (ai, cli, config, development, devops, docs, meta, system)
- **Total Lines**: ~2,000줄

### 분류 기준
| Priority | 사용 빈도 | 일일 사용 횟수 | 중요도 |
|----------|---------|-------------|-------|
| Tier 1 | Daily+ | 2~10회 | Critical |
| Tier 2 | Weekly | 2~4회 | High |
| Tier 3 | Monthly | 1~2회 | Medium |
| Tier 4 | Reference | < 1회 | Low |

---

## 🎯 Category Analysis

### Development (11 topics)
**Topics**: git, uv, py, nvm, npm, pp, cli, ux, du, psql, mytool

#### Git (79 줄) - Tier 1 ⭐⭐⭐⭐⭐
```
Sections:
- Basic Commands (11 aliases)
- Fetch & Sync (5 commands)
- Logs (4 commands)
- Upstream (4 commands)
- Branch Configuration (4 commands)
- Cherry-pick (5 commands)
- Git LFS (2 commands)
```

**분석:**
- 매우 복잡함 (79줄)
- 일일 사용 빈도: 높음
- **현재 표시 항목**: 모든 섹션 (20~30줄)
- **개선안**:
  - **TUI Quick Mode**: 기본 명령어만 (gs, ga, gc, gp, gpl, gco, gd) = 7개
  - **TUI Full Mode**: 현재 그대로
  - **색상 유지**: ANSI 컬러 복구

**우선순위**: CL-7.3 (중점 리팩토링)

---

#### Python (38줄) - Tier 1 ⭐⭐⭐⭐⭐
```
Sections:
- Full Commands (5 main commands)
- Short Aliases (5 short forms)
- Setup Tools (2 tools)
- Quick Workflow (workflow example)
```

**분석:**
- 적당한 크기 (38줄)
- 일일 사용 빈도: 높음
- **현재 표시 항목**: 전부 (38줄)
- **개선안**:
  - **현재 상태 유지** (이미 최적화됨)
  - 필수 4개: cv, av, dv, pip install
  - 보충 정보: Full/Short 섹션
  - 색상 유지

**우선순위**: CL-7.1 (색상 복구만)

---

#### UV (34줄) - Tier 1 ⭐⭐⭐⭐
```
구조 미확인 (분석 필요)
```

---

#### NPM (127줄) - Tier 2 ⭐⭐⭐⭐
```
Expected Sections:
- Info & Version
- Install
- Uninstall
- Maintenance
- Scripts
- ...
```

**분석:**
- 복잡함 (127줄)
- 일일 사용 빈도: 중간
- **현재 표시 항목**: 모든 섹션
- **개선안**:
  - **Quick Mode**: install, scripts, version (7~10개)
  - **Full Mode**: 현재 그대로

**우선순위**: CL-7.4 (후순위)

---

#### 기타 (nvm, pp, cli, ux, du, psql, mytool)
- **상태**: 분석 필요
- **예상 우선순위**: CL-7.5+

---

### DevOps (7 topics)
**Topics**: docker, dproxy, sys, proxy, mount, mysql, gpu

#### Docker (64줄) - Tier 2 ⭐⭐⭐

#### Proxy (91줄) - Tier 2 ⭐⭐⭐

#### 기타 (dproxy, sys, mount, mysql, gpu)
- **상태**: 분석 필요
- **우선순위**: CL-7.5+

---

### AI/LLM (7 topics)
**Topics**: claude, cc, gemini, codex, litellm, ollama, claude_plugins, claude_skills_marketplace

#### Claude (138줄) - Tier 2 ⭐⭐⭐

#### 기타
- **상태**: 분석 필요
- **우선순위**: CL-7.5+

---

### CLI (10 topics)
**Topics**: fzf, fd, fasd, ripgrep, pet, bat, zsh, zsh_autosuggestions, gc

#### Bat (137줄) - Tier 2 ⭐⭐⭐

#### 기타
- **상태**: 분석 필요
- **우선순위**: CL-7.5+

---

### Config (4 topics)
**Topics**: p10k, crt, apt, pip

- **상태**: 분석 필요
- **우선순위**: CL-7.5+

---

### Docs (5 topics)
**Topics**: dot, show_doc, notion, work_log, work

- **상태**: 분석 필요
- **우선순위**: CL-7.5+

---

### System (2 topics)
**Topics**: dir, opencode

#### Dir (51줄) - Tier 2 ⭐⭐⭐

#### Opencode
- **상태**: 분석 필요

---

### Meta (2 topics)
**Topics**: category, register

#### Category (37줄) - Tier 3 ⭐⭐

#### Register (33줄) - Tier 3 ⭐⭐

---

## 📈 Phased Migration Plan

### CL-7.1: 기본 UI 개선 (1-2시간)
```
목표: 현재 색상/레이아웃 문제 해결
- ANSI 색상 복구
- 의미없는 테두리 제거
- 페이지네이션 개선
```

### CL-7.2: 데이터 모델 확장 (2-3시간)
```
목표: HelpTopic에 구조 추가
- summary 필드
- categories[] (다중 섹션)
- importance (Tier 분류)
- quick_items (필수 항목만)
```

### CL-7.3: Git 리팩토링 (상세)
```
목표: Git을 Tier 1 우선순위로 최적화
- Quick Mode: 기본 7개
- Full Mode: 현재 모든 항목
- 모드 선택 UI
```

### CL-7.4+: 나머지 Tier 1, 2 순차 처리
```
우선순위:
1. Py (CL-7.1에서 색상만)
2. UV (분석 후 CL-7.2)
3. NPM (분석 후 CL-7.3)
4. Docker (분석 후 CL-7.4)
...
```

---

## 📝 Template: Topic Analysis

각 Topic별 상세 분석을 위한 템플릿:

```markdown
## {Topic Name}

**파일**: {filename}
**라인 수**: {lines}
**카테고리**: {category}
**Tier**: {priority}

### 현황
- 구조: (섹션 분석)
- 복잡도: Simple / Medium / Complex
- 사용 빈도: (추정)

### 콘텐츠 분석
- 필수 항목: (4~5개)
- 보충 정보: (섹션)
- 고급 기능: (선택적)

### 개선 방향
- Quick Mode: (5줄 미만)
- Full Mode: (현재 또는 개선)
- 색상: (유지 / 개선)

### 메타데이터
- importance: (1-5)
- frequency: (daily / weekly / monthly)
- complexity: (simple / medium / complex)
```

---

## 🔄 Next Steps

1. ✅ Overview 분석 완료
2. ⏳ 각 Topic 상세 분석 (진행 중)
3. ⏳ 우선순위 확정
4. ⏳ 각 CL-7.x 구현 계획 작성

---

**참고**: 이 문서는 분석 진행에 따라 계속 업데이트될 예정입니다.
