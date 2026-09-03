# REQ-abc-C: my-cli (Comprehensive, Consolidated Design)

**종합 개발 설계 문서** | TypeScript/Node.js | 피드백 반영 최종 검증

| Field | Value |
|-------|-------|
| **Document ID** | req-abc-C (Comprehensive Consolidated) |
| **Title** | my-cli - Modern Help & Utility CLI System |
| **Type** | Technical Design Specification |
| **Status** | Ready for Implementation (Feedback Applied) |
| **Target Language** | TypeScript/Node.js 20+ |
| **Reference Architecture** | gemini-cli + my-help.sh |
| **Integration Sources** | req-abc-CX + req-abc-G + req-CLI-MyCLI-1 |

**피드백 반영 현황:**
- [x] High Priority: alias 전환 v0.2+로 이동, shell 호출 정확성 보강, 정적 파서 검증 명시
- [x] Medium Priority: XDG 설정 경로, pager 폴백, 플러그인 범위 제한
- [x] Low Priority: 절대 경로 → 상대 경로, 이모지 제거, 문서 표기 정합성
- [x] 문서: "my-help 무변경" 원칙 명시, 호환성 원칙 추가

---

## Executive Summary

`my-cli`는 기존 shell 기반 도움말 시스템(`my-help`)을 **현대적 TypeScript/Node.js** 구조로 진화시킨 다목적 CLI 도구입니다.

**핵심 목표:**
- ✅ 기존 `my-help` 기능 100% 보존 및 확장
- ✅ Interactive TUI + Non-interactive JSON 출력 모두 지원
- ✅ Shell Completion (bash/zsh) 제공
- ✅ 다중 소스 어댑터 (Shell functions, Manpage, Markdown)
- ✅ 보안-우선 아키텍처 (injection 방지, 입력 검증)
- ✅ Plugin 확장 시스템으로 장기 유지보수성 확보

**차별점:**
1. **이중 레지스트리 로딩** (정적 파서 우선 + 실행 기반 옵션)
2. **격리된 보안 설계** (화이트리스트 검증, spawn 사용 의무)
3. **계층적 아키텍처** (Core/CLI/Plugin 명확한 경계)

**중요: 호환성 원칙**
- v0.1에서는 기존 `my_help.sh` 함수 코드 **완전 무변경**
- `my-cli`는 **별도 진입점**으로 도입 (alias 전환은 v0.2+)
- 기존 사용자는 계속 `my-help` 사용 가능
- 신규 사용자는 `my-cli` 권장

---

## 1. 프로젝트 개요

### 1.1 배경

현재 dotfiles의 help 시스템:

```bash
# Shell script 기반 (my_help.sh)
my-help              # 카테고리 표시
my-help ai           # AI 카테고리 상세
my-help git          # git 토픽 상세
```

한계:
- 탐색 경험 (discoverability) 제한
- 자동 완성 없음
- JSON/structured 출력 불가
- 동적 확장 어려움 (새로운 소스 추가 시 shell script 수정 필요)

### 1.2 목표

```
my-cli help          # TUI로 카테고리/토픽 탐색 (모드: interactive)
my-cli list topics   # JSON으로 토픽 목록 출력 (모드: non-interactive)
my-cli show git      # git 상세 help (pager로 표시)
my-cli --version     # 버전 출력
my-cli completion    # bash/zsh completion 생성
```

### 1.3 성공 지표

| 지표 | 목표값 |
|------|--------|
| 기존 기능 유지율 | 100% |
| Interactive 첫 화면 | < 500ms (Node.js cold start 포함) |
| Non-interactive 응답 | < 300ms |
| 번들 크기 | < 15MB |
| 테스트 커버리지 | ≥ 85% |

---

## 2. 아키텍처 설계

### 2.1 계층 구조

```
┌────────────────────────────────────────────────────────┐
│  Layer 1: Entry & Routing (packages/cli)               │
│  index.ts (shebang) → main.ts (mode router)           │
│  ├─ Interactive? → tui/App.tsx (Ink)                 │
│  └─ Non-interactive? → commands/ (yargs)             │
├────────────────────────────────────────────────────────┤
│  Layer 2: Domain & Orchestration (packages/core)       │
│  ├─ Registry Loaders                                  │
│  │  ├─ parse_static.ts (기본: 코드 실행 없음)          │
│  │  └─ load_by_shell.ts (옵션: --shell-loader)       │
│  ├─ Input Validation                                  │
│  │  └─ sanitize.ts (화이트리스트 검증, injection 방지) │
│  ├─ Configuration                                     │
│  │  ├─ config/loader.ts (~/.my-cli/config.json)     │
│  │  └─ dotfiles_root.ts (자동 경로 탐지)              │
│  └─ Types & Interfaces                                │
│     └─ types.ts                                       │
├────────────────────────────────────────────────────────┤
│  Layer 3: Source Adapters (packages/plugins or        │
│           packages/core/adapters)                      │
│  ├─ ShellFunctionAdapter   (my-help <topic> 호출)    │
│  ├─ ManpageAdapter         (man <topic> 파싱)        │
│  └─ MarkdownAdapter        (.md 파일 렌더링)         │
└────────────────────────────────────────────────────────┘
```

### 2.2 디렉터리 구조 (최종)

```
my-cli/
├── packages/
│   ├── core/                          # 순수 도메인 로직
│   │   ├── src/
│   │   │   ├── registry/
│   │   │   │   ├── parse_static.ts       # 정적 파서 (기본)
│   │   │   │   ├── load_by_shell.ts      # 실행 기반 로더 (옵션)
│   │   │   │   ├── types.ts              # HelpRegistry, HelpTopic 타입
│   │   │   │   └── Registry.ts           # 통합 레지스트리 클래스
│   │   │   ├── adapters/
│   │   │   │   ├── ShellFunctionAdapter.ts
│   │   │   │   ├── ManpageAdapter.ts
│   │   │   │   └── MarkdownAdapter.ts
│   │   │   ├── config/
│   │   │   │   └── ConfigLoader.ts
│   │   │   ├── sanitize.ts               # 입력 검증, injection 방지
│   │   │   ├── dotfiles_root.ts          # 경로 자동 탐지
│   │   │   └── errors.ts                 # 커스텀 에러 클래스
│   │   ├── tests/
│   │   │   ├── registry.test.ts
│   │   │   ├── parse_static.test.ts
│   │   │   ├── sanitize.test.ts
│   │   │   └── adapters.test.ts
│   │   └── package.json
│   │
│   ├── cli/                          # UI 및 CLI 진입점
│   │   ├── src/
│   │   │   ├── index.ts                 # Entry (shebang: #!/usr/bin/env node)
│   │   │   ├── main.ts                  # Mode routing (interactive vs commands)
│   │   │   ├── commands/                # yargs 커맨드 핸들러
│   │   │   │   ├── list.ts              # my-cli list categories/topics
│   │   │   │   ├── show.ts              # my-cli show <topic>
│   │   │   │   ├── config.ts            # my-cli config ...
│   │   │   │   ├── completion.ts        # my-cli completion bash/zsh
│   │   │   │   └── version.ts           # my-cli --version
│   │   │   ├── tui/                     # Ink(React) 기반 TUI
│   │   │   │   ├── App.tsx              # 메인 TUI 앱
│   │   │   │   ├── screens/
│   │   │   │   │   ├── Home.tsx         # 카테고리/토픽 탐색
│   │   │   │   │   └── Topic.tsx        # 토픽 상세 보기 (pager)
│   │   │   │   └── components/
│   │   │   │       ├── CategoryList.tsx
│   │   │   │       ├── TopicSearch.tsx
│   │   │   │       └── Pager.tsx        # less -R 스타일 페이져
│   │   │   └── formatter.ts             # 출력 포맷팅 (JSON, text)
│   │   ├── tests/
│   │   │   ├── commands.test.ts
│   │   │   └── e2e.test.ts              # my-help 호출 검증
│   │   └── package.json
│   │
│   └── plugins/                      # 선택 확장 플러그인
│       ├── git-help/
│       ├── docker-help/
│       └── python-help/
│
├── scripts/
│   ├── build.ts                        # TypeScript 컴파일
│   ├── bundle.ts                       # esbuild 번들링
│   └── generate-docs.ts                # API 문서 생성
│
├── .precommit/                         # Pre-commit hook 설정 (lint, test)
├── package.json (root workspace)
├── tsconfig.json
├── esbuild.config.js
├── vitest.config.ts
└── README.md
```

**핵심 분리:**
- `packages/core/`: 셸 호출 없는 순수 도메인 로직 (테스트 용이)
- `packages/cli/`: UI + 진입점 (Node.js 환경 의존)
- `packages/cli/tui/`: Ink TUI만 담당
- `packages/core/sanitize.ts`: **공유** - 모든 입력을 검증

### 2.3 기술 스택

```json
{
  "runtime": {
    "node": ">=20.0.0 LTS",
    "npm": "workspace monorepo"
  },
  "core_dependencies": {
    "typescript": "^5.3.x",
    "yargs": "^17.7.x",
    "ink": "^4.4.x",
    "chalk": "^5.3.x"
  },
  "dev_dependencies": {
    "vitest": "^1.0.x",
    "esbuild": "^0.19.x",
    "tsx": "^4.0.x",
    "eslint": "^8.50.x",
    "prettier": "^3.0.x"
  }
}
```

---

## 3. 핵심 요구사항

### 3.1 기능 요구사항 (FUN)

**FUN-001: Interactive 모드 (기본)**
- 첫 화면: 카테고리 목록 + 빠른 검색 입력
- 네비게이션: 상/하 화살표, Enter 선택, Esc/q 종료
- 토픽 상세: pager로 `my-help <topic>` 결과 표시
- 성능: 첫 화면 렌더링 < 500ms

**FUN-002: Non-interactive 모드 (JSON/Text)**
```bash
my-cli list categories --format json
my-cli list topics --search git
my-cli show git --raw                 # my-help git 결과 출력
my-cli help ai --format json
```

**FUN-003: 입력 검증 (Security)**
- 토픽 이름 화이트리스트: `[A-Za-z0-9_-]+`
- 레지스트리 존재 확인 후에만 실행
- Shell injection 방지 (spawn + array args)

**FUN-004: 레지스트리 로딩 (이중 전략)**
- 모드 A (기본): 정적 파서 (parse_static.ts)
  - `my_help.sh`에서 `HELP_CATEGORIES[...]`, `HELP_DESCRIPTIONS[...]` 파싱
  - 보안 위험 없음, cold start 빠름
- 모드 B (옵션): 실행 기반 로더 (--shell-loader 플래그)
  - `bash -lc 'source my_help.sh; declare -p HELP_CATEGORIES ...'`
  - 동적 생성 항목 포착, 정확도 ↑
  - 환경 의존성 고려

**FUN-005: Shell Completion**
```bash
my-cli completion bash >> ~/.bashrc
my-cli completion zsh >> ~/.zshrc
```

**FUN-006: 다중 소스 어댑터 (확장 포인트)**
- ShellFunctionAdapter: `my-help` 호출
- ManpageAdapter: `man` 명령 파싱
- MarkdownAdapter: dotfiles 내 `.md` 파일
- 플러그인으로 추가 가능

### 3.2 데이터 모델

```typescript
// packages/core/src/registry/types.ts

interface HelpTopic {
  id: string;                    // 'git', 'docker', etc.
  name: string;                  // 'Git', 'Docker', etc.
  category: string;              // 'development', 'devops', etc.
  description: string;           // '[Development] Git version control...'
  examples?: string[];           // 사용 예시
  aliases?: string[];            // 다른 이름
  source?: 'shell' | 'manpage' | 'markdown';
}

interface HelpCategory {
  key: string;                   // 'development'
  label: string;                 // 'Development'
  description: string;
  topicCount: number;
  topics: HelpTopic[];
}

interface HelpRegistry {
  categories: Map<string, HelpCategory>;
  topics: Map<string, HelpTopic>;

  // 메서드
  load(mode: 'static' | 'shell'): Promise<void>;
  getCategory(key: string): HelpCategory | undefined;
  getTopic(id: string): HelpTopic | undefined;
  search(query: string): HelpTopic[];
  toJSON(): { categories: {...}, topics: {...} };
}
```

---

## 4. 보안 설계

### 4.1 입력 검증 (packages/core/src/sanitize.ts)

```typescript
const SAFE_TOPIC_PATTERN = /^[A-Za-z0-9_-]+$/;
const MAX_TOPIC_LENGTH = 50;

export function validateTopic(
  topic: string,
  registry: HelpRegistry
): void {
  // 길이 체크
  if (topic.length === 0 || topic.length > MAX_TOPIC_LENGTH) {
    throw new ValidationError(
      `Topic must be 1-${MAX_TOPIC_LENGTH} characters`
    );
  }

  // 화이트리스트 패턴 체크
  if (!SAFE_TOPIC_PATTERN.test(topic)) {
    throw new ValidationError(
      `Topic contains invalid characters. Only a-z, A-Z, 0-9, _, - allowed`
    );
  }

  // 레지스트리 존재 확인
  if (!registry.hasTopic(topic)) {
    throw new NotFoundError(
      `Topic '${topic}' not found. See: my-cli list topics`
    );
  }
}
```

### 4.2 Shell 호출 보안

```typescript
// ❌ 위험 1: 문자열 보간
const command = `my-help ${userInput}`;
exec(command);  // shell injection 위험

// ❌ 위험 2: 잘못된 execFile 사용
// bash -lc는 "하나의 command string"을 받는데, 배열로 전달하면 작동 안함
execFile('bash', ['-lc', 'my-help', topic], {...});

// ✅ 안전: 실제 함수 호출 (alias 확장 보장)
const { execFile } = require('child_process');
const myHelpScript = '/path/to/my_help.sh';  // my-help.sh 경로

execFile('bash', [
  '--noprofile',   // 사용자 .bashrc 영향 최소화
  '--norc',
  '-c',
  `source '${myHelpScript}'; my_help_impl "$1"`,
  'bash',          // argv[0] (프로그램명)
  topic            // $1로 전달
], {
  stdio: ['pipe', 'pipe', 'pipe'],
  timeout: 10000,
  env: { ...process.env, MY_HELP_SKIP_TUI: '1' }
}, (error, stdout, stderr) => {
  if (error) {
    logger.error(`Shell execution failed: ${error.message}`);
    throw new InternalError('Failed to fetch help content');
  }
  // ... stdout 처리
});

// zsh 호환성 (선택사항)
if (shell === 'zsh') {
  execFile('zsh', [
    '-f',              // 사용자 .zshrc 영향 최소화
    '-c',
    `source '${myHelpScript}'; my_help_impl "$1"`,
    'zsh',
    topic
  ], {...});
}
```

**규칙 (확정):**
1. 모든 토픽 이름은 `validateTopic()`으로 검증 후 사용
2. `exec()` 금지, `execFile()` 또는 `spawn()` 사용 필수
3. **Argument는 배열로 전달** (쉘 인터프리터를 우회하지 않기 위해 command string을 `-c` 뒤에 전달)
4. **실제 함수명 호출** (alias 대신 `my_help_impl` 함수 직접 호출로 확장 보장)
5. **RC 파일 격리** (`--noprofile --norc` 또는 `zsh -f`로 사용자 설정 영향 최소화)
6. **타임아웃 설정** (10초, 무한 대기 방지)
7. **환경 변수 격리** (필요시 PATH 제한)

### 4.3 Pager 전략 (less -R + 폴백)

```typescript
// pager 사용 (less -R)
// less: 색상 지원(-R), 구성 변경 불가능(-i 없음), 라인 번호 지원(-N)
// PAGER 환경 변수 존중

const pagerCommand = process.env.PAGER || 'less -R';

// 폴백 전략 (less 미설치 시)
function showWithPager(content: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const pager = spawn(pagerCommand, [], { stdio: ['pipe', 'inherit', 'inherit'] });

    pager.stdin.write(content);
    pager.stdin.end();

    pager.on('error', (err) => {
      // less 미설치: plain text 출력으로 폴백
      if (err.code === 'ENOENT') {
        console.log(content);  // 색상 제거된 순수 텍스트
        resolve();
      } else {
        reject(err);
      }
    });

    pager.on('close', resolve);
  });
}
```

**Pager 우선순위:**
1. PAGER 환경 변수 (사용자 설정 존중)
2. `less -R` (기본값, 색상 지원)
3. 평문 출력 (less 미설치 시 폴백)

### 4.3 에러 처리

```typescript
enum ExitCode {
  Success = 0,
  InvalidInput = 1,      // 토픽 없음, 형식 오류
  UsageError = 2,        // 인자 파싱 실패
  InternalError = 10,    // 파서 오류, my-help 실행 오류
  SecurityError = 11,    // injection 시도
}
```

---

## 5. 레지스트리 로딩 전략 (상세)

### 5.1 모드 A: 정적 파서 (기본)

**입력:** `dotfiles root (shell-common/functions/my_help.sh`

**파싱 대상:**
```bash
# 라인 33-40: 카테고리 초기화
HELP_CATEGORIES[ai]="AI/LLM assistants (Claude, Gemini, Codex, etc.)"
HELP_CATEGORIES[development]="Development tools (Git, Python, ...)"
# ... 총 8개 카테고리

# 라인 45-60: 카테고리별 멤버
HELP_CATEGORY_MEMBERS[development]="git uv py nvm npm pp cli ux du psql mytool"
HELP_CATEGORY_MEMBERS[devops]="docker dproxy sys proxy mount mysql gpu"
# ... 총 8개 그룹

# 라인 73-84: 토픽 설명
HELP_DESCRIPTIONS["uv_help"]="[Development] UV packages and environments"
HELP_DESCRIPTIONS["git_help"]="[Development] Git version control shortcuts"
# ... 총 40+ 토픽
```

**구현 (parse_static.ts):**
```typescript
export async function parseStaticRegistry(
  filePath: string
): Promise<HelpRegistry> {
  const content = readFileSync(filePath, 'utf-8');

  // 정규식으로 할당문 추출
  const categoryPattern = /HELP_CATEGORIES\[(\w+)\]="([^"]+)"/g;
  const descPattern = /HELP_DESCRIPTIONS\[(\w+)\]="([^"]+)"/g;
  const memberPattern = /HELP_CATEGORY_MEMBERS\[(\w+)\]="([^"]+)"/g;

  // 각 배열 구성
  const categories: Map<string, HelpCategory> = new Map();
  const topics: Map<string, HelpTopic> = new Map();

  // ... 파싱 로직

  return new HelpRegistry(categories, topics);
}
```

**장점:**
- ✅ 코드 실행 없음 (보안)
- ✅ Cold start 빠름 (200ms 이내)
- ✅ bash/zsh 의존성 없음

**제약 & 검증:**
- ❌ 동적 생성 항목 미포착 (현재 my_help.sh는 주로 정적 할당이지만, `${...:-...}` 패턴 등 특수 형태는 정규식으로 매칭 어려울 수 있음)
- **Phase 1 산출물**: 현재 my_help.sh의 **모든 패턴을 카바할 정규식 목록** 작성 및 검증 필요
  - HELP_CATEGORIES[key]="value"
  - HELP_DESCRIPTIONS[key]="value"
  - HELP_CATEGORY_MEMBERS[key]="space-separated-values"
  - 기본값 패턴: ${HELP_DESCRIPTIONS[key]:-default}
- **우발 상황**: 정규식 검증 후에도 누락이 발견되면 `--shell-loader` 플래그로 보완 가능

### 5.2 모드 B: 실행 기반 로더 (옵션)

**호출:**
```bash
bash -lc 'source /path/to/my_help.sh; declare -p HELP_CATEGORIES HELP_DESCRIPTIONS HELP_CATEGORY_MEMBERS'
```

**구현 (load_by_shell.ts):**
```typescript
export async function loadByShell(
  filePath: string,
  shell: 'bash' | 'zsh' = 'bash'
): Promise<HelpRegistry> {
  const { execFile } = require('child_process');

  return new Promise((resolve, reject) => {
    const sourceCmd = `source '${filePath}'; declare -p HELP_CATEGORIES HELP_DESCRIPTIONS HELP_CATEGORY_MEMBERS`;

    execFile(shell, ['-lc', sourceCmd], {
      timeout: 5000,
      env: { ...process.env, MY_HELP_MODE: 'dump' }
    }, (error, stdout) => {
      if (error) {
        reject(new Error(`Shell loading failed: ${error.message}`));
      }
      // stdout 파싱 → HelpRegistry 구성
      resolve(parseShellOutput(stdout));
    });
  });
}
```

**사용:**
```bash
my-cli help --shell-loader bash    # bash 모드 강제
my-cli help --shell-loader zsh     # zsh 모드 강제
```

**장점:**
- ✅ 동적 생성 항목 포함
- ✅ 최신 환경 반영 (사용자 zshrc 변경 사항 등)

**제약:**
- ❌ 셸 실행 필요 (보안 고려 필요, 따라서 옵션)
- ❌ Cold start 증가 (500ms+)
- ❌ 환경 의존성

**결정:** 모드 A (정적)를 기본값으로, `--shell-loader` 플래그로 명시적 선택 가능

---

## 6. CLI 인터페이스

### 6.1 대화형 모드 (기본)

```bash
$ my-cli
# ┌─────────────────────────────────────┐
# │ 📚 my-cli Help Browser              │
# ├─────────────────────────────────────┤
# │ Categories:                         │
# │  [▶] AI/LLM (5 topics)             │
# │  [ ] CLI Utilities (8 topics)      │
# │  [ ] Development (12 topics)       │
# │  [ ] DevOps (7 topics)             │
# │  [ ] Documentation (5 topics)      │
# │                                     │
# │ Search: _______________            │
# │ Help: ↑↓ Enter | / Search | q Quit │
# └─────────────────────────────────────┘
```

**키보드 조작:**
- `↑↓`: 항목 이동
- `→`: 카테고리 확장 / 토픽 선택
- `Enter`: 선택된 항목 열기
- `/`: 검색 모드 진입
- `Esc` 또는 `q`: 종료

### 6.2 비대화형 모드 (JSON/Text)

```bash
# 카테고리 목록
$ my-cli list categories --format json
{
  "categories": [
    {
      "key": "ai",
      "label": "AI/LLM",
      "description": "AI/LLM assistants...",
      "topicCount": 5
    },
    ...
  ]
}

# 토픽 목록 (검색 포함)
$ my-cli list topics --search git --format json
{
  "topics": [
    {
      "id": "git",
      "name": "Git",
      "category": "development",
      "description": "[Development] Git version control..."
    }
  ]
}

# 토픽 상세 (원문 출력)
$ my-cli show git --raw
# my-help git 의 결과가 stdout에 출력됨

# 토픽 상세 (JSON)
$ my-cli show git --format json
{
  "topic": {
    "id": "git",
    "name": "Git",
    "description": "...",
    "details": "... (my-help git 결과)..."
  }
}
```

### 6.3 설정 (Configuration Priority)

**설정 파일 우선순위 (XDG 표준 준수):**

```
1. MY_CLI_CONFIG=/custom/path/config.json    (환경 변수)
2. ~/.config/my-cli/config.json               (XDG Base Directory)
3. ~/.my-cli/config.json                      (레거시 경로, 이전 호환성)
4. <dotfiles>/shell-common/config/my-cli.json (팀 공유 설정, 선택사항)
```

**용도별 설정 분리:**
- 개인 설정: ~/.config/my-cli/config.json (사용자별 테마, 단축키)
- 팀 공유 설정: dotfiles 내부 (권장 토픽 순서, 정책)

### 6.4 완성

```bash
# 설정
$ my-cli config show               # 현재 설정 표시
$ my-cli config set theme dark     # 테마 변경
$ my-cli config reset              # 기본값으로 복원

# 완성 (Shell integration - dotfiles 방식)
# 방법 1: 자동 생성 (설치 스크립트에서)
$ my-cli completion bash > shell-common/completions/my-cli.bash
$ my-cli completion zsh > shell-common/completions/_my-cli

# 방법 2: dotfiles 통합 (bash/main.bash 또는 zsh/main.zsh에서)
# ~/.bashrc 또는 ~/.zshrc는 직접 수정하지 않음 (dotfiles 규칙)
# 대신 dotfiles의 setup.sh에서 symlink 또는 source 설정

# 검증
$ source shell-common/completions/my-cli.bash  # bash completion 로드 확인
$ source shell-common/completions/_my-cli      # zsh completion 로드 확인

# 버전
$ my-cli --version
my-cli v0.1.0
```

**주의 (dotfiles 통합 규칙):**
- ~/.bashrc, ~/.zshrc 직접 수정 금지
- completion 스크립트는 `shell-common/completions/` 또는 `shell-common/functions/` 하위에 저장
- `bash/main.bash` 또는 `zsh/main.zsh`에서 `source` 방식으로 로드
- dotfiles setup.sh에서 symlink 관리

### 6.4 종료 코드

```
Exit Code  의미                        사용 사례
─────────────────────────────────────────────────
0          성공                        정상 실행
1          입력 오류                   토픽 없음, 형식 오류
2          사용법 오류                 인자 파싱 실패 (--invalid-flag)
10         내부 오류                   파서 오류, my-help 실행 실패
11         보안 오류                   injection 시도 차단
```

---

## 7. CL 단위 세부 개발 계획

### 🎯 개발 프로세스 (각 CL마다)

```
개발 (Dev)
    ↓
자체 검증 (Self Test)
    ↓
커밋 (git commit)
    ↓
동료 코드 리뷰 (Code Review)
    ↓
병합 (Merge)
```

**CL 크기 가이드:**
- 마이크로 CL: 50-200줄 (매우 추천)
- 작은 CL: 200-400줄 (추천)
- 중간 CL: 400-800줄 (주의)
- 큰 CL: 800줄+ (리뷰 피로도 높음, 분해 권고)

---

### 📊 전체 CL 개요 (18개 CL, 총 11-12주)

| Phase | CL ID | 주제 | 기간 | 상태 |
|-------|-------|------|------|------|
| **0** | - | 설계 리뷰 | 1주 | - |
| **1** | CL-1.1 | monorepo + TypeScript | 1일 | 📝 |
| | CL-1.2 | 에러 클래스 & 종료 코드 | 1일 | 📝 |
| | CL-1.3 | 입력 검증 모듈 | 1일 | 📝 |
| | CL-1.4 | 설정 로더 | 1일 | 📝 |
| | CL-1.5 | 테스트 인프라 | 1일 | 📝 |
| **2** | CL-2.1 | Registry 타입 & 기본 메서드 | 1일 | 📝 |
| | CL-2.2 | 정적 파서 (my_help.sh 파싱) | 2일 | 📝 |
| | CL-2.3 | 실행 기반 로더 (bash/zsh) | 2일 | 📝 |
| | CL-2.4 | 통합 로직 & 모드 선택 | 1일 | 📝 |
| **3** | CL-3.1 | yargs 라우팅 | 1일 | 📝 |
| | CL-3.2 | list 커맨드 | 1일 | 📝 |
| | CL-3.3 | show 커맨드 + pager | 1일 | 📝 |
| **4** | CL-4.1 | Ink Home 화면 | 2일 | 📝 |
| | CL-4.2 | TopicList + 검색 | 2일 | 📝 |
| | CL-4.3 | Detail + Pager 통합 | 2일 | 📝 |
| **5** | CL-5.1 | ShellFunctionAdapter | 1일 | 📝 |
| | CL-5.2 | Completion 스크립트 | 1일 | 📝 |
| **6** | CL-6.1 | E2E & 성능 테스트 | 1일 | 📝 |
| | CL-6.2 | esbuild 번들링 | 1일 | 📝 |
| | CL-6.3 | 문서화 & CI/CD & 릴리스 | 2일 | 📝 |

**범례**: 📝 = 계획 단계

---

## 8. 구현 단계별 계획 (CL 단위 세분화)

### Phase 0: 설계 및 리뷰 (1주)

- [ ] 이 문서 팀 리뷰
- [ ] 기술 선택 확정 (TUI 라이브러리, pager 방식)
- [ ] 오픈 이슈 결정 (아래 Section 10 참고)

### Phase 1: 기반 구조 (2주, 5개 CL)

#### CL-1.1: 프로젝트 초기화 (monorepo + TypeScript)
**목표:** Node.js monorepo 기본 구조 및 TypeScript 설정 완료

**산출물:**
```
packages/my-cli/
├── packages/
│   ├── core/
│   │   ├── src/
│   │   ├── tests/
│   │   └── package.json
│   └── cli/
│       ├── src/
│       ├── tests/
│       └── package.json
├── package.json (root)
├── tsconfig.json
├── tsconfig.build.json
└── .gitignore
```

**개발 체크리스트:**
- [ ] Root package.json 생성 (workspaces 정의)
- [ ] packages/core, packages/cli 디렉토리 생성
- [ ] 각 패키지의 package.json 생성 (entry point, scripts)
- [ ] tsconfig.json 설정 (strict: true)
- [ ] Node.js 버전 명시 (engines: >=20.0.0)
- [ ] .gitignore 설정 (node_modules, dist, .env)

**자체 검증:**
```bash
cd packages/my-cli       # 프로젝트 디렉토리로 이동
npm install              # 의존성 설치 성공
npm run typecheck        # TypeScript 컴파일 성공
ls packages/*/src/       # 디렉토리 구조 확인
```

**커밋 메시지 템플릿:**
```
feat: Initialize monorepo with TypeScript configuration

- Create root package.json with workspaces
- Setup packages/core and packages/cli
- Configure TypeScript strict mode
- Add Node.js 20+ engine requirement
```

**코드 리뷰 체크리스트:**
- [ ] package.json의 workspaces 정의가 정확한가?
- [ ] tsconfig.json의 strict 모드가 활성화되어 있는가?
- [ ] Node.js 최소 버전이 명시되어 있는가?
- [ ] 불필요한 의존성이 없는가?
- [ ] gitignore가 적절하게 설정되어 있는가?

---

#### CL-1.2: 에러 클래스 및 종료 코드 정의
**목표:** 구조화된 에러 처리와 일관된 종료 코드 정의

**산출물:**
```typescript
// packages/core/src/errors.ts
class ValidationError extends Error { ... }
class NotFoundError extends Error { ... }
class InternalError extends Error { ... }
class SecurityError extends Error { ... }

// packages/core/src/exit-codes.ts
enum ExitCode { Success = 0, InvalidInput = 1, ... }
```

**개발 체크리스트:**
- [ ] packages/core/src/errors.ts 생성
- [ ] 4개 에러 클래스 구현 (ValidationError, NotFoundError, InternalError, SecurityError)
- [ ] 각 에러에 타입 안전성 추가 (generic)
- [ ] packages/core/src/exit-codes.ts 생성
- [ ] 5개 종료 코드 정의 (Success, InvalidInput, UsageError, InternalError, SecurityError)
- [ ] 에러 ↔ 종료 코드 매핑 함수

**자체 검증:**
```bash
cd packages/my-cli       # 프로젝트 디렉토리로 이동
npm run typecheck        # 타입 검증
npm run test -- errors.test.ts  # 단위 테스트 통과
```

**테스트 (errors.test.ts):**
```typescript
describe('ValidationError', () => {
  it('should have correct error type', () => {
    const err = new ValidationError('test');
    expect(err).toBeInstanceOf(Error);
    expect(err.message).toBe('test');
  });
});
```

**커밋 메시지:**
```
feat: Define error classes and exit codes

- Add ValidationError, NotFoundError, InternalError, SecurityError
- Define ExitCode enum with 5 exit codes
- Add error to exit code mapping function
- Include unit tests
```

**코드 리뷰 체크리스트:**
- [ ] 모든 에러 클래스가 Error를 상속하는가?
- [ ] 에러 메시지가 명확한가?
- [ ] 종료 코드 값이 shell 규칙을 따르는가?
- [ ] 테스트 커버리지가 충분한가?

---

#### CL-1.3: 입력 검증 모듈 (sanitize.ts)
**목표:** injection 방지 및 토픽 이름 화이트리스트 검증

**산출물:**
```typescript
// packages/core/src/sanitize.ts
function validateTopic(topic: string, registry: HelpRegistry): void
function sanitizeTopicName(topic: string): string
const SAFE_TOPIC_PATTERN = /^[A-Za-z0-9_-]+$/
```

**개발 체크리스트:**
- [ ] SAFE_TOPIC_PATTERN 정규식 정의
- [ ] validateTopic() 구현 (길이, 패턴, 레지스트리 존재 확인)
- [ ] sanitizeTopicName() 구현 (선택사항, 자동 정제)
- [ ] MAX_TOPIC_LENGTH 상수 정의 (50자)
- [ ] 에러 메시지 구체화 (어떤 문자가 안되는지 명시)
- [ ] 단위 테스트 작성 (정상, 비정상, edge case)

**자체 검증:**
```bash
cd packages/my-cli       # 프로젝트 디렉토리로 이동
npm run test -- sanitize.test.ts
# 테스트 통과 및 커버리지 90%+
```

**테스트 시나리오:**
```typescript
describe('validateTopic', () => {
  it('should accept valid topics', () => {
    expect(() => validateTopic('git', mockRegistry)).not.toThrow();
    expect(() => validateTopic('git-flow', mockRegistry)).not.toThrow();
    expect(() => validateTopic('py_3_12', mockRegistry)).not.toThrow();
  });

  it('should reject injection attempts', () => {
    expect(() => validateTopic('git; rm -rf /', mockRegistry)).toThrow(ValidationError);
    expect(() => validateTopic('git$(whoami)', mockRegistry)).toThrow(ValidationError);
  });

  it('should reject non-existent topics', () => {
    expect(() => validateTopic('nonexistent', mockRegistry)).toThrow(NotFoundError);
  });

  it('should reject oversized input', () => {
    const long = 'a'.repeat(51);
    expect(() => validateTopic(long, mockRegistry)).toThrow(ValidationError);
  });
});
```

**커밋 메시지:**
```
feat: Add input validation module (sanitize.ts)

- Implement validateTopic() with whitelist pattern
- Add length and registry existence checks
- Include injection attack prevention tests
- Achieve 100% test coverage
```

**코드 리뷰 체크리스트:**
- [ ] 정규식이 정확하고 완전한가?
- [ ] 길이 제한이 합리적인가?
- [ ] 에러 메시지가 보안 정보를 노출하지 않는가?
- [ ] 테스트가 주요 취약점을 커버하는가?
- [ ] 주석이 충분한가?

---

#### CL-1.4: 설정 로더 (dotfiles_root 탐지)
**목표:** dotfiles 경로 자동 탐지 및 설정 파일 로딩

**산출물:**
```typescript
// packages/core/src/config/dotfiles-root.ts
function findDotfilesRoot(): string
function loadConfig(): Config

// packages/core/src/config/types.ts
interface Config { theme?: string; ... }
```

**개발 체크리스트:**
- [ ] 환경 변수 우선순위 (MY_CLI_DOTFILES_ROOT)
- [ ] 부모 디렉토리 탐색 (.git 또는 특정 파일 기준)
- [ ] XDG 설정 경로 지원 (MY_CLI_CONFIG, ~/.config/my-cli/)
- [ ] 기본 설정값 정의
- [ ] 설정 파일 로딩 (JSON parse)
- [ ] 에러 처리 (경로 없음, 파싱 오류)

**자체 검증:**
```bash
cd packages/my-cli       # 프로젝트 디렉토리로 이동

# 현재 dotfiles 위치 탐지 확인
npx tsx -e "import {findDotfilesRoot} from './src/config'; console.log(findDotfilesRoot())"

# 설정 로딩 확인
npm run test -- config.test.ts
```

**테스트:**
```typescript
describe('findDotfilesRoot', () => {
  it('should find .git directory', () => {
    const root = findDotfilesRoot();
    expect(root).toContain('dotfiles');
    expect(fs.existsSync(root)).toBe(true);
  });
});
```

**커밋 메시지:**
```
feat: Add dotfiles root detection and config loader

- Implement findDotfilesRoot() with environment variable support
- Add XDG Base Directory support
- Implement loadConfig() with JSON parsing
- Include error handling for missing files
```

**코드 리뷰 체크리스트:**
- [ ] 환경 변수 우선순위가 명확한가?
- [ ] 경로 탐색 로직이 안전한가?
- [ ] XDG 표준을 준수하는가?
- [ ] symlink를 올바르게 처리하는가?
- [ ] 테스트가 여러 시나리오를 커버하는가?

---

#### CL-1.5: 테스트 인프라 설정 및 첫 통합 테스트
**목표:** vitest 기본 설정 완료 및 Phase 1 통합 검증

**산출물:**
```
├── vitest.config.ts
├── packages/core/tests/
│   ├── sanitize.test.ts
│   ├── errors.test.ts
│   └── config.test.ts
└── packages/cli/tests/
    └── setup.ts
```

**개발 체크리스트:**
- [ ] vitest.config.ts 생성 (globals: true, coverage 설정)
- [ ] test 스크립트 추가 (npm run test)
- [ ] coverage 리포트 설정 (coverage: { statements: 80%+ })
- [ ] CI/CD 준비 (GitHub Actions 기본 구조)
- [ ] 모든 이전 CL의 테스트 통합

**자체 검증:**
```bash
cd packages/my-cli       # 프로젝트 디렉토리로 이동

npm run test                           # 모든 테스트 통과
npm run test -- --coverage             # 커버리지 80%+
npm run typecheck                      # 타입 체크 통과
npm run lint                           # 린트 통과
```

**GitHub Actions 기본 (선택사항):**
```yaml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '20'
      - run: npm install
      - run: npm run lint
      - run: npm run typecheck
      - run: npm run test -- --coverage
```

**커밋 메시지:**
```
feat: Setup test infrastructure (vitest) and Phase 1 integration

- Configure vitest with coverage thresholds
- Add test scripts to package.json
- Integrate all Phase 1 tests
- Setup GitHub Actions CI (optional)
```

**코드 리뷰 체크리스트:**
- [ ] vitest 설정이 정확한가?
- [ ] 모든 test 파일이 포함되어 있는가?
- [ ] 커버리지 임계값이 합리적인가?
- [ ] CI 파이프라인이 정상 작동하는가?

---

**Phase 1 완료 기준:**
- [x] CL-1.1: monorepo + TypeScript 설정
- [x] CL-1.2: 에러 클래스 및 종료 코드
- [x] CL-1.3: 입력 검증 모듈
- [x] CL-1.4: 설정 로더
- [x] CL-1.5: 테스트 인프라

**Phase 1 산출물:**
- 프로젝트 뼈대 완성
- 테스트 인프라 구성
- 보안 검증 모듈 완성
- 설정 시스템 기초
- 모든 코드에 테스트 포함 (커버리지 80%+)


### Phase 2: 레지스트리 로딩 (2주, 4개 CL)

#### CL-2.1: 타입 정의 및 Registry 클래스 (기본 구조)
**목표:** HelpTopic, HelpCategory, HelpRegistry 타입 정의 및 기본 메서드 구현

**산출물:**
```typescript
// packages/core/src/registry/types.ts
interface HelpTopic { id, name, category, description, ... }
interface HelpCategory { key, label, description, topics, ... }

// packages/core/src/registry/Registry.ts
class HelpRegistry {
  load(mode: 'static' | 'shell'): Promise<void>
  getCategory(key: string): HelpCategory | undefined
  getTopic(id: string): HelpTopic | undefined
  search(query: string): HelpTopic[]
  toJSON(): { categories, topics }
}
```

**개발 체크리스트:**
- [ ] packages/core/src/registry/types.ts 생성
- [ ] HelpTopic 인터페이스 (id, name, category, description, examples, aliases, source)
- [ ] HelpCategory 인터페이스 (key, label, description, topicCount, topics)
- [ ] HelpRegistry 클래스 생성 (constructor, private 멤버)
- [ ] 기본 메서드 구현 (getCategory, getTopic, search)
- [ ] TypeScript strict mode 통과
- [ ] JSDoc 주석 추가

**자체 검증:**
```bash
npm run typecheck                    # 타입 검증 통과
npm run test -- registry.test.ts     # 기본 메서드 테스트
```

**테스트:**
```typescript
describe('HelpRegistry', () => {
  it('should get category by key', () => {
    const registry = new HelpRegistry();
    registry.addCategory({...});
    expect(registry.getCategory('ai')).toBeDefined();
  });

  it('should search topics', () => {
    const results = registry.search('git');
    expect(results.length).toBeGreaterThan(0);
  });
});
```

**커밋 메시지:**
```
feat: Define types and HelpRegistry base class

- Add HelpTopic and HelpCategory interfaces
- Implement HelpRegistry class with basic methods
- Include JSDoc comments for all public methods
- Add unit tests for type safety
```

**코드 리뷰 체크리스트:**
- [ ] 모든 필드가 타입 안전한가?
- [ ] optional 필드가 명확하게 표시되어 있는가?
- [ ] search() 메서드의 로직이 효율적인가?
- [ ] toJSON() 메서드가 모든 필드를 포함하는가?

---

#### CL-2.2: 정적 파서 구현 (parse_static.ts)
**목표:** my_help.sh에서 HELP_* 변수를 파싱하여 Registry 구성

**산출물:**
```typescript
// packages/core/src/registry/parse_static.ts
async function parseStaticRegistry(filePath: string): Promise<HelpRegistry>

// 파싱 대상
// HELP_CATEGORIES[key]="value"
// HELP_DESCRIPTIONS[key]="value"
// HELP_CATEGORY_MEMBERS[key]="space-separated-values"
```

**개발 체크리스트:**
- [ ] 파일 읽기 (readFileSync)
- [ ] 정규식 패턴 정의 (3개)
  - HELP_CATEGORIES
  - HELP_DESCRIPTIONS
  - HELP_CATEGORY_MEMBERS
- [ ] 각 패턴 추출 및 파싱
- [ ] HelpRegistry 구성 (categories, topics 매핑)
- [ ] 에러 처리 (파일 없음, 파싱 실패)
- [ ] 단위 테스트 (정상, 비정상, edge case)

**정규식 예제:**
```typescript
const categoryPattern = /HELP_CATEGORIES\[([a-z_]+)\]="([^"]+)"/g;
const descPattern = /HELP_DESCRIPTIONS\[([a-z_]+)\]="([^"]+)"/g;
const memberPattern = /HELP_CATEGORY_MEMBERS\[([a-z_]+)\]="([^"]+)"/g;
```

**자체 검증:**
```bash
# 실제 my_help.sh 파일에 대해 테스트
npm run test -- parse_static.test.ts --coverage
# 커버리지 100% 달성

# 파싱 결과 검증
npx tsx -e "import {parseStaticRegistry} from './src'; const r = await parseStaticRegistry('./../../shell-common/functions/my_help.sh'); console.log(r.getCategory('development'))"
```

**테스트 (snapshot 기반):**
```typescript
describe('parseStaticRegistry', () => {
  it('should parse HELP_CATEGORIES', async () => {
    const registry = await parseStaticRegistry(MY_HELP_PATH);
    expect(registry.getCategory('development')).toMatchSnapshot();
  });

  it('should parse HELP_DESCRIPTIONS', async () => {
    const topic = registry.getTopic('git');
    expect(topic?.description).toContain('Git');
  });

  it('should parse HELP_CATEGORY_MEMBERS', async () => {
    const category = registry.getCategory('development');
    expect(category?.topics.length).toBeGreaterThan(0);
  });

  it('should handle malformed input gracefully', async () => {
    expect(() => parseStaticRegistry('invalid.sh')).rejects.toThrow();
  });
});
```

**커밋 메시지:**
```
feat: Implement static registry parser (parse_static.ts)

- Add regex patterns for HELP_CATEGORIES, DESCRIPTIONS, MEMBERS
- Implement parseStaticRegistry() function
- Add error handling for missing/malformed files
- Include snapshot tests for validation
- Achieve 100% test coverage
```

**코드 리뷰 체크리스트:**
- [ ] 정규식이 현재 my_help.sh의 모든 패턴을 커버하는가?
- [ ] 파싱 로직이 효율적인가? (메모리, 성능)
- [ ] 에러 메시지가 명확한가?
- [ ] 스냅샷 테스트가 실제 파일과 일치하는가?
- [ ] 성능: cold start 200ms 이내인가?

---

#### CL-2.3: 실행 기반 로더 (load_by_shell.ts)
**목표:** bash/zsh 실행으로 동적 생성 항목 포함한 전체 레지스트리 로드 (선택사항)

**산출물:**
```typescript
// packages/core/src/registry/load_by_shell.ts
async function loadByShell(
  filePath: string,
  shell: 'bash' | 'zsh'
): Promise<HelpRegistry>
```

**개발 체크리스트:**
- [ ] execFile로 bash/zsh 호출
  - --noprofile --norc 옵션 (사용자 설정 최소화)
  - `declare -p HELP_* ` 명령
- [ ] 실행 출력 파싱 (declare -p 형식)
- [ ] 타임아웃 설정 (5초)
- [ ] 환경 변수 격리 (MY_HELP_MODE=dump)
- [ ] 에러 처리 (shell 미설치, timeout)
- [ ] 단위 테스트

**실행 명령:**
```bash
bash --noprofile --norc -c 'source my_help.sh; declare -p HELP_CATEGORIES HELP_DESCRIPTIONS HELP_CATEGORY_MEMBERS'
```

**자체 검증:**
```bash
npm run test -- load_by_shell.test.ts
# bash, zsh 모두에서 테스트 (환경 의존성)
```

**테스트:**
```typescript
describe('loadByShell', () => {
  it('should load from bash', async () => {
    const registry = await loadByShell(MY_HELP_PATH, 'bash');
    expect(registry.getCategory('ai')).toBeDefined();
  });

  it('should handle timeout gracefully', async () => {
    expect(() => loadByShell(SLOW_FILE, 'bash')).rejects.toThrow('timeout');
  });

  it('should isolate user environment', async () => {
    // .bashrc/.zshrc의 영향을 받지 않는지 확인
    const r1 = await loadByShell(MY_HELP_PATH, 'bash');
    const r2 = await loadByShell(MY_HELP_PATH, 'bash');
    expect(r1.toJSON()).toEqual(r2.toJSON());
  });
});
```

**커밋 메시지:**
```
feat: Implement shell-based registry loader (load_by_shell.ts)

- Add execFile-based loading for bash and zsh
- Implement environment isolation (--noprofile --norc)
- Add 5-second timeout and error handling
- Include tests for both bash and zsh
```

**코드 리뷰 체크리스트:**
- [ ] shell 호출이 안전한가? (execFile 사용, array args)
- [ ] 타임아웃이 합리적인가?
- [ ] 환경 변수 격리가 충분한가?
- [ ] 에러 메시지가 유용한가?
- [ ] bash와 zsh 모두에서 테스트했는가?

---

#### CL-2.4: Registry 통합 및 로더 선택 로직
**목표:** parse_static과 load_by_shell 통합, 모드 선택 로직

**산출물:**
```typescript
// packages/core/src/registry/Registry.ts (CL-2.1 확장)
async load(mode: 'static' | 'shell' = 'static'): Promise<void>

// 통합 팩토리 함수
async createRegistry(options?: { shell?: boolean }): Promise<HelpRegistry>
```

**개발 체크리스트:**
- [ ] Registry.load() 구현 (mode 선택)
- [ ] --shell-loader 플래그 처리 (CLI에서 전달)
- [ ] 기본값: static (보안, 성능)
- [ ] 캐싱 옵션 (선택사항)
- [ ] 통합 테스트 (둘 다 로드되고 결과 동일성 검증)

**자체 검증:**
```bash
npm run test -- registry.test.ts
# 정적 vs 실행 기반 모두 테스트
```

**테스트:**
```typescript
describe('HelpRegistry.load()', () => {
  it('should load with static mode by default', async () => {
    const registry = new HelpRegistry();
    await registry.load('static');
    expect(registry.getCategory('development')).toBeDefined();
  });

  it('should load with shell mode when specified', async () => {
    const registry = new HelpRegistry();
    await registry.load('shell');
    expect(registry.getCategory('development')).toBeDefined();
  });

  it('should produce consistent results', async () => {
    const r1 = new HelpRegistry();
    await r1.load('static');

    const r2 = new HelpRegistry();
    await r2.load('shell');

    expect(r1.toJSON().categories).toEqual(r2.toJSON().categories);
  });
});
```

**커밋 메시지:**
```
feat: Integrate registry loaders with mode selection

- Implement Registry.load() with mode selection
- Default to static mode (performance, security)
- Add --shell-loader flag support for CLI
- Include integration tests for both modes
- Verify result consistency between modes
```

**코드 리뷰 체크리스트:**
- [ ] 기본값이 static인가?
- [ ] 두 로더의 결과가 일치하는가?
- [ ] CLI와의 통합이 명확한가?
- [ ] 에러 처리가 충분한가?
- [ ] 문서화가 완전한가?

---

**Phase 2 완료 기준:**
- [x] CL-2.1: 타입 정의 및 기본 Registry
- [x] CL-2.2: 정적 파서 (my_help.sh 파싱)
- [x] CL-2.3: 실행 기반 로더 (bash/zsh)
- [x] CL-2.4: 통합 로직 및 모드 선택

**Phase 2 산출물:**
- 완전한 레지스트리 시스템
- 두 가지 로딩 전략 (정적, 동적)
- 포괄적인 테스트 (커버리지 90%+)
- 안전한 shell 통합

### Phase 3: Non-interactive 커맨드 (1주, 3개 CL)

#### CL-3.1: yargs 설정 및 기본 커맨드 라우팅
```typescript
// packages/cli/src/commands/index.ts
// yargs 설정, 글로벌 옵션, 포맷터 선택
```

**개발:**
- [ ] yargs 초기 설정 (version, help, global options)
- [ ] --json, --text 포맷 옵션
- [ ] --search, --filter 옵션
- [ ] 에러 핸들링 (invalid command)

**자체 검증:**
```bash
my-cli --version
my-cli --help
my-cli invalid-command    # 에러 처리 확인
```

**커밋:** `feat: Setup yargs command router with global options`

---

#### CL-3.2: list 커맨드 (categories, topics)
```bash
my-cli list categories --format json
my-cli list topics --search git --format json
```

**개발:**
- [ ] list categories 구현
- [ ] list topics + 검색 기능
- [ ] JSON/텍스트 포맷팅
- [ ] 페이지네이션 (선택사항)

**자체 검증:**
```bash
npm run test -- list.test.ts
my-cli list categories --format json | jq .
```

**커밋:** `feat: Implement list command (categories, topics)`

---

#### CL-3.3: show 커맨드 (토픽 상세)
```bash
my-cli show git --raw                 # my-help git 결과
my-cli show git --format json         # JSON
```

**개발:**
- [ ] show <topic> 구현
- [ ] --raw (원문 출력)
- [ ] --format json (구조화)
- [ ] pager 호출 (less -R)
- [ ] my_help_impl 함수 호출 (안전한 shell 통합)

**자체 검증:**
```bash
npm run test -- show.test.ts
my-cli show git --raw | head -5       # 출력 확인
```

**커밋:** `feat: Implement show command with pager support`

**Phase 3 산출물:**
- Non-interactive CLI 완성
- 3개 주요 커맨드 (list categories, list topics, show)
- JSON 출력 지원 (자동화 스크립트용)

### Phase 4: Interactive TUI (2주, 3개 CL)

#### CL-4.1: Ink 기본 컴포넌트 및 홈 화면
```typescript
// packages/cli/src/tui/App.tsx
// packages/cli/src/tui/screens/Home.tsx
```

**개발:**
- [ ] Ink 프로젝트 구조 (App.tsx, screens/)
- [ ] Home 화면: 카테고리 목록 표시
- [ ] 화살표 키 네비게이션 (↑↓)
- [ ] 카테고리 선택 시 토픽 목록으로 전환
- [ ] 기본 색상/스타일 정의

**자체 검증:**
```bash
npm run dev       # 또는 npx tsx packages/cli/src/index.ts
# 화면 확인: 카테고리 목록이 표시되는가?
# 화살표 키로 선택 가능한가?
```

**테스트:**
```typescript
import { render } from 'ink-testing-library';

describe('Home screen', () => {
  it('should render categories', async () => {
    const { output } = render(<Home registry={mockRegistry} />);
    expect(output).toContain('AI/LLM');
    expect(output).toContain('Development');
  });
});
```

**커밋:** `feat: Implement Ink TUI Home screen with category navigation`

---

#### CL-4.2: 토픽 목록 및 검색
```typescript
// packages/cli/src/tui/screens/TopicList.tsx
// 검색 입력 + 토픽 필터링
```

**개발:**
- [ ] TopicList 화면 (선택된 카테고리의 토픽)
- [ ] 검색 입력 필드 (/ 키로 활성화)
- [ ] 실시간 검색 필터링 (fuzzy match)
- [ ] 토픽 선택 (Enter)
- [ ] 뒤로가기 (Esc)

**자체 검증:**
```bash
npm run build && node packages/cli/dist/index.js help
# 카테고리 선택 → 토픽 목록 표시 확인
# / 입력 → 검색 필터링 작동 확인
```

**커밋:** `feat: Add TopicList screen with search filtering`

---

#### CL-4.3: 토픽 상세보기 및 키보드 통합
```typescript
// packages/cli/src/tui/screens/Detail.tsx
// packages/cli/src/tui/components/Pager.tsx
```

**개발:**
- [ ] Detail 화면: 선택된 토픽 상세 (my-help 결과)
- [ ] Pager 컴포넌트 (Page Up/Down, 스크롤)
- [ ] 모든 화면 간 키보드 통합
  - ↑↓ Enter Esc /
- [ ] 상태 관리 (현재 화면, 선택 항목)

**자체 검증:**
```bash
npm run build && node packages/cli/dist/index.js help
# 전체 흐름 테스트:
# Home → 카테고리 선택 → TopicList → 토픽 선택 → Detail → Pager
# 모든 키 입력이 정상 작동하는가?
npm test
```

**커밋:** `feat: Add topic detail screen with pager and integrated keyboard navigation`

**Phase 4 산출물:**
- 완전한 Interactive TUI
- 4개 화면 (Home, TopicList, Detail, Pager)
- 일관된 키보드 UX
- cold start < 500ms 달성

### Phase 5: Shell Completion (1주, 2개 CL)

#### CL-5.1: ShellFunctionAdapter (my-help 호출)
```typescript
// packages/core/src/adapters/ShellFunctionAdapter.ts
class ShellFunctionAdapter implements Adapter {
  async getTopic(topic: string): Promise<HelpTopic>
}
```

**개발:**
- [ ] ShellFunctionAdapter 클래스 구현
- [ ] my_help_impl 함수 호출 (execFile + array args)
- [ ] 안전한 shell 호출 (--noprofile --norc)
- [ ] 결과 파싱 (텍스트 → 구조화)
- [ ] 에러 처리 (timeout, execution error)

**자체 검증:**
```bash
npm run test -- ShellFunctionAdapter.test.ts
npm run test -- e2e.test.ts    # my-help 호출 경로 검증
```

**커밋:** `feat: Implement ShellFunctionAdapter with safe shell integration`

---

#### CL-5.2: Shell Completion 스크립트 생성
```bash
my-cli completion bash > shell-common/completions/my-cli.bash
my-cli completion zsh > shell-common/completions/_my-cli
```

**개발:**
- [ ] completion.ts 명령 구현
- [ ] bash completion script 생성
- [ ] zsh completion script 생성
- [ ] 동적 토픽 완성 지원
- [ ] dotfiles 설치 가이드

**자체 검증:**
```bash
my-cli completion bash
# 출력이 유효한 bash completion인가?

# 실제 설치 테스트
source <(my-cli completion bash)
my-cli help [TAB]  # 완성 작동 확인
```

**커밋:** `feat: Add shell completion generation for bash and zsh`

**Phase 5 산출물:**
- ShellFunctionAdapter 완성
- bash/zsh completion 스크립트

### Phase 6: 품질 & 배포 (2주, 3개 CL)

#### CL-6.1: E2E 및 성능 테스트
**목표:** 전체 흐름 테스트 및 성능 메트릭 달성

**개발:**
- [ ] E2E 테스트 (interactive + non-interactive)
- [ ] my-help 호출 경로 검증
- [ ] 성능 테스트 (cold start, 응답 시간)
  - TUI: < 500ms
  - Non-interactive: < 300ms
- [ ] 메모리 프로파일링

**자체 검증:**
```bash
npm run test -- e2e.test.ts
time my-cli help > /dev/null           # cold start 측정
time my-cli list topics --format json  # 응답 시간 측정
```

**커밋:** `test: Add comprehensive E2E tests and performance validation`

---

#### CL-6.2: esbuild 번들링 및 최적화
**목표:** 프로덕션 번들 생성 및 최적화

**개발:**
- [ ] esbuild 설정 (production mode)
- [ ] 번들 생성 (dist/my-cli.js)
- [ ] 크기 최적화 (target: < 15MB)
- [ ] source map 생성
- [ ] shebang 추가 (#!/usr/bin/env node)

**자체 검증:**
```bash
npm run build
ls -lh dist/my-cli.js              # 크기 확인
chmod +x dist/my-cli.js
./dist/my-cli.js help              # 실행 확인
```

**커밋:** `build: Configure esbuild bundling with optimization`

---

#### CL-6.3: 문서화, CI/CD, 및 v0.1.0 릴리스
**목표:** 프로덕션 배포 준비 완료

**개발:**
- [ ] API 문서화 (JSDoc → 마크다운)
- [ ] README.md (사용자 가이드)
- [ ] DEVELOPMENT.md (개발자 가이드)
- [ ] CHANGELOG.md (v0.1.0)
- [ ] GitHub Actions CI/CD 설정
- [ ] npm publish 준비
- [ ] Git tag v0.1.0

**자체 검증:**
```bash
npm run lint          # ESLint 통과
npm run typecheck     # TypeScript 통과
npm run test          # 모든 테스트 통과
npm run build         # 번들 생성 성공
cat README.md         # 문서 확인
```

**CI/CD 체크리스트:**
```yaml
# .github/workflows/ci.yml
- [ ] Lint (eslint)
- [ ] Type check (tsc)
- [ ] Tests (npm run test --coverage)
- [ ] Build (npm run build)
- [ ] Optional: Publish to npm registry
```

**Git 작업:**
```bash
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
# GitHub Releases 페이지에서 릴리스 노트 작성
```

**커밋:** `docs: Complete documentation, setup CI/CD, and prepare v0.1.0 release`

**Phase 6 산출물:**
- 포괄적인 E2E 테스트
- 성능 메트릭 달성
- 프로덕션 번들
- 완전한 문서화
- CI/CD 파이프라인
- v0.1.0 릴리스 완료

### Phase 7: 이후 단계 (v0.2+)

v0.1 이후 요구에 따라 우선순위 결정:
- ManpageAdapter + MarkdownAdapter
- 플러그인 시스템 고도화
- alias 전환 (my-help → my-cli)

**타임라인: v0.1 총 11-12주 (Phase 0-6)**

**v0.2 이후: 별도 REQ 문서로 진행**

---

## 8. 데이터 흐름도

```
┌─────────────────────────────────────┐
│       사용자 입력 (터미널)           │
│  my-cli help / my-cli list topics   │
└────────────────────┬────────────────┘
                     │
                     ▼
            ┌────────────────┐
            │  index.ts      │
            │  (shebang)     │
            └────────┬───────┘
                     │
                     ▼
            ┌────────────────────┐
            │  main.ts           │
            │  (mode routing)    │
            └────────┬───────────┘
                     │
         ┌───────────┴───────────┐
         │                       │
         ▼                       ▼
    ┌─────────┐         ┌──────────────┐
    │   TUI   │         │  Non-int CMD │
    │ (Ink)   │         │ (yargs)      │
    │ App.tsx │         │ list/show    │
    └────┬────┘         └──────┬───────┘
         │                      │
         └──────────┬───────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  core/Registry       │
         │  (패키지: @my-cli)   │
         │                      │
         │  ├─ load()           │
         │  │  ├─ parseStatic() │
         │  │  │  (my_help.sh)  │
         │  │  └─ loadByShell() │
         │  │     (옵션)        │
         │  ├─ getTopic()       │
         │  ├─ search()         │
         │  └─ toJSON()         │
         └──────────┬───────────┘
                    │
         ┌──────────┴──────────┐
         │                     │
         ▼                     ▼
    ┌──────────┐         ┌──────────┐
    │Adapters  │         │Sanitize  │
    │ Shell    │         │ (입력    │
    │ Manpage  │         │  검증)   │
    │ Markdown │         └──────────┘
    └──────────┘
```

---

## 9. 테스트 전략

### 9.1 단위 테스트 (vitest)

```typescript
// packages/core/tests/sanitize.test.ts
describe('validateTopic', () => {
  it('should accept valid topic names', () => {
    expect(() => validateTopic('git', registry)).not.toThrow();
    expect(() => validateTopic('git-flow', registry)).not.toThrow();
    expect(() => validateTopic('py_3_12', registry)).not.toThrow();
  });

  it('should reject invalid characters', () => {
    expect(() => validateTopic('git; rm -rf /', registry)).toThrow();
    expect(() => validateTopic('git$(whoami)', registry)).toThrow();
  });

  it('should reject non-existent topics', () => {
    expect(() => validateTopic('nonexistent', registry)).toThrow();
  });
});

// packages/core/tests/parse_static.test.ts
describe('parseStaticRegistry', () => {
  it('should parse HELP_CATEGORIES', async () => {
    const registry = await parseStaticRegistry(MY_HELP_PATH);
    expect(registry.getCategory('development')).toBeDefined();
    expect(registry.getCategory('ai')).toBeDefined();
  });

  it('should parse HELP_DESCRIPTIONS', async () => {
    const topic = registry.getTopic('git');
    expect(topic?.description).toMatch(/Development.*Git/);
  });

  it('should handle malformed input', async () => {
    expect(() => parseStaticRegistry('invalid.sh')).rejects.toThrow();
  });
});
```

### 9.2 통합 테스트

```typescript
// packages/cli/tests/e2e.test.ts
describe('my-cli e2e', () => {
  it('should list categories in JSON', async () => {
    const { stdout } = await execFile('my-cli', [
      'list', 'categories', '--format', 'json'
    ]);
    const data = JSON.parse(stdout);
    expect(data.categories.length).toBeGreaterThan(0);
  });

  it('should show topic using my-help', async () => {
    const { stdout } = await execFile('my-cli', [
      'show', 'git', '--raw'
    ]);
    expect(stdout).toContain('git');  // my-help output
  });

  it('should respect security constraints', async () => {
    const { exitCode } = await execFile('my-cli', [
      'show', 'git; rm -rf /'
    ]);
    expect(exitCode).toBe(ExitCode.SecurityError);
  });
});
```

### 9.3 성능 테스트

```bash
# 성능 측정
$ time my-cli help                    # TUI 첫 화면 (목표: 500ms)
$ time my-cli list topics --format json  # Non-int (목표: 300ms)

# 메모리 프로파일
$ node --prof index.ts help
$ node --prof-process isolate-*.log > processed.txt
```

---

## 10. 오픈 이슈 및 결정 필요 사항

| # | 항목 | 옵션 | 권장 | 결정자 |
|---|------|------|------|--------|
| **1** | TUI 라이브러리 | Ink (React) vs chalk+blessed vs curses | Ink (React 컴포넌트 모델, 장기 확장성) | 팀 |
| **2** | Pager 방식 | less -R 호출 vs Ink 스크롤 컴포넌트 | less -R (구현 단순, 사용자 친숙) | 팀 |
| **3** | 레지스트리 로딩 기본값 | 정적 파서만 vs 정적+실행 옵션 | 정적만 (보안, 성능, --shell-loader로 옵션) | 팀 |
| **4** | 명령명 | my-cli vs my (짧음, 충돌 가능성) | my-cli (명확, 기존 my-help와 구분) | 팀 |
| **5** | 이전 호환성 | alias my-help='my-cli help' v0.1 필수 vs 후속 단계 | **후속 단계** (v0.1은 별도 진입점, v0.2+에서 alias 옵션) | 팀 |
| **6** | 향후 AI 기능 | 이번 v0.1에 포함 vs 별도 req | **별도 req** (스코프 분리, 우선순위 검토) | PM |

---

## 11. 수용 기준 (AC)

### 11.1 기능 (Functional)

- [ ] **AC-F1**: `my-cli help` 실행 시 TUI 카테고리 화면 표시 (< 500ms)
- [ ] **AC-F2**: 카테고리 선택 시 해당 토픽 목록 표시
- [ ] **AC-F3**: 토픽 선택 시 `my-help <topic>` 결과를 pager로 표시
- [ ] **AC-F4**: `my-cli list categories --format json` 작동
- [ ] **AC-F5**: `my-cli list topics --search git` 검색 작동
- [ ] **AC-F6**: `my-cli show git --raw` 원문 출력
- [ ] **AC-F7**: `my-cli completion bash/zsh` completion script 생성
- [ ] **AC-F8**: 모든 기존 my-help 카테고리/토픽 포함

### 11.2 비기능 (Non-Functional)

- [ ] **AC-N1**: TUI cold start < 500ms
- [ ] **AC-N2**: Non-interactive 응답 < 300ms
- [ ] **AC-N3**: 번들 크기 < 15MB
- [ ] **AC-N4**: Node.js 20+ LTS 호환
- [ ] **AC-N5**: macOS/Linux/WSL 호환

### 11.3 보안 (Security)

- [ ] **AC-S1**: 토픽 이름 화이트리스트 검증 ([A-Za-z0-9_-]+)
- [ ] **AC-S2**: Shell injection 방지 (spawn + array args)
- [ ] **AC-S3**: 레지스트리 미등록 토픽 거부
- [ ] **AC-S4**: 에러 출력에 민감 정보 미포함

### 11.4 품질 (Quality)

- [ ] **AC-Q1**: 테스트 커버리지 ≥ 85%
- [ ] **AC-Q2**: ESLint + Prettier 통과
- [ ] **AC-Q3**: TypeScript strict mode 통과
- [ ] **AC-Q4**: 공개 API JSDoc 완성

### 11.5 호환성 (Compatibility)

- [ ] **AC-C1**: 기존 my-help.sh 함수 코드 무변경 (주석/포맷 제외)
- [ ] **AC-C2**: 기존 HELP_CATEGORIES/DESCRIPTIONS 데이터 100% 마이그레이션
- [ ] **AC-C3**: my-cli 실행 시 my-help 함수와 동일한 동작 검증
- [ ] **AC-C4**: my-help 함수 계속 사용 가능 (레거시 호환성)

---

## 12. 리뷰 체크리스트 (동료 리뷰용)

### 설계 검증 (High Priority Feedback 적용)

- [ ] my-help 무변경 원칙이 명확한가? (v0.1에서는 별도 진입점, alias는 v0.2+)
- [ ] 레지스트리 로더가 현재 my_help.sh의 모든 패턴을 파싱할 수 있는가?
  - HELP_CATEGORIES[key]="value"
  - HELP_DESCRIPTIONS[key]="value"
  - HELP_CATEGORY_MEMBERS[key]="value"
  - 기본값 패턴: ${...:-...}
- [ ] Shell 호출이 정확한가? (bash -lc 호출 형식, my_help_impl 함수 호출)
- [ ] 보안 설계 (injection 방지)가 모든 셸 호출 경로에서 적용되는가?
- [ ] dotfiles 규칙을 준수하는가? (~/bashrc 직접 수정 금지, symlink 방식)
- [ ] 오픈 이슈(Section 10)가 모두 결정되었는가?

### 구현 검증

- [ ] sanitize.ts가 모든 CLI 커맨드 진입점에서 호출되는가?
- [ ] 정적 파서가 예상 시간(200ms 내)에 완료되는가?
- [ ] Non-interactive 테스트가 JSON schema validation 포함하는가?
- [ ] E2E 테스트에서 실제 my-help 호출 경로를 검증하는가?

### 배포 검증

- [ ] esbuild 번들 크기가 목표(< 15MB)를 충족하는가?
- [ ] Shell completion script가 bash/zsh 모두 작동하는가?
- [ ] npm publish 시 의존성이 정확히 명시되는가?

---

## 13. 의존성

### Core Dependencies

| 패키지 | 버전 | 용도 | 라이선스 |
|--------|------|------|---------|
| yargs | ^17.7 | CLI 인자 파싱 | MIT |
| ink | ^4.4 | React TUI | MIT |
| chalk | ^5.3 | 색상 출력 | MIT |
| fs-extra | ^11 | 파일 시스템 | MIT |
| cosmiconfig | ^8 | 설정 로딩 | MIT |

### Dev Dependencies

| 패키지 | 버전 | 용도 | 라이선스 |
|--------|------|------|---------|
| vitest | ^1.0 | 테스트 | MIT |
| esbuild | ^0.19 | 번들링 | MIT |
| typescript | ^5.3 | 언어 | Apache-2.0 |
| eslint | ^8.50 | Linting | MIT |
| prettier | ^3.0 | 포매팅 | MIT |

---

## 14. 마이그레이션 맵

```
shell-common/functions/my_help.sh
├─ Line 33-40 (Init arrays)
│  → TypeScript: HelpRegistry.ts
│     HELP_DESCRIPTIONS → registry.descriptions: Map
│     HELP_CATEGORIES → registry.categories: Map
│
├─ Line 45-60 (Members)
│  → TypeScript: parse_static.ts
│     HELP_CATEGORY_MEMBERS → registry.topics per category
│
├─ Line 73-84 (Register help)
│  → TypeScript: HelpRegistry.register()
│
├─ Line 297-380 (Show categories/topics)
│  → TypeScript: tui/screens/Home.tsx + Topic.tsx
│
└─ Line 509-637 (Main logic)
   → TypeScript: main.ts (mode routing)
```

---

## 15. 참고 자료

### 기존 시스템

- `shell-common/functions/my_help.sh`: 현재 help 시스템
- `shell-common/tools/`: CLI 도구 모음
- `claude/skills/`: Claude 기술 명세

### 참고 프로젝트

- **gemini-cli**: Node.js/TypeScript monorepo 패턴
  - `packages/*/package.json`: 워크스페이스 구조
  - `esbuild.config.js`: 번들링 설정
  - `packages/cli/index.ts`: 진입점 패턴

- **my-help.sh**: 마이그레이션 소스
  - 데이터: 40+ 토픽, 8개 카테고리
  - 로직: 매칭, 폴백, 출력

---

## 16. 성공 메트릭

| 메트릭 | 목표 | 측정 방법 |
|--------|------|---------|
| 기능 완성도 | 100% of existing features | 수용 기준 체크 |
| 성능 (cold start) | < 500ms | `time my-cli help` |
| 성능 (non-int) | < 300ms | `time my-cli list` |
| 테스트 커버리지 | ≥ 85% | `vitest --coverage` |
| 번들 크기 | < 15MB | `ls -lh bundle/my-cli.js` |
| 사용자 만족도 | 기존 동등 이상 | 팀 피드백 |

---

## 17. 다음 단계

### 즉시 (This Week)

1. **이 문서 팀 리뷰**
   - 설계 검토 및 피드백 수집
   - 오픈 이슈(Section 10) 결정

2. **기술 검증**
   - Ink 프로토타입 (React TUI 가능성 확인)
   - 정적 파서 PoC (my_help.sh 파싱 검증)

3. **개발 환경 준비**
   - monorepo 초기화
   - TypeScript/vitest 설정

### 시작 명령

설계 리뷰 완료 후:

```bash
> "REQ-abc-C 개발해"  # Claude Code CLI로 Phase 1 시작
```

---

## Appendix A: 보안 감사 체크리스트

```
[ ] 모든 외부 입력은 sanitize.validateTopic() 통과
[ ] 셸 호출은 execFile + array args만 사용 (exec 금지)
[ ] 토픽 이름은 레지스트리 존재 확인 후 실행
[ ] 에러 메시지에 파일 경로/환경 변수 노출 금지
[ ] 타임아웃 설정 (shelload 5초, show 10초)
[ ] 의존성 audit 정기 실행 (npm audit)
```

## Appendix B: 성능 프로파일링 가이드

```bash
# Cold start 측정
time my-cli help > /dev/null

# Memory profiling
node --expose-gc index.ts help
# vs
node --prof index.ts help && node --prof-process *.log

# Benchmark (다중 실행)
for i in {1..5}; do time my-cli list topics; done
```

---

**Document Version**: 2.1 (Feedback Applied)
**Last Updated**: 2026-02-19
**Status**: Ready for Implementation (High Priority Feedback Integrated)
**Prepared By**: Unified Design Analysis (req-abc-CX + req-abc-G + req-CLI-MyCLI-1)

**최근 변경 사항 (v2.0 → v2.1):**
- alias 전환 (my-help → my-cli) 스코프 명확화: v0.1 제외 → v0.2+ 선택사항
- Shell 호출 예시 정확성 보강: bash -lc 올바른 사용법, my_help_impl 직접 호출
- 정적 파서 검증: 현재 my_help.sh의 모든 패턴 커버 확인 필요 명시
- dotfiles 규칙 준수: completion 설치 방식 변경 (~/.bashrc 직접 수정 금지)
- XDG 설정 경로: ~/.config/my-cli/config.json 표준 준수
- Pager 폴백: less 미설치 시 평문 출력 전략
- 플러그인 범위: ManpageAdapter/MarkdownAdapter는 v0.2+로 이동
- 문서 정합성: 절대 경로 → 상대 경로, 이모지 제거
