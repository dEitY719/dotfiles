# REQ-CLI-MyCLI-1: Personal CLI Tool Suite (my-cli)

## 🎯 핵심 결정사항 (Decision Log)

| 결정 | 상태 | 사유 |
|------|------|------|
| **TUI 라이브러리** | ✅ **ink** | v0.1부터 프로페셔널 UX (chalk 스킵) |
| **학습 경로** | 📖 병렬 학습 | 2주간 TypeScript/React/ink 동시 학습 |
| **프로젝트 위치** | 📁 dotfiles 내부 | `/home/bwyoon/dotfiles/packages/my-cli` |
| **일정** | ⏱️ 8주 | v0.1.0 릴리스 목표 |

**주의**: TypeScript 초보자이므로 학습 가이드 (`req-CLI-MyCLI-1-learning-guide.md`)를 반드시 참고하세요.

---

## Overview

| Field | Value |
|-------|-------|
| **REQ ID** | REQ-CLI-MyCLI-1 |
| **Title** | Personal CLI Tool Suite (my-cli) |
| **Type** | CLI Application |
| **Priority** | Medium |
| **Status** | Design Phase → Learning Phase (Week 1-2) |
| **Target Language** | TypeScript/Node.js |
| **TUI Framework** | **ink (React-based)** ⭐ |
| **Reference Architecture** | gemini-cli + ink examples |
| **Expected Launch** | Week 7 (v0.1.0) |

---

## 1. Requirement Summary

### Problem Statement
현재 dotfiles에는 shell script 기반의 분산된 도움말 시스템(`my-help`)이 존재합니다. 이를 통합하고 확장하여 더 강력하고 확장 가능한 CLI 도구 모음을 제공하고자 합니다.

### Goal
**gemini-cli의 아키텍처를 참고하여 TypeScript/Node.js 기반의 개인용 CLI 도구 모음(`my-cli`)을 개발합니다.**

주요 특징:
- 기존 my-help 함수의 기능을 보존 및 확장
- 모던 TypeScript/Node.js 스택 구현
- 모노레포 구조 (packages/* 방식)
- Interactive TUI 지원
- 플러그인/확장 가능한 아키텍처
- Non-interactive 모드 (스크립팅 지원)

---

## 2. Architectural Design

### 2.1 Project Location & Integration

**위치**: `/home/bwyoon/dotfiles/packages/my-cli`

```
/home/bwyoon/dotfiles/
├── shell-common/
│   └── functions/
│       ├── my_help.sh              # 현재: Shell 버전 (유지)
│       └── my_cli_bridge.sh          # 신규: TypeScript 버전과 연결
├── packages/
│   └── my-cli/                      # ⭐ 새로운 TypeScript 프로젝트
│       ├── packages/
│       ├── scripts/
│       └── configuration files
└── ... (기존 구조 유지)
```

**통합 방식**:
- `my-cli` 프로젝트는 dotfiles 내 `packages/my-cli/` 디렉토리에 위치
- 기존 `my_help.sh`는 유지 (Fallback용)
- 신규 `my_cli_bridge.sh` 함수가 TypeScript 바이너리를 호출
- 별도 npm package로는 배포하지 않음 (dotfiles 내부 tools)

### 2.2 Reference Architecture: gemini-cli

gemini-cli의 모범 사례:

| 측면 | 구현 방식 | 우리의 적용 |
|------|---------|-----------|
| **언어** | TypeScript + Node.js 20+ | ✅ TypeScript |
| **구조** | npm workspace (monorepo) | ✅ packages/* 구조 |
| **빌드** | esbuild + bundling | ✅ esbuild 적용 |
| **테스트** | vitest + integration tests | ✅ vitest |
| **UI** | ink (React 기반 TUI) | ✅ 검토 대상 |
| **CLI 패턴** | slash commands (/help, /chat) | ✅ 적용 |
| **설정** | JSON config files | ✅ ~/.my-cli/config.json |

### 2.3 Project Structure

```
/home/bwyoon/dotfiles/packages/my-cli/
├── packages/
│   ├── core/                        # Core 라이브러리
│   │   ├── src/
│   │   │   ├── cli/
│   │   │   │   ├── commands.ts          # 명령어 체계
│   │   │   │   ├── parser.ts            # 인자 파싱
│   │   │   │   └── executor.ts          # 명령어 실행
│   │   │   ├── help/
│   │   │   │   ├── registry.ts          # 도움말 등록 시스템
│   │   │   │   ├── formatter.ts         # 포맷팅
│   │   │   │   └── categories.ts        # 카테고리 관리
│   │   │   ├── ui/
│   │   │   │   ├── components.ts        # TUI 컴포넌트
│   │   │   │   └── styles.ts            # 스타일/색상
│   │   │   ├── config/
│   │   │   │   └── loader.ts            # 설정 로딩
│   │   │   ├── utils/
│   │   │   │   └── logger.ts            # 로깅
│   │   │   └── types.ts
│   │   ├── tests/
│   │   └── package.json
│   │
│   ├── cli/                         # CLI 진입점
│   │   ├── src/
│   │   │   └── index.ts                 # bin 진입점
│   │   ├── bin/
│   │   │   └── my-cli.ts                # 실행 파일
│   │   └── package.json
│   │
│   └── plugins/                     # Plugin system (향후)
│       ├── git-help/
│       ├── docker-help/
│       ├── python-help/
│       └── ... (각 도메인별 플러그인)
│
├── scripts/
│   ├── build.ts                     # TypeScript 빌드
│   ├── bundle.ts                    # esbuild 번들링
│   ├── generate-docs.ts             # 문서 생성
│   └── migrate-help-data.ts          # Shell → TS 데이터 마이그레이션
│
├── package.json                     # Root workspace
├── tsconfig.json
├── esbuild.config.js
├── vitest.config.ts
├── README.md
└── DEVELOPMENT.md                   # 개발 가이드
```

**Shell과의 브릿지**:
```bash
# /home/bwyoon/dotfiles/shell-common/functions/my_cli_bridge.sh
my-cli() {
  if command -v node >/dev/null 2>&1; then
    # dotfiles/packages/my-cli 실행
    node /home/bwyoon/dotfiles/packages/my-cli/dist/bin/my-cli.js "$@"
  else
    # Fallback: 기존 my-help 함수 사용
    my-help "$@"
  fi
}
```

### 2.4 Technology Stack

```json
{
  "runtime": {
    "node": ">=20.0.0",
    "npm": "workspace monorepo"
  },
  "core_dependencies": {
    "typescript": "^5.x",
    "yargs": "CLI argument parsing",
    "react": "^18.x (for ink)",
    "ink": "React-based TUI (PRIMARY)",
    "fs-extra": "file utilities"
  },
  "dev_dependencies": {
    "vitest": "unit/integration tests",
    "esbuild": "bundling",
    "tsx": "TypeScript execution",
    "eslint": "code quality",
    "prettier": "code formatting",
    "@types/react": "type definitions"
  }
}
```

**주요 결정: ink를 v0.1부터 도입**
- ✅ 처음부터 프로페셔널 TUI
- ✅ gemini-cli 수준의 UX
- ⚠️ React 학습 필수 (하지만 관리 가능)

**Root package.json (dotfiles 내)**
```json
{
  "name": "dotfiles",
  "private": true,
  "workspaces": [
    "packages/*",
    "packages/my-cli/packages/*"
  ]
}
```

**my-cli Root package.json**
```json
{
  "name": "@dotfiles/my-cli-root",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "workspaces": [
    "packages/*"
  ],
  "engines": {
    "node": ">=20.0.0"
  },
  "scripts": {
    "build": "tsx scripts/build.ts",
    "bundle": "node esbuild.config.js",
    "test": "vitest run",
    "test:watch": "vitest",
    "lint": "eslint . --fix",
    "format": "prettier --write .",
    "dev": "tsx --watch packages/cli/src/index.ts"
  }
}
```

---

## 3. Core Features

### 3.1 Help System (my-help 진화)

#### Current State (Shell)
```bash
my-help              # 모든 카테고리 표시
my-help ai           # AI/LLM 카테고리 보기
my-help git          # git 도움말 보기
```

#### Target State (TypeScript)
```typescript
// Interactive mode
my-cli help              # 카테고리 선택 (TUI)
my-cli help ai          # AI 카테고리 상세 (TUI)
my-cli help git --detail  # git 도움말 (더 많은 정보)

// Non-interactive mode
my-cli help --json      # JSON 형식 출력 (스크립팅용)
my-cli help --text      # 순수 텍스트 (파이프용)
```

### 3.2 Help Registry System

**Before (Shell - associative array)**
```bash
HELP_DESCRIPTIONS["git_help"]="[Development] Git shortcuts"
HELP_CATEGORY_MEMBERS[development]="git uv py nvm npm pp cli"
```

**After (TypeScript - type-safe)**
```typescript
interface HelpTopic {
  id: string;
  name: string;
  description: string;
  category: HelpCategory;
  details?: string;
  examples?: CommandExample[];
}

interface HelpCategory {
  key: string;
  label: string;
  description: string;
  topics: HelpTopic[];
}

// Registry 사용
helpRegistry.register({
  id: 'git',
  name: 'Git',
  category: 'development',
  description: '[Development] Git version control shortcuts',
  examples: [...]
});
```

### 3.3 Plugin Architecture

```typescript
// Plugin interface
interface CliPlugin {
  name: string;
  version: string;
  commands: CliCommand[];
  helpTopics: HelpTopic[];
  initialize(): Promise<void>;
}

// 각 도메인별 플러그인
packages/plugins/git-help/
packages/plugins/docker-help/
packages/plugins/python-help/
```

### 3.4 Command System

```typescript
interface CliCommand {
  name: string;
  aliases: string[];
  description: string;
  options: CliOption[];
  handler: (args: ParsedArgs) => Promise<void>;
}

// Examples
commands: [
  {
    name: 'help',
    aliases: ['h'],
    description: 'Show help',
    options: [
      { name: 'category', type: 'string', description: 'Category name' },
      { name: 'json', type: 'boolean', description: 'JSON output' }
    ],
    handler: async (args) => { ... }
  }
]
```

---

## 4. Implementation Phases

### Phase 1: React/TypeScript Foundation + Core Infrastructure (Week 1-2)

**선행 학습** (병렬):
- [ ] TypeScript 기본 문법 (함수, 타입, 클래스)
- [ ] React 개념 이해 (JSX, 컴포넌트, props, state)
- [ ] ink 라이브러리 튜토리얼

**개발**:
- [ ] Project setup (monorepo, tsconfig, esbuild, vitest)
- [ ] CLI argument parser (yargs)
- [ ] Help registry system (TypeScript 버전)
- [ ] Category management
- [ ] ink 기본 렌더링 (Box, Text 컴포넌트)
- [ ] Config loader (~/.my-cli/config.json)

### Phase 2: Help System Migration + Interactive TUI (Week 2-4)

**데이터 마이그레이션**:
- [ ] Shell data 추출 (HELP_DESCRIPTIONS, HELP_CATEGORIES)
- [ ] TypeScript data structure로 변환
- [ ] 기존 my-help 기능 100% 포팅

**Interactive TUI 구현** (ink 기반):
- [ ] 카테고리 탐색 UI
  - 화살표 키 네비게이션
  - 선택 기능 (Enter)
  - 돌아가기 (ESC/q)
- [ ] 토픽 상세보기
  - 포맷된 텍스트 표시
  - 스크롤 기능 (필요시)
- [ ] 검색 기능
  - 실시간 검색 UI
  - 검색 결과 표시

**Non-interactive 모드**:
- [ ] JSON 출력 (--json flag)
- [ ] 텍스트 출력 (--text flag)
- [ ] 스크립팅 호환성

### Phase 3: Plugin System (Week 4-5)

- [ ] Plugin loader architecture
- [ ] Plugin interface 정의
- [ ] 기존 도움말을 플러그인화
  - git_help → git-help plugin
  - docker_help → docker-help plugin
  - ... 등
- [ ] Hot-reload (개발 환경)

### Phase 4: Testing & Documentation (Week 5-6)

- [ ] Unit tests (vitest)
- [ ] Integration tests (TUI 동작 테스트)
- [ ] E2E tests
- [ ] 사용자 가이드 (README.md)
- [ ] 개발자 가이드 (DEVELOPMENT.md)
- [ ] ink 컴포넌트 문서화

### Phase 5: Polish & Release (Week 6-7)

- [ ] Performance 최적화
- [ ] Error handling 강화
- [ ] GitHub Actions CI/CD 설정
- [ ] Version management
- [ ] Changelog 생성
- [ ] 배포 자동화

---

## 5. User Interface Design

### 5.1 Interactive Mode (TUI)

```
┌─────────────────────────────────────────────────┐
│ 📚 my-cli Help System                           │
├─────────────────────────────────────────────────┤
│ Categories:                                      │
│  [AI/LLM]        │ claude, gemini, codex...    │
│  [CLI Utilities] │ fzf, fd, ripgrep...         │
│  [Development]   │ git, uv, python...          │
│  [DevOps]        │ docker, proxy, db...        │
│  [Documentation] │ dots, notes, work...        │
│                                                  │
│ Popular Topics:                                 │
│  • git     - Git version control shortcuts     │
│  • docker  - Docker commands and aliases       │
│  • claude  - Claude Code CLI basics            │
│                                                  │
│ Navigation: my-cli help <category|topic>      │
└─────────────────────────────────────────────────┘
```

### 5.2 JSON Output (Non-interactive)

```bash
$ my-cli help ai --json
{
  "category": {
    "key": "ai",
    "label": "AI/LLM",
    "description": "AI/LLM assistants...",
    "topics": [
      {
        "id": "claude",
        "name": "Claude",
        "description": "[AI/LLM] Claude Code CLI basics",
        "examples": [...]
      },
      ...
    ]
  }
}
```

### 5.3 Help Topic Detail

```
┌─────────────────────────────────────────────────┐
│ 📖 Topic: Git                                   │
├─────────────────────────────────────────────────┤
│ Category: Development                           │
│ Description: Git version control shortcuts     │
│                                                  │
│ Common Commands:                                │
│  git-init      - Initialize a new repo         │
│  git-clone     - Clone a repository            │
│  git-commit    - Create a commit               │
│  git-push      - Push changes to remote        │
│                                                  │
│ Tips:                                           │
│  • Use 'gc' for git-crypt operations          │
│  • See: git-help for more details             │
│                                                  │
│ Run: my-cli help git --detail                  │
└─────────────────────────────────────────────────┘
```

---

## 6. Data Model

### 6.1 Help Categories (from my-help.sh)

```typescript
const HELP_CATEGORIES = {
  ai: "AI/LLM assistants (Claude, Gemini, Codex, etc.)",
  cli: "CLI utilities (search, navigation, snippets, shell helpers)",
  config: "Configuration and setup (prompt, certs, package managers)",
  development: "Development tools (Git, Python, package managers, UX)",
  devops: "DevOps and infrastructure (Docker, proxy, DB, system)",
  docs: "Documentation and knowledge (dotfiles docs, notes, work logs)",
  meta: "Help system utilities (category browsing, registration)",
  system: "System tools (directory navigation, opencode)"
};

const HELP_CATEGORY_MEMBERS = {
  development: ["git", "uv", "py", "nvm", "npm", "pp", "cli", "ux", "du", "psql", "mytool"],
  devops: ["docker", "dproxy", "sys", "proxy", "mount", "mysql", "gpu"],
  ai: ["claude", "cc", "gemini", "codex", "litellm", "ollama", "claude_plugins", "claude_skills_marketplace"],
  cli: ["fzf", "fd", "fasd", "ripgrep", "pet", "bat", "zsh", "zsh_autosuggestions", "gc"],
  config: ["p10k", "crt", "apt", "pip"],
  docs: ["dot", "show_doc", "notion", "work_log", "work"],
  system: ["dir", "opencode"],
  meta: ["category", "register"]
};
```

### 6.2 Help Descriptions (샘플)

```typescript
const HELP_DESCRIPTIONS = {
  uv_help: "[Development] UV packages and environments",
  git_help: "[Development] Git version control shortcuts",
  py_help: "[Development] Python environments and tooling",
  docker_help: "[DevOps] Docker commands and aliases",
  claude_help: "[AI/LLM] Claude Code + MCP integration",
  gemini_help: "[AI/LLM] Gemini CLI commands",
  // ... 40+ more entries from my-help.sh
};
```

---

## 7. API/Interface Design

### 7.1 CLI Usage Examples

```bash
# Help system
my-cli help                          # Show all categories
my-cli help ai                       # Show AI/LLM category
my-cli help git                      # Show git help
my-cli help git --detail            # Detailed git help
my-cli help --search docker         # Search for docker
my-cli help --json                  # JSON output
my-cli help --text                  # Plain text output

# Configuration
my-cli config show                  # Show current config
my-cli config set theme dark        # Set theme
my-cli config reset                 # Reset to defaults

# Plugin management
my-cli plugin list                  # List installed plugins
my-cli plugin install git-enhanced  # Install a plugin
my-cli plugin update                # Update all plugins

# Status
my-cli version                      # Show version
my-cli status                       # Check system status
```

### 7.2 TypeScript API

```typescript
// Import and use programmatically
import { HelpRegistry, HelpCommand } from '@my-cli/core';

const registry = new HelpRegistry();
await registry.load();

// Get category
const aiCategory = registry.getCategory('ai');
console.log(aiCategory.topics);

// Search
const results = registry.search('git');

// Export
const json = registry.toJSON();
```

---

## 8. Configuration

### 8.1 Config File (~/.my-cli/config.json)

```json
{
  "version": "1.0",
  "theme": "auto",
  "defaultFormat": "interactive",
  "plugins": {
    "enabled": ["git-help", "docker-help", "python-help"],
    "disabled": []
  },
  "customTopics": [
    {
      "id": "my-tool",
      "category": "development",
      "description": "[Development] My custom tool"
    }
  ]
}
```

### 8.2 Environment Variables

```bash
# Disable interactive mode
export MY_CLI_NO_INTERACTIVE=1

# Override config directory
export MY_CLI_CONFIG_DIR=/custom/path

# Debug mode
export MY_CLI_DEBUG=1

# Output format
export MY_CLI_FORMAT=json
```

---

## 9. Backwards Compatibility & Shell Integration

### 9.1 기존 my-help 함수 유지 전략

**원칙**: 기존 `my-help` 함수는 완전히 보존하되, 신규 `my-cli` 도입 후 점진적으로 마이그레이션

```bash
# 현재 상태: /dotfiles/shell-common/functions/my_help.sh
my-help() {
  # 기존 my_help_impl 함수 호출 (변경 없음)
}

# 신규: /dotfiles/shell-common/functions/my_cli_bridge.sh
my-cli() {
  if command -v node >/dev/null 2>&1; then
    # TypeScript 버전 실행
    node "${DOTFILES}/packages/my-cli/dist/bin/my-cli.js" "$@"
  else
    # Fallback: Node.js 없으면 Shell 버전 사용
    my_help_impl "$@"
  fi
}

# 별칭 (선택사항, v0.2+)
# alias my-help='my-cli help'
```

### 9.2 Phase별 호환성 관리

| Phase | 상태 | my-help | my-cli | 비고 |
|-------|------|---------|--------|------|
| v0.1 | 개발 중 | ✅ Active | ❌ Beta | 병렬 운영 |
| v0.2 | 기능 완성 | ✅ Active | ✅ Active | 선택 사용 |
| v0.3 | 안정화 | ⚠️ Maintenance | ✅ Primary | 권장 전환 |
| v1.0 | Production | 📝 Deprecated | ✅ Primary | 정책 결정 대기 |

### 9.3 Shell 호출 방식 지원

기존 스크립트 호환성:

```bash
#!/bin/bash

# Old way (계속 작동)
source ~/.dotfiles/shell-common/functions/my_help.sh
my-help git

# New way (권장)
my-cli help git

# 둘 다 지원 (선택적)
my-help git     # → my_help_impl (Shell)
my-cli git      # → TypeScript (Node.js)
```

### 9.4 Migration Path

| 단계 | 버전 | 상태 | 주요 마일스톤 |
|------|------|------|-------------|
| Phase 1 | v0.1.0 | Beta | Core infra + Help registry |
| Phase 2 | v0.2.0 | RC | Shell → TS 100% 기능 포팅 |
| Phase 3 | v0.3.0 | Stable | Plugin system, TUI 개선 |
| Phase 4 | v0.4.0 | Enhanced | Performance, docs |
| Phase 5 | v1.0.0 | Production | 정식 릴리스 |

### 9.5 데이터 호환성

Shell 배열을 TypeScript로 자동 마이그레이션:

```typescript
// /scripts/migrate-help-data.ts
// 데이터 소스: shell-common/functions/my_help.sh
// 변환: HELP_DESCRIPTIONS[] → HelpRegistry
// 변환: HELP_CATEGORIES[] → CategoryManager
// 생성: packages/core/src/data/help-registry.json

const HELP_REGISTRY_DATA = {
  categories: { ... },      // HELP_CATEGORIES
  descriptions: { ... },    // HELP_DESCRIPTIONS
  members: { ... }          // HELP_CATEGORY_MEMBERS
};
```

---

## 10. Testing Strategy

### 10.1 Test Coverage

```typescript
// Unit tests (vitest)
packages/core/tests/
├── help/
│   ├── registry.test.ts
│   ├── categories.test.ts
│   └── formatter.test.ts
├── cli/
│   ├── parser.test.ts
│   ├── commands.test.ts
│   └── executor.test.ts
└── config/
    └── loader.test.ts

// Integration tests
integration-tests/
├── help-system.test.ts
├── plugin-loading.test.ts
└── e2e-commands.test.ts
```

### 10.2 Test Examples

```typescript
describe('HelpRegistry', () => {
  it('should load categories from config', () => {
    const registry = new HelpRegistry();
    expect(registry.getCategory('ai')).toBeDefined();
  });

  it('should search topics by keyword', () => {
    const registry = new HelpRegistry();
    const results = registry.search('docker');
    expect(results).toContainEqual(expect.objectContaining({ id: 'docker' }));
  });

  it('should register custom topics', () => {
    const registry = new HelpRegistry();
    registry.registerTopic({ id: 'custom', category: 'development', ... });
    expect(registry.getTopic('custom')).toBeDefined();
  });
});
```

---

## 11. Acceptance Criteria

### 11.1 Functional Requirements

- [ ] **AF1**: Help 명령어가 모든 기존 카테고리를 표시할 수 있음
- [ ] **AF2**: 특정 카테고리 선택 시 해당 토픽 목록을 표시
- [ ] **AF3**: 특정 토픽 선택 시 상세 정보 표시
- [ ] **AF4**: 토픽 검색 기능 작동
- [ ] **AF5**: JSON/텍스트 출력 포맷 지원
- [ ] **AF6**: Interactive TUI 네비게이션
- [ ] **AF7**: 플러그인 시스템으로 확장 가능

### 11.2 Non-Functional Requirements

- [ ] **ANF1**: 명령어 응답 시간 < 100ms (Interactive)
- [ ] **ANF2**: 메모리 사용량 < 50MB (base)
- [ ] **ANF3**: 번들 크기 < 10MB (production)
- [ ] **ANF4**: TypeScript strict mode 준수
- [ ] **ANF5**: 90% 이상의 테스트 커버리지
- [ ] **ANF6**: Node.js 20+ LTS 지원

### 11.3 Quality Criteria

- [ ] **AQ1**: ESLint + Prettier 통과
- [ ] **AQ2**: TypeScript 타입 체크 통과 (strict)
- [ ] **AQ3**: 모든 파일에 JSDoc 주석
- [ ] **AQ4**: 국제화(i18n) 지원 (영어, 한국어)
- [ ] **AQ5**: 에러 처리 및 그레이스풀 폴백

---

## 12. Dependencies

### 12.1 Core Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| yargs | ^17.x | CLI argument parsing |
| typescript | ^5.x | Language |
| ink | ^5.x | React-based TUI (optional) |
| chalk | ^5.x | Terminal colors |
| fs-extra | ^11.x | File system utilities |
| cosmiconfig | ^8.x | Config file loading |

### 12.2 Dev Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| vitest | ^1.x | Unit/integration testing |
| esbuild | ^0.20.x | Bundling |
| tsx | ^4.x | TypeScript execution |
| eslint | ^8.x | Linting |
| prettier | ^3.x | Code formatting |

### 12.3 Constraints

- Node.js >= 20.0.0 (LTS)
- npm or yarn workspace 호환
- Unix/Linux/macOS 우선 지원

---

## 13. Risk & Mitigation

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|-----------|
| Shell script 마이그레이션 데이터 손실 | High | Low | 기존 my-help 완전히 보존, 병렬 운영 |
| 성능 저하 (Node.js vs Shell) | Medium | Medium | 사전 벤치마킹, 캐싱 전략 |
| 플러그인 호환성 | Medium | Medium | 명확한 API 정의, 버전 관리 |
| 의존성 보안 | Medium | Low | 정기적 업데이트, audit 체크 |

---

## 14. Success Metrics

| 지표 | 목표 |
|------|------|
| 기능 완성도 | 100% of existing my-help features |
| 테스트 커버리지 | >= 90% |
| 응답 시간 | < 100ms (interactive) |
| 문서화 | 100% of public APIs |
| 사용자 만족도 | 기존 대비 동등 이상 |

---

## 15. Team & Timeline

### 15.1 Estimated Timeline (ink 기반)

| Phase | Duration | Start | End | Notes |
|-------|----------|-------|-----|-------|
| Design Review | 0.5 week | Week 0 | Week 0.5 | 동료 리뷰 완료 |
| Learning + Infra | 2 weeks | Week 0.5 | Week 2.5 | React/ink 학습 병렬 |
| Help Migration + TUI | 2 weeks | Week 2.5 | Week 4.5 | 핵심 개발 |
| Plugin System | 1 week | Week 4.5 | Week 5.5 | 확장 아키텍처 |
| Testing & Docs | 1.5 weeks | Week 5.5 | Week 7 | 품질 보증 |
| Polish & Release | 1 week | Week 7 | Week 8 | v0.1.0 배포 |

**Total Estimated Duration: 8 weeks** (chalk 스킵으로 1주 단축)

**빠른 진행 가능 조건**:
- React 기본 개념을 빠르게 습득
- ink 예제 코드를 많이 참고
- 병렬 학습/개발

### 15.2 Team Roles

- **Architect**: 전체 구조 설계
- **Core Developer**: TypeScript core 구현
- **Plugin Developer**: 플러그인 시스템 및 통합
- **QA Engineer**: Testing & validation
- **DevOps**: CI/CD, packaging, release

---

## 16. References

### 16.1 Source Code References

- **gemini-cli**: https://github.com/google-gemini/gemini-cli
  - esbuild 설정: `esbuild.config.js`
  - 패키지 구조: `packages/*/package.json`
  - CLI 설계: `packages/cli/src/main.ts`

- **Current my-help**: `/home/bwyoon/dotfiles/shell-common/functions/my_help.sh`
  - 라인 1-120: 초기화 및 등록 시스템
  - 라인 215-380: 카테고리 및 토픽 표시
  - 라인 509-637: 메인 로직

### 16.2 Documentation Templates

- REQ format: `/home/bwyoon/dotfiles/claude/skills/req-define/README.md`
- Phase template: `/home/bwyoon/dotfiles/claude/skills/req-phases/phase1-spec.md`

---

## 17. Next Steps

### Phase 0: Design Review & Learning (현재)

**✅ 완료**:
- 설계문서 작성: `req-CLI-MyCLI-1.md`
- 학습 가이드 작성: `req-CLI-MyCLI-1-learning-guide.md`
- 기술 결정: **ink 기반 즉시 개발** (chalk 스킵)

**📋 동료 리뷰 (예정)**:
- [ ] 아키텍처 검토 (dotfiles 내부 구조)
- [ ] 기술 스택 확인 (ink, TypeScript, yargs, vitest)
- [ ] 8주 타임라인 협의
- [ ] 학습 가이드 검토 및 피드백

**⏳ 설계 최종 승인 후**:
- [ ] 동료들의 최종 동의
- [ ] 개발 시작 일정 확정
- [ ] 학습 시작 (Week 1-2)

---

### Phase 1: Learning + Infrastructure Setup (Week 1-2)

**병렬 진행**:

#### 1️⃣ TypeScript/React 학습 (주 4-6시간)
```bash
# 학습 가이드 참고
📖 Week 1: TypeScript + React 기본
  Day 1-2: TypeScript 기본 문법
  Day 3-4: React 개념 (JSX, 컴포넌트, props)
  Day 5: ink "Hello World"

📖 Week 2: ink + yargs 심화
  Day 1-2: ink 컴포넌트 실험
  Day 3-4: yargs CLI 파싱
  Day 5: 첫 프로토타입 (HelpScreen)

# 리소스
- TypeScript Handbook: https://www.typescriptlang.org/docs/handbook/
- React Docs: https://react.dev/learn
- ink GitHub: https://github.com/vadimdemedes/ink
```

#### 2️⃣ 프로젝트 초기화 (병렬)
```bash
# 주 2: 프로젝트 구조 생성
cd /home/bwyoon/dotfiles

mkdir -p packages/my-cli/{packages/{core,cli},scripts}
cd packages/my-cli

# package.json 설정
npm init -y
npm init -y -w packages/core
npm init -y -w packages/cli

# 의존성 설치
npm install react ink yargs
npm install -D typescript tsx vitest eslint prettier @types/react @types/node

# TypeScript 설정
npx tsc --init

# 개발 스크립트 설정
# "dev": "tsx watch packages/cli/src/index.ts"
# "test": "vitest"
```

**주간 체크리스트**:
- [ ] TypeScript 기본 숙달
- [ ] React 컴포넌트 개념 이해
- [ ] ink "Hello World" 동작
- [ ] 프로젝트 구조 완성
- [ ] npm run dev 동작 확인

---

### Phase 2: Help System Migration + Interactive TUI (Week 2-4)

**Week 2.5 부터 시작** (TypeScript 학습과 병렬 마무리):

```bash
# 1. Shell 데이터 추출
📊 /dotfiles/shell-common/functions/my_help.sh 분석
   → HELP_DESCRIPTIONS 추출
   → HELP_CATEGORIES 추출
   → HELP_CATEGORY_MEMBERS 추출

# 2. TypeScript data structure 정의
📝 packages/core/src/types/help.ts
   ```typescript
   interface HelpTopic { ... }
   interface HelpCategory { ... }
   interface HelpRegistry { ... }
   ```

# 3. Help Registry 구현
🔧 packages/core/src/help/registry.ts
   - 카테고리 관리
   - 토픽 등록/조회
   - 검색 기능

# 4. ink TUI 구현
🎨 packages/cli/src/components/
   ├── CategorySelector.tsx      # 카테고리 선택
   ├── TopicList.tsx             # 토픽 목록
   ├── TopicDetail.tsx           # 토픽 상세보기
   └── SearchInput.tsx            # 검색 (향후)

# 5. CLI 통합
🚀 packages/cli/src/index.ts
   - yargs 커맨드 연결
   - ink 렌더링
   - Non-interactive 모드 (--json, --text)
```

**주간 체크리스트**:
- [ ] Shell 데이터 100% 마이그레이션
- [ ] HelpRegistry 구현 완료
- [ ] 카테고리 선택 TUI 동작
- [ ] 토픽 상세보기 TUI 동작
- [ ] 기본 기능 테스트 통과

---

### Phase 3: Plugin System (Week 4-5)

```bash
# 1. Plugin Architecture 정의
📐 packages/core/src/types/plugin.ts
   interface CliPlugin { ... }
   interface CliCommand { ... }

# 2. Plugin Loader 구현
🔌 packages/core/src/plugin/loader.ts
   - 플러그인 동적 로드
   - Hot reload (개발 환경)

# 3. 기존 도움말을 플러그인화
📦 packages/plugins/
   ├── git-help/
   ├── docker-help/
   └── python-help/
   ... (각 도메인별 플러그인)

# 4. 플러그인 통합 테스트
✅ 여러 플러그인이 동시에 로드/실행되는지 확인
```

**주간 체크리스트**:
- [ ] Plugin interface 정의
- [ ] Plugin loader 구현
- [ ] 3개 이상 플러그인 생성
- [ ] 플러그인 hot reload 동작

---

### Phase 4: Testing & Documentation (Week 5-6)

```bash
# 1. Unit Tests (vitest)
🧪 packages/core/tests/
   ├── help/registry.test.ts
   ├── plugin/loader.test.ts
   └── cli/parser.test.ts

# 2. Integration Tests
🔗 integration-tests/
   ├── help-system.test.ts
   ├── plugin-loading.test.ts
   └── cli-commands.test.ts

# 3. Documentation
📚 packages/my-cli/
   ├── README.md                # 사용자 가이드
   ├── DEVELOPMENT.md           # 개발자 가이드
   └── docs/
       ├── PLUGIN_API.md        # 플러그인 API
       └── ARCHITECTURE.md      # 아키텍처

# 4. 커버리지 목표: 80%+
npm run test -- --coverage
```

**주간 체크리스트**:
- [ ] 테스트 커버리지 80%+
- [ ] 모든 공개 API 문서화
- [ ] 사용자 가이드 완성
- [ ] 개발자 가이드 완성
- [ ] README 작성

---

### Phase 5: Polish & Release (Week 6-7)

```bash
# 1. 성능 최적화
⚡ 메모리 사용량 모니터링
   빌드 크기 최적화
   렌더링 성능 개선

# 2. Error Handling 강화
🛡️ 모든 에러 경로에 사용자 친화적 메시지
   Graceful fallback (기존 my-help)
   디버그 모드 지원

# 3. CI/CD 설정
🔄 GitHub Actions
   ├─ Lint on push
   ├─ Tests on PR
   ├─ Build verification
   └─ Auto-publish (선택)

# 4. Release 준비
🚀 Version: 0.1.0
   Changelog 생성
   Git tag 설정
   배포 (npm, dotfiles)

# 5. 기존 my-help과의 호환성 검증
🔗 my-cli-bridge.sh 작성
   alias my-cli='...'
   fallback 동작 확인
```

**주간 체크리스트**:
- [ ] ESLint/Prettier 통과
- [ ] 성능 벤치마크 완료
- [ ] CI/CD 파이프라인 동작
- [ ] v0.1.0 릴리스 준비
- [ ] 기존 my-help과 호환성 검증

---

### 📅 최종 타임라인

```
Week 1-2: 학습 + 초기 구조 (병렬)
Week 2-4: Help 시스템 + TUI (core 개발)
Week 4-5: 플러그인 시스템 (확장성)
Week 5-6: 테스트 + 문서 (품질)
Week 6-7: 최적화 + 릴리스 (완성)

Week 8: 버퍼 (오버런 대비)
```

---

### 📚 관련 문서

| 문서 | 경로 | 목적 |
|------|------|------|
| **설계문서** | `docs/requirement/req-CLI-MyCLI-1.md` | 전체 구조 및 목표 |
| **학습 가이드** | `docs/requirement/req-CLI-MyCLI-1-learning-guide.md` | TypeScript/React/ink 학습 |
| **개발 가이드** | `packages/my-cli/DEVELOPMENT.md` | (작성 예정) |
| **사용자 가이드** | `packages/my-cli/README.md` | (작성 예정) |
| **플러그인 API** | `packages/core/docs/PLUGIN_API.md` | (작성 예정) |
| **아키텍처** | `packages/my-cli/docs/ARCHITECTURE.md` | (작성 예정) |

---

### 🎯 개발 시작 체크리스트

동료 리뷰 및 승인 후:

```bash
# 1단계: 학습 시작 (Day 1)
   📖 learning-guide.md 읽기
   💻 TypeScript 기본 학습 시작

# 2단계: 환경 구성 (Week 1 중반)
   📁 프로젝트 디렉토리 생성
   📦 npm workspace 초기화
   🔧 개발 환경 설정

# 3단계: 첫 프로토타입 (Week 2)
   ✏️ HelpScreen 컴포넌트
   🎨 ink UI 기본 구현
   ✅ npm run dev 동작 확인

# 4단계: 본개발 시작 (Week 3)
   🏗️ Help registry 구현
   🗂️ 데이터 마이그레이션
   🎯 기본 기능 완성

# 5단계: 지속적 개발 (Week 3-7)
   🔧 플러그인, 테스트, 문서화
   📈 버전별 완성도 제고
   🚀 v0.1.0 릴리스
```

**개발 시작 명령어** (Week 1 학습 완료 후):
```bash
# 학습 가이드 완독 후 시작
cd /home/bwyoon/dotfiles
mkdir -p packages/my-cli && cd packages/my-cli

# 초기 구조 생성 스크립트 (추후 제공)
> "초기 구조 생성 스크립트"

# 또는 수동으로
npm init -y
npm init -y -w packages/{core,cli}
npm install react ink yargs
npm install -D typescript tsx vitest
```

---

## Appendix: Shell to TypeScript Migration Map

```typescript
// shell-common/functions/my_help.sh → my-cli/packages/core

// my_help.sh: Line 33-40 (Initialize arrays)
// → TypeScript: HelpRegistry.ts
//   HELP_DESCRIPTIONS → class HelpRegistry { descriptions: Map<...> }
//   HELP_CATEGORIES → class HelpRegistry { categories: Map<...> }

// my_help.sh: Line 73-84 (Register help)
// → TypeScript: HelpRegistry.ts
//   _register_help() → registry.register()
//   get_help_description() → registry.getDescription()

// my_help.sh: Line 90-105 (_get_help_functions)
// → TypeScript: PluginLoader.ts
//   _get_help_functions() → pluginLoader.loadTopics()

// my_help.sh: Line 297-380 (Show categories/topics)
// → TypeScript: HelpUIFormatter.ts
//   _my_help_show_categories() → formatter.formatCategories()
//   _my_help_show_category() → formatter.formatCategory()

// my_help.sh: Line 509-637 (Main logic)
// → TypeScript: HelpCommand.ts
//   my_help_impl() → HelpCommand.execute()
```

---

**Document Version**: 1.0
**Last Updated**: 2026-02-19
**Status**: Ready for Review
