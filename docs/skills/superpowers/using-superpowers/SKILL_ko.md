---
name: using-superpowers
description: Use when starting any conversation - establishes how to find and use skills, requiring Skill tool invocation before ANY response including clarifying questions
---

<SUBAGENT-STOP>
서브에이전트로 특정 작업을 수행하기 위해 디스패치된 경우, 이 스킬을 건너뛰세요.
</SUBAGENT-STOP>

<EXTREMELY-IMPORTANT>
스킬이 적용될 가능성이 1%라도 있다고 생각되면, 반드시 해당 스킬을 호출해야 합니다.

스킬이 작업에 적용된다면, 선택권이 없습니다. 반드시 사용해야 합니다.

이것은 협상할 수 없습니다. 선택 사항이 아닙니다. 합리화해서 피할 수 없습니다.
</EXTREMELY-IMPORTANT>

## 지시사항 우선순위

Superpowers 스킬은 기본 시스템 프롬프트 동작을 재정의하지만, **사용자 지시사항이 항상 우선**합니다:

1. **사용자의 명시적 지시사항** (CLAUDE.md, GEMINI.md, AGENTS.md, 직접 요청) — 최우선
2. **Superpowers 스킬** — 충돌하는 경우 기본 시스템 동작을 재정의
3. **기본 시스템 프롬프트** — 최하위 우선순위

CLAUDE.md, GEMINI.md, 또는 AGENTS.md에서 "TDD를 사용하지 마세요"라고 하고 스킬에서 "항상 TDD를 사용하세요"라고 하면, 사용자의 지시를 따르세요. 사용자가 통제권을 가집니다.

## 스킬 접근 방법

**Claude Code에서:** `Skill` 도구를 사용하세요. 스킬을 호출하면 해당 내용이 로드되어 제시됩니다—직접 따르세요. 스킬 파일에 Read 도구를 절대 사용하지 마세요.

**Copilot CLI에서:** `skill` 도구를 사용하세요. 스킬은 설치된 플러그인에서 자동 검색됩니다. `skill` 도구는 Claude Code의 `Skill` 도구와 동일하게 작동합니다.

**Gemini CLI에서:** `activate_skill` 도구를 통해 스킬이 활성화됩니다. Gemini는 세션 시작 시 스킬 메타데이터를 로드하고 필요할 때 전체 내용을 활성화합니다.

**다른 환경에서:** 스킬이 어떻게 로드되는지 해당 플랫폼의 문서를 확인하세요.

## 플랫폼 적응

스킬은 Claude Code 도구 이름을 사용합니다. CC가 아닌 플랫폼: 도구 대응표는 `references/copilot-tools.md` (Copilot CLI), `references/codex-tools.md` (Codex)를 참조하세요. Gemini CLI 사용자는 GEMINI.md를 통해 자동으로 도구 매핑이 로드됩니다.

# 스킬 사용하기

## 규칙

**응답이나 행동 전에 관련 스킬 또는 요청된 스킬을 먼저 호출하세요.** 스킬이 적용될 가능성이 1%라도 있다면 스킬을 호출하여 확인해야 합니다. 호출한 스킬이 해당 상황에 맞지 않는 것으로 판명되면, 사용하지 않아도 됩니다.

```dot
digraph skill_flow {
    "User message received" [shape=doublecircle];
    "About to EnterPlanMode?" [shape=doublecircle];
    "Already brainstormed?" [shape=diamond];
    "Invoke brainstorming skill" [shape=box];
    "Might any skill apply?" [shape=diamond];
    "Invoke Skill tool" [shape=box];
    "Announce: 'Using [skill] to [purpose]'" [shape=box];
    "Has checklist?" [shape=diamond];
    "Create TodoWrite todo per item" [shape=box];
    "Follow skill exactly" [shape=box];
    "Respond (including clarifications)" [shape=doublecircle];

    "About to EnterPlanMode?" -> "Already brainstormed?";
    "Already brainstormed?" -> "Invoke brainstorming skill" [label="no"];
    "Already brainstormed?" -> "Might any skill apply?" [label="yes"];
    "Invoke brainstorming skill" -> "Might any skill apply?";

    "User message received" -> "Might any skill apply?";
    "Might any skill apply?" -> "Invoke Skill tool" [label="yes, even 1%"];
    "Might any skill apply?" -> "Respond (including clarifications)" [label="definitely not"];
    "Invoke Skill tool" -> "Announce: 'Using [skill] to [purpose]'";
    "Announce: 'Using [skill] to [purpose]'" -> "Has checklist?";
    "Has checklist?" -> "Create TodoWrite todo per item" [label="yes"];
    "Has checklist?" -> "Follow skill exactly" [label="no"];
    "Create TodoWrite todo per item" -> "Follow skill exactly";
}
```

## 위험 신호

이런 생각이 들면 멈추세요—합리화하고 있는 것입니다:

| 생각 | 현실 |
|---------|---------|
| "이건 단순한 질문일 뿐이야" | 질문도 작업입니다. 스킬을 확인하세요. |
| "먼저 더 많은 맥락이 필요해" | 스킬 확인이 명확화 질문보다 먼저입니다. |
| "먼저 코드베이스를 탐색해볼게" | 스킬이 탐색 방법을 알려줍니다. 먼저 확인하세요. |
| "git/파일을 빠르게 확인할 수 있어" | 파일에는 대화 맥락이 없습니다. 스킬을 확인하세요. |
| "먼저 정보를 수집할게" | 스킬이 정보 수집 방법을 알려줍니다. |
| "이건 정식 스킬이 필요 없어" | 스킬이 존재하면, 사용하세요. |
| "이 스킬 기억나" | 스킬은 진화합니다. 현재 버전을 읽으세요. |
| "이건 작업에 해당하지 않아" | 행동 = 작업. 스킬을 확인하세요. |
| "이 스킬은 과하다" | 단순한 것도 복잡해집니다. 사용하세요. |
| "이것만 먼저 할게" | 무엇이든 하기 전에 먼저 확인하세요. |
| "이건 생산적인 것 같아" | 규율 없는 행동은 시간 낭비입니다. 스킬이 이를 방지합니다. |
| "그게 무슨 뜻인지 알아" | 개념을 아는 것 ≠ 스킬을 사용하는 것. 호출하세요. |

## 스킬 우선순위

여러 스킬이 적용될 수 있을 때, 이 순서를 따르세요:

1. **프로세스 스킬 먼저** (brainstorming, debugging) - 작업 접근 방법을 결정합니다
2. **구현 스킬 다음** (frontend-design, mcp-builder) - 실행을 안내합니다

"X를 만들자" → brainstorming 먼저, 그다음 구현 스킬.
"이 버그를 고쳐줘" → debugging 먼저, 그다음 도메인별 스킬.

## 스킬 유형

**엄격형** (TDD, debugging): 정확히 따르세요. 규율에서 벗어나지 마세요.

**유연형** (patterns): 원칙을 맥락에 맞게 적용하세요.

스킬 자체가 어느 유형인지 알려줍니다.

## 사용자 지시사항

지시사항은 무엇을 할지 알려주지, 어떻게 할지 알려주지 않습니다. "X를 추가해" 또는 "Y를 고쳐줘"가 워크플로우를 건너뛰라는 뜻은 아닙니다.
