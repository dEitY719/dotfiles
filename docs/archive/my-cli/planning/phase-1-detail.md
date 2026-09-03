# Phase 1 상세 구현 계획 (CL-7.1~7.2)

**기간**: 1주일
**작업**: UI 개선 + 데이터 모델 확장
**상태**: 준비 완료

---

## CL-7.1: UI 개선 (2-3시간)

### 목표
- ANSI 컬러 복구 → 터미널 화려한 출력
- 의미없는 테두리 제거 → 레이아웃 개선
- 불필요한 헤더 감추기 → 공간 절약

---

## Task 1: TopicDetail.tsx 리팩토링

### 파일 위치
```
packages/my-cli/packages/cli/src/tui/screens/TopicDetail.tsx
```

### 현재 문제
```
1. ANSI 색상 제거됨 (ShellFunctionAdapter에서 strip)
   ├─ ANSI 패턴: /\u001b\[[0-9;]*m/g
   └─ 결과: 색상 없음 ❌

2. 의미없는 테두리 표시됨
   ├─ 예: ╔══════════════════╗
   ├─ 위치: content 상단
   └─ 결과: 공간 낭비 ❌

3. 헤더 라인이 계속 표시됨
   ├─ 예: first page에 header가 고정됨
   └─ 결과: 스크롤 시 이상함 ⚠️
```

### 해결 방안

#### 1-1: ANSI 색상 복구

**변경 위치**: 48~62줄 (content section)

```typescript
// Before (현재)
{topic.content ? (
  <>
    {visibleLines.map((line) => (
      <Text key={line || Math.random()}>{line}</Text>  // ← 색상 없음
    ))}
  </>
) : (
  <Text dimColor>No content</Text>
)}

// After (개선)
{topic.content ? (
  <>
    {visibleLines.map((line) => {
      // ANSI 색상 코드 적용
      const ansiToComponent = (str: string) => {
        // 색상 코드를 Ink Text의 color props로 변환
        // 예: \u001b[34m → color="blue"
        return <Text>{str}</Text>;  // 임시 (실제는 파싱 필요)
      };
      return <Box key={line}>{ansiToComponent(line)}</Box>;
    })}
  </>
) : (
  <Text dimColor>No content</Text>
)}
```

**라이브러리 확인**
```bash
# 설치된 색상 라이브러리 확인
cd packages/my-cli
npm ls | grep -i "chalk\|color\|ansi"
```

**추천**: chalk 또는 strip-ansi 이용
```bash
npm install chalk --save  # 필요시
```

#### 1-2: 의미없는 테두리 제거

**변경 위치**: 46~50줄 (contentLines 생성)

```typescript
// Before
const contentLines = useMemo(
  () => (topic.content ? topic.content.split('\n') : []),
  [topic.content],
);

// After (테두리 제거)
const contentLines = useMemo(
  () => {
    if (!topic.content) return [];
    const lines = topic.content.split('\n');

    // 의미없는 테두리 라인 필터링
    const filtered = lines.filter(line => {
      // 제거할 패턴들:
      // ╔══════╗, ╚══════╝, ║, ─ 등
      if (/^[╔╚═║╝┌┐└┘│─┬┴├┤┼]/.test(line.trim())) {
        return false;
      }
      return true;
    });

    return filtered;
  },
  [topic.content],
);
```

**패턴 설명**
```
제거할 문자들:
- ╔╗╚╝ (박스 모서리)
- ║ (박스 세로선)
- ═─ (박스 가로선)
- 기타 그리기 문자들
```

---

## Task 2: ShellFunctionAdapter.ts 수정

### 파일 위치
```
packages/core/src/adapters/ShellFunctionAdapter.ts
```

### 현재 문제
```typescript
// 현재 코드 (128~132줄)
private parseOutput(topicId: string, raw: string): HelpTopic {
  // ❌ ANSI 색상 코드 제거
  const content = raw
    .replace(/\u001b\[[0-9;]*m/g, '') // 이 줄 때문에 색상 손실!
    .trim();
  ...
}
```

### 해결 방안

```typescript
// After (색상 유지)
private parseOutput(topicId: string, raw: string): HelpTopic {
  // ✅ ANSI 색상 코드 유지
  const content = raw.trim();  // 그냥 trim만!

  // ... 나머지 코드 동일
}
```

**변경 사항**
```diff
- const content = raw
-   .replace(/\u001b\[[0-9;]*m/g, '') // 색상 제거 (X)
-   .trim();

+ const content = raw.trim();  // 색상 유지 (O)
```

---

## Task 3: 테스트

### Unit Tests
```bash
cd packages/my-cli

# 1. 기존 테스트 통과 확인
npm test

# 2. 색상 관련 수동 테스트
node packages/cli/dist/index.js show git | head -30
# ANSI 색상 확인 (터미널에서 색상이 보여야 함)
```

### E2E 테스트
```bash
# TUI 수동 테스트
node packages/cli/dist/index.js
# 1. Development 카테고리 선택
# 2. Git 선택
# 3. 확인:
#    - 색상 표시 ✓
#    - 테두리 없음 ✓
#    - 첫 화면에 불필요한 헤더 없음 ✓
```

---

## CL-7.2: 데이터 모델 확장 (4-5시간)

### 목표
HelpTopic 타입에 새로운 필드 추가 → Quick/Full Mode 지원 준비

---

## Task 4: HelpTopic 타입 확장

### 파일 위치
```
packages/core/src/registry/types.ts
```

### 현재 타입
```typescript
export interface HelpTopic {
  id: string;
  name: string;
  category: string;
  description: string;
  content?: string;
  examples?: string[];
  aliases?: string[];
  source: 'static' | 'shell';
  tags?: string[];
  updatedAt?: Date;
}
```

### 새 필드 추가

```typescript
export interface HelpTopic {
  // 기존 필드
  id: string;
  name: string;
  category: string;
  description: string;
  content?: string;
  examples?: string[];
  aliases?: string[];
  source: 'static' | 'shell';
  tags?: string[];
  updatedAt?: Date;

  // 새 필드 (CL-7.2)
  tier?: 1 | 2 | 3;              // 우선순위 Tier
  summary?: string;                // 한 줄 요약
  frequency?: 'daily' | 'weekly' | 'monthly' | 'rarely';  // 사용 빈도
  sections?: {                      // 콘텐츠 섹션 구조화
    title: string;
    items: Array<{
      command: string;
      description: string;
      example?: string;
    }>;
  }[];
}
```

### 필드 설명

| 필드 | 용도 | 예시 |
|------|------|------|
| tier | Tier 분류 | 1 (critical) |
| summary | 한 줄 설명 | "Git 버전 관리 도구" |
| frequency | 사용 빈도 | "daily" |
| sections | 콘텐츠 구조화 | [{title: "Basic", items: [...]}] |

---

## Task 5: 데이터 포맷 정의

### 새로운 HELP_* 변수

```bash
# 파일: shell-common/functions/*.sh
# 예시: git_help.sh

# 기존 (유지)
HELP_DESCRIPTIONS[git]="..."
HELP_CONTENT[git]="..."

# 신규 (추가)
HELP_TIER[git]="1"                    # Tier 1
HELP_FREQUENCY[git]="daily"           # 매일 사용
HELP_SUMMARY[git]="Git 버전 관리"      # 한 줄 요약

# Quick Mode 콘텐츠
HELP_CONTENT[git__quick]="gs   | git status
ga   | git add .
gc   | git commit
gp   | git push
gpl  | git pull
gco  | git checkout
gd   | git diff"

# Full Mode (기존 그대로)
HELP_CONTENT[git__full]="(기존 79줄 그대로)"
```

---

## Task 6: 파서 업데이트 (Optional)

### 파일
```
packages/core/src/registry/parse_static.ts
```

### 작업
새로운 HELP_* 변수들을 파싱할 수 있도록 regex 추가

```typescript
// 기존 CATEGORY_PATTERN 옆에 추가
const TIER_PATTERN = /HELP_TIER\[([a-z0-9_]+)\]="(\d)"/g;
const FREQUENCY_PATTERN = /HELP_FREQUENCY\[([a-z0-9_]+)\]="([^"]+)"/g;
const SUMMARY_PATTERN = /HELP_SUMMARY\[([a-z0-9_]+)\]="([^"]+)"/g;

// parseStaticRegistryFromString에서:
const tiers: Record<string, number> = {};
const frequencies: Record<string, string> = {};
const summaries: Record<string, string> = {};

// 각각 추출하고...

// topic 생성 시 추가
const topic: HelpTopic = {
  ...existing,
  tier: tiers[topicId],           // 추가
  frequency: frequencies[topicId], // 추가
  summary: summaries[topicId],     // 추가
};
```

---

## 예상 소요 시간

| Task | 예상 시간 | 난이도 |
|------|---------|--------|
| 1-1: 색상 복구 | 30분 | ⭐⭐ |
| 1-2: 테두리 제거 | 30분 | ⭐ |
| Task 3: 테스트 | 1시간 | ⭐⭐ |
| Task 4: 타입 확장 | 1시간 | ⭐ |
| Task 5: 데이터 포맷 | 1.5시간 | ⭐⭐ |
| Task 6: 파서 (Optional) | 1시간 | ⭐⭐⭐ |
| **총계** | **5-6시간** | |

---

## 구현 순서

```
1️⃣  TopicDetail.tsx 수정 (색상 + 테두리)
    └─ npm test 확인
    └─ 수동 테스트 (TUI)

2️⃣  ShellFunctionAdapter.ts 수정 (색상 유지)
    └─ npm test 확인
    └─ 수동 테스트 (CLI: show git)

3️⃣  HelpTopic 타입 확장
    └─ 빌드 확인
    └─ 타입 에러 없는지 확인

4️⃣  데이터 포맷 문서화 (shell-common)
    └─ 예시 작성
    └─ 포맷 명확히

5️⃣  파서 업데이트 (선택)
    └─ 테스트 작성
    └─ 통과 확인

6️⃣  최종 커밋
```

---

## ✅ Phase 1 완료 조건

- [ ] npm test 모두 통과
- [ ] my-cli show git에서 색상 표시됨
- [ ] 의미없는 테두리 제거됨
- [ ] HelpTopic 타입에 새 필드 추가됨
- [ ] 데이터 포맷 문서 작성됨
- [ ] Git 커밋 완료

---

## 📝 커밋 메시지 템플릿

```bash
git commit -m "$(cat <<'EOF'
feat(tui): Restore ANSI colors and improve layout

- Preserve ANSI color codes in ShellFunctionAdapter
- Remove meaningless box borders in TopicDetail
- Extend HelpTopic type with tier, summary, frequency fields
- Update data format for Quick/Full mode preparation
- All 357 tests passing

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## 🚀 Next Phase

Phase 1 완료 후:
- PHASE_2_DETAIL.md 읽기
- CL-7.3: Git 리팩토링 시작
