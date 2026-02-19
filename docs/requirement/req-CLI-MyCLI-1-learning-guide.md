# REQ-CLI-MyCLI-1: Learning Guide for ink + TypeScript Development

## 🚀 학습 순서 (이 순서대로 진행!)

### Week 1: Foundation (주중 2-3시간/일)

#### Day 1-2: TypeScript 기본
```typescript
// 1. 변수 선언 및 타입
const name: string = "my-cli";
const version: number = 0.1;
const isActive: boolean = true;

// 2. 함수 (중요!)
function greet(name: string): string {
  return `Hello, ${name}`;
}

const add = (a: number, b: number): number => a + b;

// 3. 인터페이스 (TypeScript의 핵심)
interface User {
  name: string;
  age: number;
  email?: string;  // optional
}

const user: User = { name: "Alice", age: 30 };

// 4. 클래스
class Counter {
  private count: number = 0;

  increment(): void {
    this.count++;
  }

  getCount(): number {
    return this.count;
  }
}
```

**학습 리소스**:
- TypeScript Handbook: https://www.typescriptlang.org/docs/
- 한국어 블로그: "TypeScript 기초" 검색
- 시간: 2-3시간

#### Day 3-4: React 기본 개념
```typescript
// 1. 컴포넌트 (함수형)
function Greeting(props: { name: string }) {
  return <div>Hello, {props.name}!</div>;
}

// 2. JSX (JavaScript XML 문법)
const element = (
  <div>
    <h1>My App</h1>
    <p>Welcome</p>
  </div>
);

// 3. Props (컴포넌트 입력)
interface CardProps {
  title: string;
  description: string;
}

function Card({ title, description }: CardProps) {
  return (
    <div>
      <h2>{title}</h2>
      <p>{description}</p>
    </div>
  );
}

// 4. 렌더링
export default Greeting;
```

**학습 리소스**:
- React Docs: https://react.dev/learn
- 한국어 강좌: "React 기초" (생활코딩 등)
- 시간: 2-3시간

#### Day 5: ink 라이브러리 튜토리얼
```typescript
// ink는 React로 TUI를 만드는 라이브러리
// React 컴포넌트를 터미널에 렌더링

import React from 'react';
import { render, Box, Text } from 'ink';

// 1. 기본 텍스트 출력
const App1 = () => <Text>Hello, ink!</Text>;

// 2. 박스 레이아웃
const App2 = () => (
  <Box flexDirection="column" borderStyle="round">
    <Text>📚 Help System</Text>
    <Text>Ready to use</Text>
  </Box>
);

// 3. 색상 (ink 내장)
const App3 = () => (
  <Text color="green">✓ Success</Text>
);

// 4. 마진/패딩
const App4 = () => (
  <Box marginLeft={2} paddingY={1}>
    <Text>Indented text</Text>
  </Box>
);

render(<App4 />);
```

**학습 리소스**:
- ink GitHub: https://github.com/vadimdemedes/ink
- 공식 예제: https://github.com/vadimdemedes/ink/tree/master/examples
- 시간: 2시간

---

### Week 2: Interactive Input + yargs

#### Day 1-2: ink Interactive Components
```typescript
// ink는 기본적으로 reactive하지 않음 → stdin 사용

import React, { useState, useEffect } from 'react';
import { render, Box, Text } from 'ink';
import SelectInput from 'ink-select-input';  // 서드파티 라이브러리

interface Item {
  label: string;
  value: string;
}

function HelpCategorySelector() {
  const [selectedValue, setSelectedValue] = useState<string>('');

  const items: Item[] = [
    { label: 'AI/LLM', value: 'ai' },
    { label: 'Development', value: 'development' },
    { label: 'DevOps', value: 'devops' },
  ];

  return (
    <Box flexDirection="column">
      <Text>Select a category:</Text>
      <SelectInput
        items={items}
        onSelect={(item) => setSelectedValue(item.value)}
      />
      {selectedValue && <Text>Selected: {selectedValue}</Text>}
    </Box>
  );
}

render(<HelpCategorySelector />);
```

**중요**: ink-select-input은 커뮤니티 패키지이므로 사용 검토 필요
- 대안 1: 직접 stdin 처리
- 대안 2: 다른 TUI 라이브러리 찾기 (blessed 등)

#### Day 3-4: yargs CLI Parser
```typescript
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';

const argv = yargs(hideBin(process.argv))
  .command(
    'help [topic]',
    'Show help',
    (yargs) =>
      yargs.positional('topic', {
        describe: 'Help topic',
        type: 'string',
      }),
    (argv) => {
      console.log(`Showing help for: ${argv.topic}`);
    }
  )
  .option('json', {
    alias: 'j',
    describe: 'Output as JSON',
    type: 'boolean',
  })
  .parseSync();

// 사용: $ my-cli help git --json
```

**학습 리소스**:
- yargs 문서: https://yargs.js.org/
- 시간: 1-2시간

#### Day 5: 첫 프로토타입 만들기
```typescript
// packages/cli/src/index.ts

import React from 'react';
import { render, Box, Text } from 'ink';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';

// 1. 간단한 UI 컴포넌트
const HelpScreen: React.FC<{ topic?: string }> = ({ topic }) => (
  <Box flexDirection="column">
    <Text bold color="cyan">
      📚 Help System
    </Text>
    {topic ? (
      <Box marginTop={1}>
        <Text>Help for: {topic}</Text>
      </Box>
    ) : (
      <Box marginTop={1}>
        <Text>Available categories: ai, development, devops</Text>
      </Box>
    )}
  </Box>
);

// 2. 메인 진입점
async function main() {
  const argv = yargs(hideBin(process.argv))
    .command('help [topic]', 'Show help', (y) =>
      y.positional('topic', { type: 'string' })
    )
    .parseSync();

  const topic = argv.topic as string | undefined;
  render(<HelpScreen topic={topic} />);
}

main().catch(console.error);
```

**실행**:
```bash
npx tsx packages/cli/src/index.ts help git
# 출력: 📚 Help System
#       Help for: git
```

---

## 📚 주간 학습 목표

### Week 1 목표
- [ ] TypeScript 기본 문법 이해 (2-3시간)
- [ ] React 컴포넌트 개념 숙지 (2-3시간)
- [ ] ink 라이브러리 기본 사용 가능 (2시간)
- [ ] 간단한 "Hello World" ink 앱 만들기
- [ ] yargs로 CLI 인자 파싱 해보기

### Week 2 목표
- [ ] ink로 텍스트 레이아웃 만들기
- [ ] 마진/패딩/색상 활용
- [ ] 첫 프로토타입 (HelpScreen) 동작
- [ ] TypeScript 타입 안정성 이해
- [ ] 빌드/번들 파이프라인 구성

---

## 🔧 개발 환경 구성

### Step 1: 프로젝트 초기화
```bash
cd /home/bwyoon/dotfiles/packages

# 새 프로젝트 디렉토리
mkdir my-cli
cd my-cli

# Root package.json
npm init -y

# TypeScript 설정
npm install -D typescript @types/node

# 초기화
npx tsc --init
```

### Step 2: 패키지 설정
```bash
# packages 구조
mkdir -p packages/{core,cli}

# 각 패키지 초기화
npm init -y -w packages/core
npm init -y -w packages/cli

# Root package.json에 workspace 추가
# "workspaces": ["packages/*"]
```

### Step 3: 의존성 설치
```bash
# Root에서 설치 (모든 workspace에 적용)
npm install react ink yargs

# 개발 의존성
npm install -D typescript tsx vitest eslint prettier
npm install -D @types/react @types/node
```

### Step 4: 개발 스크립트 설정
```json
{
  "scripts": {
    "dev": "tsx watch packages/cli/src/index.ts",
    "build": "tsc",
    "test": "vitest",
    "lint": "eslint ."
  }
}
```

---

## 🎯 일일 학습 플래너

### 월요일 (TypeScript 기본)
```
09:00 - 10:00: TypeScript 공식 문서 읽기
10:00 - 11:30: 타입, 인터페이스 직접 코딩
11:30 - 12:00: 간단한 클래스 작성 및 테스트
점심
14:00 - 15:30: 함수 오버로딩, 제네릭 학습
15:30 - 16:00: 학습한 내용 정리 및 요약
```

### 화요일 (React 기본)
```
09:00 - 10:00: React 공식 튜토리얼
10:00 - 11:30: 간단한 컴포넌트 만들기
11:30 - 12:00: Props와 상태 이해
점심
14:00 - 15:30: 여러 컴포넌트 조합하기
15:30 - 16:00: JSX 문법 깊이 있게 학습
```

### 수요일 (ink 라이브러리)
```
09:00 - 10:00: ink 공식 예제 따라하기
10:00 - 11:30: Box, Text 컴포넌트 실험
11:30 - 12:00: 색상, 마진, 패딩 적용
점심
14:00 - 15:30: 첫 프로토타입 (HelpScreen) 작성
15:30 - 16:00: 문제 해결 및 리팩토링
```

### 목요일 (yargs + 통합)
```
09:00 - 10:00: yargs 문서 학습
10:00 - 11:30: CLI 커맨드 파싱 구현
11:30 - 12:00: help 커맨드 연결
점심
14:00 - 15:30: 빌드 파이프라인 구성
15:30 - 16:00: 전체 흐름 테스트
```

### 금요일 (복습 및 심화)
```
09:00 - 10:00: 주간 학습 내용 복습
10:00 - 11:30: 첫 전체 프로토타입 완성
11:30 - 12:00: 리팩토링 및 최적화
점심
14:00 - 15:30: 다음주 계획 및 심화 학습
15:30 - 16:00: 코드 리뷰 및 문제점 정리
```

---

## ⚠️ 일반적인 함정 (Pitfalls)

### 1. JSX 문법 헷갈림
```typescript
// ❌ 틀림
const bad = <Text>Hello</Text>;  // JSX는 일반 JS가 아님

// ✅ 맞음
import React from 'react';
const good = <Text>Hello</Text>;  // React import 필수
```

### 2. ink는 웹 React가 아님
```typescript
// ❌ 틀림 (웹 React)
return <div style={{ color: 'red' }}>Hello</div>;

// ✅ 맞음 (ink)
return <Text color="red">Hello</Text>;
```

### 3. 비동기 처리
```typescript
// ❌ 틀림
const getData = async () => {
  const data = await fetch(...);  // ink에서는 fetch 안됨
};

// ✅ 맞음
import { readFileSync } from 'fs';
const data = readFileSync('./data.json', 'utf-8');
```

### 4. 타입 오류
```typescript
// ❌ 틀림
const items: any[] = [];  // any 사용 금지

// ✅ 맞음
interface Item {
  id: string;
  name: string;
}
const items: Item[] = [];
```

---

## 📖 추천 학습 리소스

### TypeScript
1. **공식 Handbook** (필독)
   - https://www.typescriptlang.org/docs/handbook/
   - 시간: 4-6시간

2. **TypeScript Deep Dive** (한국어)
   - https://basarat.gitbook.io/typescript/
   - 시간: 2-3시간

3. **유튜브**: "TypeScript Tutorial for Beginners"
   - 시간: 1-2시간

### React
1. **React 공식 학습** (최신)
   - https://react.dev/learn
   - 시간: 3-4시간

2. **생활코딩 React**
   - https://www.youtube.com/results?search_query=생활코딩+react
   - 시간: 2-3시간

### ink
1. **GitHub README**
   - https://github.com/vadimdemedes/ink#readme
   - 시간: 1시간

2. **예제 코드**
   - https://github.com/vadimdemedes/ink/tree/master/examples
   - 시간: 2-3시간

3. **커뮤니티 패키지**
   - ink-select-input, ink-text-input 등
   - 문서: 각 GitHub repo

---

## 🚨 빠른 진행을 위한 팁

### 1. 예제 코드 먼저 실행해보기
```bash
# ink 예제 실행
git clone https://github.com/vadimdemedes/ink
cd ink/examples
npm install
npm start

# 그 다음 이해하기
```

### 2. REPL 활용 (ts-node)
```bash
# TypeScript REPL
npx ts-node
> const x: number = 5
> x + 3
```

### 3. 작은 단위로 자주 테스트
```bash
# 매번 빌드하지 말고, tsx watch 사용
npm run dev

# 파일 저장하면 자동 재실행
```

### 4. 타입 오류를 두려워하지 않기
```typescript
// TypeScript는 실수를 미리 알려줌 (좋은 것!)
const x: string = 5;  // ❌ Error (즉시 알 수 있음)
```

### 5. 문서를 적극 활용하기
- 막힐 때: Google "ink how to X"
- 에러 메시지 읽기 (매우 도움됨)
- 예제 코드 참고

---

## 🎓 주간 체크리스트

### Week 1 완료 기준
- [ ] TypeScript 기본 타입 이해
- [ ] 함수와 인터페이스 작성 가능
- [ ] React 컴포넌트 개념 이해
- [ ] JSX 문법 사용 가능
- [ ] ink Box/Text로 간단한 UI 만들기
- [ ] "Hello World" TUI 앱 동작

### Week 2 완료 기준
- [ ] ink 여러 컴포넌트 조합 가능
- [ ] 색상, 마진, 레이아웃 활용
- [ ] yargs로 CLI 인자 파싱
- [ ] 첫 프로토타입 (HelpScreen) 완성
- [ ] npm run dev로 개발 가능
- [ ] 타입 오류 스스로 해결 가능

---

## 💬 FAQ

### Q1: React를 꼭 배워야 하나?
**A**: ink는 React를 기반으로 하므로 React 개념이 필요합니다. 다행히 기본만 알면 됩니다 (상태 관리 등 심화는 나중).

### Q2: TypeScript는 너무 복잡한데?
**A**: 처음엔 기본만 알면 됩니다:
- 타입 선언 (: string, : number)
- 인터페이스 (interface)
- 함수 매개변수/반환 타입
나머지는 필요할 때 배우면 됩니다.

### Q3: 오류가 많이 나는데 정상인가?
**A**: 네, 정상입니다! TypeScript는 오류를 **미리** 알려주므로 개발 중 에러를 빨리 발견할 수 있습니다. 이게 장점입니다.

### Q4: 얼마나 걸릴까?
**A**:
- 기본 (1주): 4-6시간/일
- 프로토타입 (1주): 3-4시간/일
- 총 2주 후 본개발 가능

### Q5: 도움이 필요하면?
**A**:
1. 에러 메시지 읽기 (매우 구체적)
2. Google "error message here"
3. Stack Overflow 검색
4. ChatGPT나 Claude에 코드 붙여넣기

---

## 🎯 Success Path

```
Week 1:
Day 1-2 → TypeScript 기본 ✓
Day 3-4 → React 개념 ✓
Day 5   → ink "Hello World" ✓

Week 2:
Day 1-2 → ink 컴포넌트 실험 ✓
Day 3-4 → yargs CLI 파싱 ✓
Day 5   → 첫 프로토타입 완성 ✓

Week 3+:
본개발 시작 (HelpRegistry, 데이터 마이그레이션 등)
```

---

**이 가이드를 따르면 2주 후 본개발을 시작할 수 있습니다!** 🚀

막힐 때는 언제든 도움을 요청하세요. 함께 해결하겠습니다! 💪
