---
name: req-draft
description: Create and iterate on feature requirement draft documents. Use when starting new feature discussions, writing initial requirement drafts, or synthesizing colleague review documents. Triggered by "/req-draft", "요구사항 초안", "기능 초안 작성", or any request to create/update feature requirement documents in docs/feature/.
---

# Requirement Draft

Create structured feature requirement drafts and synthesize multi-agent review feedback.

## Help

When invoked with `-h` or `--help`, display this usage and stop:

```
/req-draft — 요구사항 초안 작성 & 동료 리뷰 종합

Usage:
  /req-draft v1 <input>                    초안 생성 (자동 경로)
  /req-draft <path> v1 <input>             초안 생성 (경로 지정)
  /req-draft v2                            동료 리뷰 종합 (최근 디렉토리)
  /req-draft <path> v2                     동료 리뷰 종합 (경로 지정)
  /req-draft -h | --help                   이 도움말 표시

Arguments:
  <path>      docs/feature/ 하위 경로 (optional, 생략시 자동 생성)
  <version>   v1 = 초안 생성, v2 = 동료 리뷰 반영
  <input>     자유 텍스트 설명 또는 파일 경로

Examples:
  /req-draft v1 GCP 스캔에 parallel 처리 추가
  /req-draft docs/feature/gcp-parallel v1 input.md
  /req-draft v2
  /req-draft docs/feature/gcp-parallel v2

Workflow:
  v1  →  동료 프롬프트 복사/전달  →  동료가 -CX.md, -G.md 작성  →  v2

Peer Roles:
  Option A: 독립 설계 (동일 요구사항으로 각자 설계)
  Option B: 리뷰 (Claude의 v1 문서를 읽고 리뷰)
```

## Workflow

### Determine version, then branch:

1. **`-h` or `--help`** → Display help above and stop
2. **v1** → Follow "v1: Create Initial Draft" below
3. **v2** → Follow "v2: Synthesize Reviews" below

---

### v1: Create Initial Draft

**Goal**: Transform raw input into a structured requirement draft document.

#### Steps

1. **Parse input**: Read the input text or file. Extract core feature concept, scope, and constraints.

2. **Determine output path**:
   - If path given: use `docs/feature/<path>/`
   - If not: derive slug from feature topic → `docs/feature/<topic-slug>/`
   - Create directory if it doesn't exist

3. **Derive filename**: Use kebab-case from the feature topic → `<feature-slug>.md`
   - Example: "GCP 스캔 성능 개선" → `gcp-scan-performance.md`

4. **Show peer prompts FIRST**: Display the peer prompts immediately so the user can copy and forward to colleagues while Claude works on the draft. This enables parallel work.
   ```
   ══════════════════════════════════════════════════
   📋 동료 에이전트 요청 프롬프트 (복사해서 전달)
   ══════════════════════════════════════════════════

   ── Option A: 독립 설계 (작성자 역할) ──────────

   [Codex] 다음 요구사항을 읽고 너의 관점에서 독립적으로
   설계 문서를 작성해. 참고로 다른 동료도 같은 주제로
   각자 설계 중이야.
   요구사항: <original input summary>
   출력 파일: docs/feature/<path>/<feature-slug>-CX.md

   [Gemini] 다음 요구사항을 읽고 너의 관점에서 독립적으로
   설계 문서를 작성해. 참고로 다른 동료도 같은 주제로
   각자 설계 중이야.
   요구사항: <original input summary>
   출력 파일: docs/feature/<path>/<feature-slug>-G.md

   ── Option B: 리뷰 (리뷰어 역할) ──────────────

   [Codex] docs/feature/<path>/<feature-slug>.md 를 읽고
   리뷰해. 보완할 점, 누락된 부분, 더 나은 접근법을
   docs/feature/<path>/<feature-slug>-CX.md 로 작성해.

   [Gemini] docs/feature/<path>/<feature-slug>.md 를 읽고
   리뷰해. 보완할 점, 누락된 부분, 더 나은 접근법을
   docs/feature/<path>/<feature-slug>-G.md 로 작성해.

   ══════════════════════════════════════════════════
   초안 작성 중...
   ```

5. **Generate document**: Write to `docs/feature/<path>/<feature-slug>.md` using the template in [references/v1-template.md](references/v1-template.md).

6. **Confirm completion**:
   ```
   ══════════════════════════════════════════════════
   DRAFT CREATED (v1)
   ══════════════════════════════════════════════════
   File: docs/feature/<path>/<feature-slug>.md
   Topic: <title>
   ──────────────────────────────────────────────────
   동료 문서 완료 후: /req-draft v2
   ══════════════════════════════════════════════════
   ```

---

### v2: Synthesize Reviews

**Goal**: Read colleague review documents, identify their strengths and gaps in the original, update the original document.

#### Steps

1. **Locate documents**: Find the original and all colleague review files in the target directory.
   ```bash
   # Original: <feature-slug>.md
   # Colleague reviews: <feature-slug>-*.md (e.g., -CX.md, -G.md, -S.md)
   ```
   - If path not specified, scan `docs/feature/` for the most recently modified directory.
   - If multiple originals exist, ask the user which one to update.

2. **Read all documents**: Read the original and every colleague review file.

3. **Analyze colleague contributions**: For each colleague document, determine its nature and extract insights:

   **독립 설계 문서** (작성자 역할로 작성된 경우):
   - **독자적 강점**: 우리가 생각하지 못한 설계 관점이나 구조
   - **공통점**: 여러 에이전트가 동일하게 판단한 부분 (신뢰도 높음)
   - **차별점**: 서로 다른 접근법 (최선의 방안 선택 또는 병합)

   **리뷰 문서** (리뷰어 역할로 작성된 경우):
   - **Strengths**: Ideas, perspectives, or details that improve the original
   - **Gaps identified**: Points the original missed that the colleague caught

   **공통**:
   - **Conflicts**: Areas where colleague disagrees with the original (flag for user decision)

4. **Update the original document**:
   - Preserve the original structure and voice
   - Integrate colleague strengths naturally into relevant sections
   - Add new sections if colleagues identified entirely new areas
   - Add an **Integration Sources** field in the header listing all reviewed documents
   - Add a **피드백 반영 현황** section tracking what was incorporated and from whom

5. **Confirm output**:
   ```
   ══════════════════════════════════════════════════
   DRAFT UPDATED (v2)
   ══════════════════════════════════════════════════
   File: docs/feature/<path>/<feature-slug>.md
   Reviewed: <feature-slug>-CX.md, <feature-slug>-G.md
   ──────────────────────────────────────────────────
   반영 요약:
   - [CX] <key contribution summary>
   - [G]  <key contribution summary>

   ⚠ 충돌 사항 (수동 확인 필요):
   - <conflict description, if any>
   ──────────────────────────────────────────────────
   다음 단계:
   - 충돌 사항 검토 후 최종 확정
   - 정식 REQ 문서로 전환: /req-define <feature description>
   ══════════════════════════════════════════════════
   ```

## Guidelines

- Write all documents in **Korean** (technical terms in English are acceptable)
- Use **kebab-case** for all filenames
- Never overwrite colleague documents — only update the original
- When conflicts exist between colleagues, preserve both perspectives and flag for user
- v2 should be idempotent: running it again re-reads all colleague files and re-synthesizes
