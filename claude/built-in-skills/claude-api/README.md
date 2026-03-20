# /claude-api - Claude API/SDK 레퍼런스 로더

Claude Code 내장(built-in) 스킬. 플러그인/마켓플레이스가 아닌 Claude Code 바이너리에 포함되어 있어 파일시스템에 별도의 `SKILL.md`가 존재하지 않는다. 프로젝트의 언어를 자동 감지하여 해당 언어의 Claude API 레퍼런스 문서와 Agent SDK 레퍼런스를 컨텍스트에 주입하는 대규모 문서 로더 스킬이다.

## 동작 요약

프로젝트 파일을 검사하여 사용 언어(Python, TypeScript, Java, Go, Ruby, C#, PHP, cURL)를 판별한 뒤, 해당 언어에 맞는 API 레퍼런스 문서 8개 이상을 `<doc>` 섹션으로 컨텍스트에 일괄 주입한다. 코드를 생성하거나 수정하지 않고, **Claude가 API 관련 질문에 정확히 답할 수 있도록 참조 자료를 제공하는 것**이 유일한 목적이다.

## 트리거 조건

| 조건 | 설명 |
| ---- | ---- |
| 사용자 호출 | `/claude-api`로 직접 호출 (`userInvocable: true`) |
| 자동 트리거 | 코드에서 `anthropic`, `@anthropic-ai/sdk`, `claude_agent_sdk`를 import하면 자동 활성화 (`disableModelInvocation: false`) |

사용자가 명시적으로 호출하지 않아도 SDK import가 감지되면 Claude가 스스로 스킬을 로드할 수 있다는 점이 다른 built-in 스킬과 구별되는 특징이다.

## 언어 감지 (Language Detection)

프로젝트 파일(package.json, pyproject.toml, go.mod, Cargo.toml 등)을 검사하여 언어를 결정한다. 감지된 언어에 따라 주입되는 문서 세트와 사용 가능한 기능이 달라진다.

| 언어 | Tool Runner | Agent SDK |
| ---- | ----------- | --------- |
| Python | Yes (beta) | Yes |
| TypeScript | Yes (beta) | Yes |
| Java | Yes (beta) | No |
| Go | Yes (beta) | No |
| Ruby | Yes (beta) | No |
| cURL | N/A | N/A |
| C# | No | No |
| PHP | No | No |

- **Tool Runner**: `@beta_tool` 데코레이터를 통한 자동 도구 실행 지원 여부
- **Agent SDK**: `claude_agent_sdk`를 통한 에이전트 빌딩 지원 여부
- 언어를 감지하지 못하면 fallback 로직이 적용된다

## Surface 선택 가이드

스킬은 사용자의 요구사항에 맞는 구현 방식을 결정하는 decision tree를 제공한다.

| Surface | 적합한 경우 |
| ------- | ----------- |
| **Single API Call** | 단일 요청-응답으로 충분한 경우 (텍스트 생성, 분류, 요약 등) |
| **Workflow** | 여러 API 호출을 체이닝하거나 오케스트레이션이 필요한 경우 |
| **Agent SDK** | 도구를 사용하여 자율적으로 목표를 달성해야 하는 경우 (Python/TypeScript만 해당) |

## 포함된 참조 문서

스킬이 컨텍스트에 주입하는 `<doc>` 섹션 목록이다. 언어별로 달라질 수 있으나, Python 기준으로 다음이 포함된다.

### API 레퍼런스

| 문서 | 내용 |
| ---- | ---- |
| `python/claude-api/README.md` | 클라이언트 초기화, 기본 메시지, vision, prompt caching, extended thinking, multi-turn, compaction, 에러 처리, 비용 최적화 |
| `python/claude-api/batches.md` | Batch API (최대 100K 요청, 50% 비용 절감) |
| `python/claude-api/files-api.md` | Files API (업로드, 메시지에서 사용, 관리) |
| `python/claude-api/streaming.md` | Streaming 패턴, 이벤트 타입, thinking stream |
| `python/claude-api/tool-use.md` | Tool runner (`@beta_tool`), MCP 변환, 수동 agentic loop, code execution, memory tool, structured outputs |

### Agent SDK 레퍼런스

| 문서 | 내용 |
| ---- | ---- |
| `python/agent-sdk/README.md` | Agent SDK Quick Start, built-in tools, `query()`, `ClaudeSDKClient`, permissions, MCP, hooks, subagents |
| `python/agent-sdk/patterns.md` | Custom tools, hooks, subagents, MCP integration, session resumption 패턴 |

### 공통(shared) 레퍼런스

| 문서 | 내용 |
| ---- | ---- |
| `shared/error-codes.md` | HTTP 에러 코드 레퍼런스 |
| `shared/live-sources.md` | 최신 문서를 가져올 수 있는 WebFetch URL 목록 |
| `shared/models.md` | 전체 모델 카탈로그 및 프로그래밍 방식 모델 디스커버리 |
| `shared/tool-use-concepts.md` | Tool 정의, tool choice, server-side tools (code execution, web search, computer use, memory), structured outputs |

## 주요 기본값 (Defaults)

| 항목 | 기본값 |
| ---- | ------ |
| 모델 | `claude-opus-4-6` |
| Thinking | adaptive (Opus 4.6, Sonnet 4.6에서 지원) |
| 응답 방식 | streaming |
| API endpoint | `POST /v1/messages` (단일 엔드포인트) |

## 아키텍처

- **단일 엔드포인트**: 모든 상호작용이 `POST /v1/messages`를 통해 이루어진다
- **사용자 정의 도구(user-defined tools)**: 함수 호출 기반 도구 정의
- **서버 사이드 도구(server-side tools)**: code execution, web search, computer use, memory
- **Structured outputs**: JSON schema 기반 응답 형식 강제
- **지원 엔드포인트**: models, files, batches 등 보조 API

## 모델 정보

| 모델 | ID | 비고 |
| ---- | -- | ---- |
| Claude Opus 4.6 | `claude-opus-4-6` | 최상위 모델, thinking 지원 |
| Claude Sonnet 4.6 | `claude-sonnet-4-6` | thinking 지원 |
| Claude Haiku 4.5 | `claude-haiku-4-5` | 경량 모델 |

모델 ID는 **정확히 위의 문자열**을 사용해야 하며, 임의 수정이나 추측은 허용되지 않는다.

## Thinking & Effort

- **Adaptive thinking**: Opus 4.6과 Sonnet 4.6에서 지원. 모델이 필요에 따라 자동으로 thinking을 활성화
- **Effort parameter**: thinking 깊이를 제어하는 파라미터
- **Legacy `budget_tokens`**: 이전 방식의 thinking 토큰 예산 설정 (호환성 유지)

## Compaction

- 긴 대화에서 컨텍스트를 압축하는 beta 기능
- 대화가 길어질 때 이전 메시지를 요약하여 토큰 사용량을 절감

## Common Pitfalls

스킬은 API 사용 시 흔한 실수를 경고하는 섹션을 포함한다.

| 함정 | 설명 |
| ---- | ---- |
| `budget_tokens` 혼동 | legacy thinking 설정과 새로운 effort parameter 혼용 주의 |
| `max_tokens` 설정 누락 | 응답 토큰 한도를 지정하지 않으면 예상치 못한 동작 발생 |
| Prefill 제거 | 특정 상황에서 prefill이 자동 제거되는 동작 주의 |
| JSON 파싱 | tool use 응답의 JSON 파싱 시 edge case 주의 |

## 특징

- **읽기 전용 스킬**: 코드를 생성하거나 수정하지 않는다. 오직 레퍼런스 문서를 컨텍스트에 주입하는 역할만 수행한다.
- **자동 트리거 가능**: `disableModelInvocation: false`로 설정되어 있어 SDK import가 감지되면 사용자 호출 없이도 Claude가 자동으로 로드할 수 있다. 대부분의 built-in 스킬이 사용자 전용 호출인 것과 대조적이다.
- **컨텍스트 인식 문서 주입**: 프로젝트 언어를 감지하여 해당 언어의 문서만 선택적으로 주입한다. 8개 언어를 지원하며, 언어별 기능 지원 수준(Tool Runner, Agent SDK)도 함께 안내한다.
- **대규모 컨텍스트 소비**: 8개 이상의 `<doc>` 섹션을 한꺼번에 주입하므로 상당한 컨텍스트 윈도우를 소비한다. 사실상 Claude Code 내장 스킬 중 가장 큰 컨텍스트 주입량을 가진 스킬이다.
- **모델 ID 엄격 관리**: 모델 ID를 캐시된 테이블로 제공하며, 정확한 문자열 사용을 강제한다. 모델 ID를 추측하거나 변형하는 것을 명시적으로 금지한다.
- **Live Sources 제공**: `shared/live-sources.md`를 통해 WebFetch로 최신 문서를 가져올 수 있는 URL을 제공하여, 캐시된 문서가 오래된 경우 실시간 업데이트가 가능하다.
