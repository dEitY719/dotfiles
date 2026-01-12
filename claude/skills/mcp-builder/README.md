# MCP Builder Skill

**MCP(Model Context Protocol) 서버 개발** - GitHub, Slack, API 등을 LLM과 연결하는 서버를 구축합니다.

---

## 🎯 이 스킬이 뭔가요?

외부 API나 외부 API나 서비스를 LLM(Claude)에 연결해주는 **MCP 서버**를 만듭니다. 사용자가 Claude와 대화하면서 자동으로
GitHub, Slack, 데이터베이스 등에 접근할 수 있게 합니다.

마치 Claude의 손과 발을 줄 것처럼, 실제 시스템과 상호작용할 수 있는 능력을 부여합니다.

---

## 🔄 어떻게 작동하나요?

### 4단계 프로세스

```text
1. 계획 및 연구 → 2. 구현 → 3. 테스트 및 검증 → 4. 평가
```text

#### 1단계: 계획 및 연구

**목표**: API 이해, 도구 설계

- **MCP 프로토콜 학습**: 스펙 읽기, 아키텍처 이해

- **API 조사**: 연결할 서비스의 엔드포인트, 인증, 데이터 모델

- **도구 설계**: 어떤 기능들을 LLM에 노출할 것인가?

  - 예: `github_list_issues`, `github_create_pr`, `github_merge_pr`

- **우선순위**: 가장 중요한 기능부터

**권장 기술**:

- **언어**: TypeScript (권장) 또는 Python

- **Transport**: HTTP (스케일 가능) 또는 stdio (로컬)

#### 2단계: 구현

**프로세스**:
1. 프로젝트 구조 설정
2. API 클라이언트 구현 (인증, 요청)
3. MCP 도구 등록
4. 에러 처리 및 응답 포맷팅

**TypeScript 예시**:
```typescript
server.registerTool("github_list_issues", {
  description: "List open issues for a repository",
  inputSchema: {
    type: "object",
    properties: {
      owner: { type: "string" },
      repo: { type: "string" },
      state: { type: "string", enum: ["open", "closed", "all"] }
    }
  }
}, async (args) => {
  // API 호출 및 결과 반환
});
```

#### 3단계: 테스트 및 검증

**도구**: MCP Inspector

```bash
npx @modelcontextprotocol/inspector
```text

- 모든 도구가 등록되었는가?

- 입력 스키마가 정확한가?

- 에러 메시지가 명확한가?

- 응답이 예상대로인가?

#### 4단계: 평가

**목표**: LLM이 이 서버를 얼마나 잘 활용할 수 있는가?

- 10개의 복잡한 평가 질문 작성

- 각 질문에 대해 LLM이 올바르게 응답하는지 확인

- 부족한 부분 개선

**예시 질문**:
```

"GitHub의 python-sdk repo에서 'authentication' 키워드를 포함하는
오픈된 이슈들을 모두 찾아서 개수를 세줘."

```text

---

## 📊 Output (생산물)

### 완성된 MCP 서버

```text
┌────────────────────────────────┐
│  MCP Server                    │
│  (GitHub, Slack, etc.)         │
│                                │
│  Tools Registered:             │
│  - github_list_repos           │

│  - github_list_issues          │

│  - github_create_pr            │

│  - github_merge_pr             │

│  [... 등등]                    │
│                                │
│  Ready for Claude Integration  │
└────────────────────────────────┘
```

**특징**:

- 프로덕션 레벨 코드

- 완벽한 에러 처리

- 명확한 도구 설명

- 평가된 품질

---

## 💡 실제 사용 예시

### 예시: GitHub MCP 서버

#### 요청

> "GitHub API를 LLM과 연결하는 MCP 서버를 만들어줄래?
> PR 관리, 이슈 조회, PR 생성 같은 기능들."

#### 설계

**프로토콜**: HTTP (Streamable HTTP)
**언어**: TypeScript
**도구들**:

- `github_list_repos` - 저장소 나열

- `github_list_issues` - 이슈 조회 (필터 가능)

- `github_create_issue` - 이슈 생성

- `github_list_prs` - PR 목록

- `github_create_pr` - PR 생성

- `github_merge_pr` - PR 병합

- 등등

#### 결과

```text
사용자: "python-sdk에서 지난 일주일의 오픈 이슈들을 정렬해줄 수 있어?"
Claude: [MCP 서버로 API 호출]
→ 최신순 10개 이슈 반환 + 분석
```

---

## 🎯 특징

| 특징 | 설명 |
| --- | --- |

| **MCP 프로토콜** | 최신 표준 구현 |
| **TypeScript 권장** | 타입 안전, 좋은 개발 경험 |
| **API 호출 추상화** | 인증, 에러 처리 자동화 |
| **도구 스키마** | Zod (TS) 또는 Pydantic (Python) |
| **에러 처리** | 명확한 에러 메시지 |
| **확장성** | 새 도구 추가 용이 |
| **평가된 품질** | 10개 평가 질문으로 검증 |

---

## 🚀 시작하기

### 사용자 입장 (Claude 사용할 때)

```text
"[서비스] API를 MCP 서버로 만들어줄래?
[원하는 기능들]이 포함되어야 해."
```text

예시:
```text
"Slack API를 MCP 서버로. 메시지 전송, 채널 조회, 파일 업로드."
```

### 기대할 수 있는 것

1. **완성된 코드**: TypeScript 또는 Python
2. **테스트됨**: MCP Inspector로 검증됨
3. **문서화됨**: 각 도구의 사용법 설명
4. **평가됨**: 실제 사용 케이스로 검증됨
5. **즉시 배포**: 프로덕션 레벨

---

## 🛠️ 기술 스택

**권장**:

- **언어**: TypeScript (최우선)

- **Framework**: MCP SDK (TypeScript) 또는 FastMCP (Python)

- **Transport**: Streamable HTTP (원격) 또는 stdio (로컬)

- **인증**: API 키, OAuth 등 (서비스에 따라)

- **호출**: axios, fetch (HTTP)

**개발 도구**:

- MCP Inspector (테스트)

- Node.js 18+ 또는 Python 3.9+

---

## 📚 스킬의 핵심 철학

> **"LLM은 강력하지만 혼자는 무력하다"**

- MCP 서버는 LLM의 손과 발

- 외부 시스템과의 안전한 연결

- 도구는 명확하고 신뢰할 수 있어야 함

- 에러 메시지는 다음 단계를 안내해야 함

---

## ❓ FAQ

**Q: 인증 처리는 어떻게?**

A: API 키, OAuth, 토큰 등 다양한 방식 지원. 보안 설정도 포함.

**Q: 대규모 API는?**

A: 엔드포인트 선별로 시작, 필요하면 확장. 처음부터 전부할 필요 없음.

**Q: TypeScript가 아니어도 되나요?**

A: Python도 가능하지만, TypeScript 권장 (더 나은 지원).

**Q: 실제 배포는?**

A: AWS Lambda, Google Cloud Functions 등으로 배포 가능.

**Q: 기존 API 변경 시?**

A: 도구만 수정하면 됨. 서버는 버전 관리됨.

---

## 📖 더 알고 싶으면

- **SKILL.md**: MCP 프로토콜 완전 가이드

- **reference/mcp_best_practices.md**: 설계 및 구현 베스트 프랙티스

- **reference/node_mcp_server.md**: TypeScript 상세 가이드

- **reference/python_mcp_server.md**: Python 상세 가이드

- **reference/evaluation.md**: 평가 질문 작성법

---

**이 스킬의 목표**: 외부 서비스를 Claude와 안전하게 연결하여, LLM이 실제 작업을 수행할 수 있게 하는 것입니다. 🔗✨
