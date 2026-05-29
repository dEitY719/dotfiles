# /gh:issue-proceed Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `/gh:issue-proceed` skill at `~/dotfiles/claude/skills/gh-issue-proceed/` per the design at `docs/feature/gh-issue-proceed-skill/design.md`, with full bats test coverage and cross-linked sibling skills.

**Architecture:** Approach A — slim wrapper mirroring `/gh:issue-implement` 6-step shell. Markdown SSOTs at `references/*.md`; executable mirrors at `tests/bats/skills/_fixtures/gh_issue_proceed_*.sh`; bats tests at `tests/bats/skills/gh_issue_proceed_*.bats`.

**Tech Stack:** Bash 5+, Bats (already installed at `~/dotfiles/tests/bats/lib/bats-core/`), `gh` CLI, `jq`, markdown.

---

## Open Question Resolutions (settled)

| Q | Resolution |
|---|---|
| Q1 — Reuse strategy | **COPY** each shared reference (`repo-resolution.md`, `fetch-issue.md`, `claim.md`) from sibling skills. Matches dotfiles convention (see existing `gh-issue-implement/` vs `gh-issue-read/` — they have copies, not symlinks). |
| Q2 — Test convention | `tests/bats/skills/gh_issue_proceed_*.bats` + `tests/bats/skills/_fixtures/gh_issue_proceed_*.sh`. Source-of-truth = markdown; fixtures kept in sync per dotfiles `claim.md` ↔ `claim.sh` precedent. |
| Q3 — STRUCTURED payload | v1 = plain `Skill(gh:commit)` / `Skill(gh:pr)` / `Skill(gh:issue-create)` invocations (composed skills' current contracts). STRUCTURED payload contract deferred to a follow-up issue filed at PR time. |
| Q4 — Step-completion markers | YES — mirror `/gh:issue-implement` pattern. Emit at: `fetch-issue`, `schema-validate`, `execute`, `report`. |

---

## File Structure

### New files (created by this plan)

| Path | Responsibility |
|---|---|
| `claude/skills/gh-issue-proceed/SKILL.md` | 4-step shell + frontmatter + Constraints. ≤ 150 lines. |
| `claude/skills/gh-issue-proceed/references/help.md` | Full `--help` output (verbatim). |
| `claude/skills/gh-issue-proceed/references/repo-resolution.md` | Copy from gh-issue-implement, rename skill ref. |
| `claude/skills/gh-issue-proceed/references/fetch-issue.md` | Copy from gh-issue-implement, rename skill ref. |
| `claude/skills/gh-issue-proceed/references/claim.md` | Copy from gh-issue-implement, rename skill ref. |
| `claude/skills/gh-issue-proceed/references/protocol-schema.md` | 8-section schema + aliases + parser algorithm (SSOT). |
| `claude/skills/gh-issue-proceed/references/preconditions.md` | 4-class detector algorithm + mutation keyword list (SSOT). |
| `claude/skills/gh-issue-proceed/references/execution-flow.md` | Step parser + verb registry + step loop pseudocode (SSOT). |
| `claude/skills/gh-issue-proceed/references/safety-gates.md` | 4-layer gates + `ABSOLUTE_BLOCK_PATTERNS` list (SSOT). |
| `claude/skills/gh-issue-proceed/references/report-format.md` | §6 audit templates. |
| `tests/bats/skills/_fixtures/gh_issue_proceed_schema.sh` | Executable mirror of schema parser. |
| `tests/bats/skills/_fixtures/gh_issue_proceed_preconditions.sh` | Executable mirror of class detector. |
| `tests/bats/skills/_fixtures/gh_issue_proceed_steps.sh` | Executable mirror of step parser. |
| `tests/bats/skills/_fixtures/gh_issue_proceed_safety.sh` | Executable mirror of safety pattern matcher. |
| `tests/bats/skills/gh_issue_proceed_schema.bats` | 5 fixture variants: all-OK / 1-missing / empty / H3-nested / KO-aliases. |
| `tests/bats/skills/gh_issue_proceed_preconditions.bats` | 4 class detection cases. |
| `tests/bats/skills/gh_issue_proceed_steps.bats` | Matrix mode + numbered mode + malformed cases. |
| `tests/bats/skills/gh_issue_proceed_safety.bats` | Positive + negative for each `ABSOLUTE_BLOCK_PATTERNS` entry. |

### Modified files

| Path | Change |
|---|---|
| `claude/skills/gh-issue-implement/SKILL.md` (frontmatter `description`) | Add `Sister skill of [[gh:issue-proceed]] for directive issues.` |
| `claude/skills/gh-issue-read/SKILL.md` (frontmatter `description`) | Add `Output feeds [[gh:issue-implement]] for code-change issues, [[gh:issue-proceed]] for directive issues.` |

---

## Task 1: Scaffold skill directory + SKILL.md skeleton

**Files:**
- Create: `~/dotfiles/claude/skills/gh-issue-proceed/SKILL.md`
- Create: `~/dotfiles/claude/skills/gh-issue-proceed/references/` (empty dir)

- [ ] **Step 1.1: Create directory structure**

```bash
mkdir -p ~/dotfiles/claude/skills/gh-issue-proceed/references
ls ~/dotfiles/claude/skills/gh-issue-proceed/
```
Expected: `references` listed; no other files.

- [ ] **Step 1.2: Write SKILL.md skeleton**

Create `~/dotfiles/claude/skills/gh-issue-proceed/SKILL.md`:

````markdown
---
name: gh:issue-proceed
description: >-
  Read a GitHub directive issue (containing an embedded 8-section
  execution protocol) and proceed end-to-end without human
  intervention — validating the protocol schema, executing the steps
  per-rule, and (when the protocol authorizes) committing, opening
  PRs, filing follow-ups, commenting on or closing the issue. Use
  when the user runs /gh:issue-proceed, /gh-issue-proceed, or asks
  "이 작업지시서대로 진행해", "issue #N 끝까지 자동으로", "#78 진행해".
  Sister of /gh:issue-implement — distinct intent: this skill handles
  verify/triage/analysis/audit "work order" issues, not code-change
  requests. Refuses any issue lacking the 8 required sections (Goal,
  Preconditions, Execution Protocol, Decision Rules, Deliverables,
  Done Criteria, Out of Scope, Safety / Abort). Auto-detects
  read-only vs mutation-required precondition class from issue body.
  Composes with /gh:commit, /gh:pr, /gh:issue-create for write
  actions. Hard-blocks PR merge, force-push, secret leakage, and
  cross-worktree mutation regardless of issue content. Accepts
  `<issue-number> [remote]` and `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, Skill
---

# gh:issue-proceed — Directive Issue → End-to-End Execution

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Parse Args + Repo + Preconditions

(stub — wired in Task 11)

## Step 3: Fetch + Claim + Schema-Validate

(stub — wired in Task 12)

## Step 5: Execute Protocol

(stub — wired in Task 13)

## Step 6: Report + Close

(stub — wired in Task 14)

## Constraints

Read `references/safety-gates.md` Layer 1 before relaxing any of these:
never `gh pr merge`, never force-push, never leak secrets, never
mutate cross-worktree paths, never reopen non-self closed issues.
````

- [ ] **Step 1.3: Verify file**

```bash
wc -l ~/dotfiles/claude/skills/gh-issue-proceed/SKILL.md
```
Expected: 30-50 lines.

- [ ] **Step 1.4: Commit**

```bash
git -C ~/dotfiles add claude/skills/gh-issue-proceed/SKILL.md
git -C ~/dotfiles commit -m "feat(skill): Scaffold /gh:issue-proceed skill directory

T1 of #874 — SKILL.md skeleton with frontmatter + step stubs.
Implementation tasks 2-15 follow."
```

---

## Task 2: Copy shared references from gh-issue-implement

**Files:**
- Create: `~/dotfiles/claude/skills/gh-issue-proceed/references/repo-resolution.md`
- Create: `~/dotfiles/claude/skills/gh-issue-proceed/references/fetch-issue.md`
- Create: `~/dotfiles/claude/skills/gh-issue-proceed/references/claim.md`

- [ ] **Step 2.1: Copy three reference files**

```bash
cp ~/dotfiles/claude/skills/gh-issue-implement/references/repo-resolution.md \
   ~/dotfiles/claude/skills/gh-issue-proceed/references/repo-resolution.md
cp ~/dotfiles/claude/skills/gh-issue-implement/references/fetch-issue.md \
   ~/dotfiles/claude/skills/gh-issue-proceed/references/fetch-issue.md
cp ~/dotfiles/claude/skills/gh-issue-implement/references/claim.md \
   ~/dotfiles/claude/skills/gh-issue-proceed/references/claim.md
```

- [ ] **Step 2.2: Rewrite skill name + step references**

Use `Edit` on each of the 3 files:

In `repo-resolution.md`:
- Replace `gh:issue-implement` → `gh:issue-proceed`
- Replace `Step 3 of the` → `Step 3 of the` (no change — same step number)

In `fetch-issue.md`:
- Replace `gh:issue-implement` → `gh:issue-proceed`

In `claim.md`:
- Replace `gh:issue-implement` → `gh:issue-proceed`

Use `grep -n "gh:issue-implement" claim.md repo-resolution.md fetch-issue.md` to verify zero matches after.

- [ ] **Step 2.3: Commit**

```bash
git -C ~/dotfiles add claude/skills/gh-issue-proceed/references/
git -C ~/dotfiles commit -m "feat(skill): Copy shared references for /gh:issue-proceed

T2 of #874 — repo-resolution / fetch-issue / claim copied from
gh-issue-implement and renamed. COPY strategy per design Q1
(matches existing dotfiles convention)."
```

---

## Task 3: Write `references/help.md`

**Files:**
- Create: `~/dotfiles/claude/skills/gh-issue-proceed/references/help.md`

- [ ] **Step 3.1: Author help content**

````markdown
# gh:issue-proceed — Help

## Usage

```
/gh:issue-proceed <issue-number> [remote]
/gh-issue-proceed <issue-number> [remote]
```

## Arguments

| Arg | Description | Default |
|---|---|---|
| `<issue-number>` | GitHub issue number containing a directive protocol | — |
| `[remote]` | Git remote whose repo owns the issue | `origin` |

## What it does

Reads the issue, validates that the body contains the 8-section
directive schema, executes the embedded protocol end-to-end, and
applies write actions (commit / PR / comment / close / file
follow-up) per the protocol's `Decision Rules`. Refuses if the
schema is incomplete.

## Required issue body sections

`Goal`, `Preconditions`, `Execution Protocol`, `Decision Rules`,
`Deliverables`, `Done Criteria`, `Out of Scope`, `Safety / Abort`.
Aliases listed in `references/protocol-schema.md`.

## Sibling skills

- `/gh:issue-implement` — for code-change issues (not directives).
- `/gh:issue-read` — to inspect an issue before deciding which skill
  to use.

## Hard-blocked actions (regardless of issue body)

- `gh pr merge` (use `/gh:pr-merge`)
- `git push --force` (only `--force-with-lease` with explicit
  `allow: force-with-lease` in §Safety)
- Secret leakage to GitHub
- Cross-worktree mutation
- Reopening a non-self closed issue

## Exit codes

- `0` — success, issue closed
- `1` — schema validation failed; nothing posted to GitHub
- `2` — safety gate triggered; issue kept open with audit comment
- `3` — done criteria not met after protocol exhausted; issue kept open

See `docs/feature/gh-issue-proceed-skill/design.md` for full
behavior spec.
````

- [ ] **Step 3.2: Commit**

```bash
git -C ~/dotfiles add claude/skills/gh-issue-proceed/references/help.md
git -C ~/dotfiles commit -m "feat(skill): Add help.md for /gh:issue-proceed

T3 of #874."
```

---

## Task 4: Write `references/protocol-schema.md` SSOT

**Files:**
- Create: `~/dotfiles/claude/skills/gh-issue-proceed/references/protocol-schema.md`

- [ ] **Step 4.1: Author schema content (~100 lines)**

Translate design §3 verbatim into the SSOT. Include:

1. The 8-section table with aliases (copy from design.md §3.1).
2. The "Empty" definition (50 chars after stripping).
3. The H2/H3 parsing rule.
4. The `## Validator algorithm` section with pseudocode:

````markdown
## Validator algorithm

```
1. body = issue_body_markdown
2. headings = extract_headings(body, levels=[2, 3])
3. for each heading h:
       normalized = lower(strip_numeric_prefix(strip_punctuation(h.text)))
       captures[normalized] = content_until_next_heading(h, body)
4. for each required_section in [goal, preconditions, ..., safety]:
       match = find_first_alias_match(required_section.aliases, captures)
       if no match: missing += [required_section.key]
       else if empty(captures[match]): empty += [required_section.key]
       else if special_rule(required_section) fails: invalid += [required_section.key]
5. if any of missing/empty/invalid: emit error report (design §3.4), exit 1
6. return SectionContent map
```
````

5. Add `## Section content access keys` (so downstream files have a stable contract):

```
goal | preconditions | execution_protocol | decision_rules | deliverables | done_criteria | out_of_scope | safety | background? | references? | track?
```

- [ ] **Step 4.2: Commit**

```bash
git -C ~/dotfiles add claude/skills/gh-issue-proceed/references/protocol-schema.md
git -C ~/dotfiles commit -m "feat(skill): Add protocol-schema.md SSOT

T4 of #874 — 8-section schema with aliases, empty-content rules,
validator algorithm, and stable section content keys."
```

---

## Task 5: Write schema parser fixture (TDD red)

**Files:**
- Create: `~/dotfiles/tests/bats/skills/_fixtures/gh_issue_proceed_schema.sh`

- [ ] **Step 5.1: Write the executable mirror**

````bash
#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_issue_proceed_schema.sh
# Source-of-truth mirror for the validator in
#   claude/skills/gh-issue-proceed/references/protocol-schema.md
# Keep in sync whenever schema rules change.

set -u

# Required section keys + alias regex (case-insensitive, ALT in OR).
gh_issue_proceed_required_sections() {
    cat <<'EOF'
goal|goal|목표
preconditions|preconditions|사전 조건|prerequisites
execution_protocol|execution protocol|execution matrix|실행 절차|steps
decision_rules|decision rules|결정 규칙|branching|decision matrix
deliverables|deliverables|산출물|output|outputs
done_criteria|done criteria|종료 조건|acceptance|acceptance criteria
out_of_scope|out of scope|out-of-scope|범위 밖
safety|safety|safety / abort|abort|안전 규칙|safety rules
EOF
}

# Lowercase + strip numeric prefix (e.g. "5. Deliverables" → "deliverables").
gh_issue_proceed_normalize_heading() {
    local s="$1"
    s="$(printf '%s' "$s" | sed -E 's/^[#[:space:]]+//; s/^[0-9]+\.[[:space:]]*//')"
    printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]]+$//'
}

# Strip whitespace, list markers, code fences for "empty" check.
gh_issue_proceed_content_size() {
    printf '%s' "$1" \
        | sed -E 's/```//g; s/^[-*][[:space:]]+//; s/^[0-9]+\.[[:space:]]+//' \
        | tr -d '[:space:]' \
        | wc -c \
        | tr -d '[:space:]'
}

# Validate a body file. Output: zero lines on OK; one line per error otherwise.
# Exit code: 0 OK, 1 schema-invalid.
gh_issue_proceed_validate_body() {
    local body_file="$1"
    local err_count=0

    while IFS='|' read -r key aliases; do
        # Find heading line containing one of the aliases.
        local found_heading=""
        while IFS= read -r heading_line; do
            local normalized
            normalized="$(gh_issue_proceed_normalize_heading "$heading_line")"
            local IFS_old="$IFS"; IFS='|'
            for alias in $aliases; do
                if [ -n "$alias" ] && printf '%s' "$normalized" | grep -qF "$alias"; then
                    found_heading="$heading_line"
                    break
                fi
            done
            IFS="$IFS_old"
            [ -n "$found_heading" ] && break
        done < <(grep -E '^(##|###) ' "$body_file")

        if [ -z "$found_heading" ]; then
            echo "missing: $key"
            err_count=$((err_count + 1))
            continue
        fi

        # Extract content between this heading and the next H2/H3.
        local content
        content="$(awk -v h="$found_heading" '
            $0 == h {capture=1; next}
            capture && /^(##|###) / {exit}
            capture
        ' "$body_file")"

        if [ "$(gh_issue_proceed_content_size "$content")" -lt 50 ]; then
            # Special-case execution_protocol + done_criteria handled later
            echo "empty: $key"
            err_count=$((err_count + 1))
        fi
    done < <(gh_issue_proceed_required_sections)

    [ "$err_count" -eq 0 ]
}
````

- [ ] **Step 5.2: Verify shellcheck clean**

```bash
shellcheck ~/dotfiles/tests/bats/skills/_fixtures/gh_issue_proceed_schema.sh
```
Expected: no output, exit 0.

- [ ] **Step 5.3: Commit**

```bash
git -C ~/dotfiles add tests/bats/skills/_fixtures/gh_issue_proceed_schema.sh
git -C ~/dotfiles commit -m "test(skill): Add executable mirror for /gh:issue-proceed schema validator

T5 of #874 — bash fixture mirroring protocol-schema.md. Bats suite
in T6 will exercise this fixture."
```

---

## Task 6: Write bats tests for schema validator (TDD green)

**Files:**
- Create: `~/dotfiles/tests/bats/skills/gh_issue_proceed_schema.bats`
- Create: `~/dotfiles/tests/bats/skills/_fixtures/gh_issue_proceed_bodies/all_ok.md`
- Create: `~/dotfiles/tests/bats/skills/_fixtures/gh_issue_proceed_bodies/missing_safety.md`
- Create: `~/dotfiles/tests/bats/skills/_fixtures/gh_issue_proceed_bodies/empty_decision_rules.md`
- Create: `~/dotfiles/tests/bats/skills/_fixtures/gh_issue_proceed_bodies/h3_nested.md`
- Create: `~/dotfiles/tests/bats/skills/_fixtures/gh_issue_proceed_bodies/ko_aliases.md`

- [ ] **Step 6.1: Create fixture issue bodies**

Each fixture is a minimal valid (or intentionally invalid) directive issue body.

`all_ok.md`:
````markdown
## Goal
Build and verify thing X end-to-end within 60 minutes.
## Preconditions
- Backend running on port 8000
- gh CLI authenticated
## Execution Protocol
| # | Step | Command | Expected |
|---|---|---|---|
| 1 | warmup | echo hi | hi |
## Decision Rules
| PASS | continue |
| FAIL | abort_all |
## Deliverables
Final report comment on this issue.
## Done Criteria
- [ ] step 1 PASS
- [ ] final comment posted
## Out of Scope
- DB mutations
- PR merge
## Safety / Abort
- Hard block on secret leakage
- Hard block on force push
````

`missing_safety.md`: identical to `all_ok.md` but with the `## Safety / Abort` section removed entirely.

`empty_decision_rules.md`: identical to `all_ok.md` but `## Decision Rules` heading is followed by no content (next heading immediately).

`h3_nested.md`: like `all_ok.md` but all sections are H3 instead of H2 (e.g. `### Goal`).

`ko_aliases.md`: identical structure but Korean headings (`## 목표`, `## 사전 조건`, `## 실행 절차`, `## 결정 규칙`, `## 산출물`, `## 종료 조건`, `## 범위 밖`, `## 안전 규칙`).

- [ ] **Step 6.2: Write bats suite**

````bash
#!/usr/bin/env bats
# tests/bats/skills/gh_issue_proceed_schema.bats
# Validates the source-of-truth mirror of
#   claude/skills/gh-issue-proceed/references/protocol-schema.md
# Five fixtures exercise: all-OK, missing section, empty section,
# H3-nested, KO aliases.

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_issue_proceed_schema.sh"
    FIXTURE_DIR="${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_issue_proceed_bodies"
}

teardown() { teardown_isolated_home; }

@test "schema: all 8 sections present and well-formed → OK" {
    run gh_issue_proceed_validate_body "$FIXTURE_DIR/all_ok.md"
    assert_success
}

@test "schema: missing 'Safety / Abort' section → fail" {
    run gh_issue_proceed_validate_body "$FIXTURE_DIR/missing_safety.md"
    assert_failure
    assert_output --partial "missing: safety"
}

@test "schema: empty 'Decision Rules' content → fail" {
    run gh_issue_proceed_validate_body "$FIXTURE_DIR/empty_decision_rules.md"
    assert_failure
    assert_output --partial "empty: decision_rules"
}

@test "schema: H3 headings instead of H2 → OK" {
    run gh_issue_proceed_validate_body "$FIXTURE_DIR/h3_nested.md"
    assert_success
}

@test "schema: Korean aliases (목표 / 사전 조건 / ...) → OK" {
    run gh_issue_proceed_validate_body "$FIXTURE_DIR/ko_aliases.md"
    assert_success
}
````

- [ ] **Step 6.3: Run tests, expect green**

```bash
~/dotfiles/tests/bats/lib/bats-core/bin/bats ~/dotfiles/tests/bats/skills/gh_issue_proceed_schema.bats
```
Expected: 5 tests pass. If any fail, edit the fixture (`gh_issue_proceed_schema.sh`) and re-run — do not loosen the test cases.

- [ ] **Step 6.4: Commit**

```bash
git -C ~/dotfiles add tests/bats/skills/gh_issue_proceed_schema.bats \
    tests/bats/skills/_fixtures/gh_issue_proceed_bodies/
git -C ~/dotfiles commit -m "test(skill): Cover /gh:issue-proceed schema validator (5 fixtures)

T6 of #874 — all-OK, missing, empty, H3-nested, KO-aliases."
```

---

## Task 7: Write `references/preconditions.md` SSOT

**Files:**
- Create: `~/dotfiles/claude/skills/gh-issue-proceed/references/preconditions.md`

- [ ] **Step 7.1: Author content (~60 lines)**

Translate design §5.1 verbatim. Include:

- 4-class table (read-only / mutation-required / mixed / verify-only)
- Mutation keyword list (verbatim from design)
- Detection pseudocode:

````markdown
## Class detection algorithm

```
1. If section_content.track == "verify-only": class = verify-only; return.
2. haystack = concat(execution_protocol, decision_rules, deliverables)
3. for kw in MUTATION_KEYWORDS:
       if kw in haystack: mutation = True; break
4. If mutation:
       if "allow: cross-repo:" in section_content.safety: class = mixed
       else: class = mutation-required
   else:
       class = read-only
5. return class
```
```

MUTATION_KEYWORDS = [
    "commit_changes",
    "Skill(gh:commit)",
    "git commit",
    "open_pr",
    "Skill(gh:pr)",
    "gh pr create",
    "queue_doc_patch",
    "신규 파일",
    "new file",
]
````

- [ ] **Step 7.2: Commit**

```bash
git -C ~/dotfiles add claude/skills/gh-issue-proceed/references/preconditions.md
git -C ~/dotfiles commit -m "feat(skill): Add preconditions.md SSOT (4-class detector)

T7 of #874 — verify-only / read-only / mutation-required / mixed
class detection algorithm + MUTATION_KEYWORDS list."
```

---

## Task 8: Write preconditions fixture + bats (TDD)

**Files:**
- Create: `~/dotfiles/tests/bats/skills/_fixtures/gh_issue_proceed_preconditions.sh`
- Create: `~/dotfiles/tests/bats/skills/gh_issue_proceed_preconditions.bats`

- [ ] **Step 8.1: Write fixture shell**

````bash
#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_issue_proceed_preconditions.sh
# Mirror of claude/skills/gh-issue-proceed/references/preconditions.md

set -u

GH_ISSUE_PROCEED_MUTATION_KEYWORDS=(
    "commit_changes"
    "Skill(gh:commit)"
    "git commit"
    "open_pr"
    "Skill(gh:pr)"
    "gh pr create"
    "queue_doc_patch"
    "신규 파일"
    "new file"
)

# Inputs (env):
#   FAKE_TRACK            — "verify-only" or ""
#   FAKE_BODY             — concat of execution_protocol + decision_rules + deliverables
#   FAKE_SAFETY           — safety section content
#
# Output: class name on stdout. Exit 0.
gh_issue_proceed_classify() {
    if [ "${FAKE_TRACK:-}" = "verify-only" ]; then
        echo "verify-only"; return 0
    fi
    local mutation=0
    for kw in "${GH_ISSUE_PROCEED_MUTATION_KEYWORDS[@]}"; do
        if printf '%s' "${FAKE_BODY:-}" | grep -qF "$kw"; then
            mutation=1
            break
        fi
    done
    if [ "$mutation" -eq 1 ]; then
        if printf '%s' "${FAKE_SAFETY:-}" | grep -qF "allow: cross-repo:"; then
            echo "mixed"
        else
            echo "mutation-required"
        fi
    else
        echo "read-only"
    fi
}
````

- [ ] **Step 8.2: Write bats suite**

````bash
#!/usr/bin/env bats
# tests/bats/skills/gh_issue_proceed_preconditions.bats
load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_issue_proceed_preconditions.sh"
}
teardown() { teardown_isolated_home; unset FAKE_TRACK FAKE_BODY FAKE_SAFETY; }

@test "preconditions: verify-only track → verify-only" {
    FAKE_TRACK="verify-only"
    FAKE_BODY="git commit -m foo"   # would otherwise trigger mutation
    run gh_issue_proceed_classify
    assert_output "verify-only"
}

@test "preconditions: no mutation keyword → read-only" {
    FAKE_BODY="gh issue comment 78"
    run gh_issue_proceed_classify
    assert_output "read-only"
}

@test "preconditions: 'git commit' present → mutation-required" {
    FAKE_BODY="step 3: git commit -m 'docs'"
    run gh_issue_proceed_classify
    assert_output "mutation-required"
}

@test "preconditions: mutation + cross-repo allow → mixed" {
    FAKE_BODY="Skill(gh:commit)"
    FAKE_SAFETY="allow: cross-repo: dEitY719/other"
    run gh_issue_proceed_classify
    assert_output "mixed"
}
````

- [ ] **Step 8.3: Run + commit**

```bash
~/dotfiles/tests/bats/lib/bats-core/bin/bats \
    ~/dotfiles/tests/bats/skills/gh_issue_proceed_preconditions.bats
```
Expected: 4 pass.

```bash
git -C ~/dotfiles add claude/skills/gh-issue-proceed/references/preconditions.md \
    tests/bats/skills/_fixtures/gh_issue_proceed_preconditions.sh \
    tests/bats/skills/gh_issue_proceed_preconditions.bats
git -C ~/dotfiles commit -m "test(skill): Cover /gh:issue-proceed precondition class detector

T8 of #874 — 4 cases (verify-only / read-only / mutation-required / mixed)."
```

---

## Task 9: Write `references/execution-flow.md` SSOT

**Files:**
- Create: `~/dotfiles/claude/skills/gh-issue-proceed/references/execution-flow.md`

- [ ] **Step 9.1: Author content (~120 lines)**

Translate design §5.2-5.4. Sections:

1. **Step parsing** — matrix detection (markdown table with header `| # | ... |`), numbered detection (`^### \d+\.` or `^\d+\.`).
2. **Step loop pseudocode** — exact code from design.md §5.2.
3. **Action verb registry** — table from design §5.3 (with file_issue template clarification).
4. **Composition payload** — design §5.4 (note that v1 uses plain Skill() invocation; STRUCTURED is v2 follow-up).
5. **`done_criteria_met` semantics** — exact paragraph from design.

- [ ] **Step 9.2: Commit**

```bash
git -C ~/dotfiles add claude/skills/gh-issue-proceed/references/execution-flow.md
git -C ~/dotfiles commit -m "feat(skill): Add execution-flow.md SSOT

T9 of #874 — step parsing (matrix + numbered), step loop pseudocode,
verb registry, composition payload notes, done-criteria semantics."
```

---

## Task 10: Write step parser fixture + bats (TDD)

**Files:**
- Create: `~/dotfiles/tests/bats/skills/_fixtures/gh_issue_proceed_steps.sh`
- Create: `~/dotfiles/tests/bats/skills/gh_issue_proceed_steps.bats`

- [ ] **Step 10.1: Fixture**

````bash
#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_issue_proceed_steps.sh
# Mirror step parser from execution-flow.md.

set -u

# Detect mode of execution_protocol section content.
# stdin = section content. stdout = "matrix" | "numbered" | "none".
gh_issue_proceed_step_mode() {
    local content
    content="$(cat)"
    if printf '%s' "$content" | grep -qE '^\|.*#.*\|'; then
        echo "matrix"; return
    fi
    if printf '%s' "$content" | grep -qE '^(### |^)[0-9]+\.[[:space:]]'; then
        echo "numbered"; return
    fi
    echo "none"
}

# Count parsed steps. stdin = section content. stdout = integer.
gh_issue_proceed_step_count() {
    local content mode
    content="$(cat)"
    mode="$(printf '%s' "$content" | gh_issue_proceed_step_mode)"
    case "$mode" in
        matrix)
            # Count data rows (table rows excluding header + separator).
            printf '%s' "$content" \
                | grep -cE '^\|' \
                | awk '{print $1 - 2}'   # subtract header + separator
            ;;
        numbered)
            printf '%s' "$content" \
                | grep -cE '^(### |^)[0-9]+\.[[:space:]]'
            ;;
        none)
            echo 0
            ;;
    esac
}
````

- [ ] **Step 10.2: Bats**

````bash
#!/usr/bin/env bats
# tests/bats/skills/gh_issue_proceed_steps.bats
load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_issue_proceed_steps.sh"
}
teardown() { teardown_isolated_home; }

@test "step parser: matrix mode detected from table header" {
    run bash -c 'printf "| # | Step | Cmd |\n|---|---|---|\n| 1 | a | b |\n" | gh_issue_proceed_step_mode'
    assert_output "matrix"
}

@test "step parser: numbered H3 mode detected" {
    run bash -c 'printf "### 1. setup\nfoo\n### 2. run\nbar\n" | gh_issue_proceed_step_mode'
    assert_output "numbered"
}

@test "step parser: plain numbered list mode detected" {
    run bash -c 'printf "1. first\n2. second\n3. third\n" | gh_issue_proceed_step_mode'
    assert_output "numbered"
}

@test "step parser: count matches matrix data rows" {
    run bash -c 'printf "| # | A |\n|---|---|\n| 1 | x |\n| 2 | y |\n| 3 | z |\n" | gh_issue_proceed_step_count'
    assert_output "3"
}

@test "step parser: count matches numbered items" {
    run bash -c 'printf "### 1. a\n### 2. b\n### 3. c\n### 4. d\n" | gh_issue_proceed_step_count'
    assert_output "4"
}
````

- [ ] **Step 10.3: Run + commit**

```bash
~/dotfiles/tests/bats/lib/bats-core/bin/bats \
    ~/dotfiles/tests/bats/skills/gh_issue_proceed_steps.bats
```
Expected: 5 pass.

```bash
git -C ~/dotfiles add tests/bats/skills/_fixtures/gh_issue_proceed_steps.sh \
    tests/bats/skills/gh_issue_proceed_steps.bats
git -C ~/dotfiles commit -m "test(skill): Cover /gh:issue-proceed step parser

T10 of #874 — matrix vs numbered detection + step count."
```

---

## Task 11: Write `references/safety-gates.md` SSOT

**Files:**
- Create: `~/dotfiles/claude/skills/gh-issue-proceed/references/safety-gates.md`

- [ ] **Step 11.1: Author content (~80 lines)**

Translate design §4 verbatim. Critical: define `ABSOLUTE_BLOCK_PATTERNS` as a stable bash array (so the fixture in T12 mirrors exact entries).

````markdown
## Layer 1 — ABSOLUTE_BLOCK_PATTERNS (SSOT)

Each entry is a `pattern_name : regex` pair. The skill scans every
intended command string before execution; first match → abort.

```
ABSOLUTE_BLOCK_PATTERNS=(
    "force_push_default:git push.*--force.*(main|master)"
    "force_push_any:git push.*--force([^-]|$)"
    "rm_rf_outside_pwd:rm[[:space:]]+-rf?[[:space:]]+/"
    "destructive_db:(admin[[:space:]]+reset|DROP[[:space:]]+TABLE|TRUNCATE|DELETE FROM [^W])"
    "pr_merge:gh[[:space:]]+pr[[:space:]]+merge"
    "branch_delete:git[[:space:]]+branch[[:space:]]+-D"
    "reopen_external:gh[[:space:]]+issue[[:space:]]+reopen"
)
```

Secret output scanner (post-execute regex on stdout/stderr):

```
SECRET_OUTPUT_PATTERNS=(
    "secret_env_keyword:(API|AUTH|ACCESS|SECRET|TOKEN|PASSWORD)[_-]?(KEY|TOKEN|SECRET|PASS)?[[:space:]]*=[[:space:]]*[^[:space:]]{8,}"
    "bearer_token:Bearer[[:space:]]+[A-Za-z0-9._-]{20,}"
    "jwt:eyJ[A-Za-z0-9_=-]+\\.eyJ[A-Za-z0-9_=-]+\\.[A-Za-z0-9_.+/=-]+"
)
```
````

Plus paragraphs for Layers 2, 3, 4 from design §4.2-4.4.

- [ ] **Step 11.2: Commit**

```bash
git -C ~/dotfiles add claude/skills/gh-issue-proceed/references/safety-gates.md
git -C ~/dotfiles commit -m "feat(skill): Add safety-gates.md SSOT (4 layers + ABSOLUTE_BLOCK_PATTERNS)

T11 of #874."
```

---

## Task 12: Write safety fixture + bats (TDD)

**Files:**
- Create: `~/dotfiles/tests/bats/skills/_fixtures/gh_issue_proceed_safety.sh`
- Create: `~/dotfiles/tests/bats/skills/gh_issue_proceed_safety.bats`

- [ ] **Step 12.1: Fixture**

````bash
#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_issue_proceed_safety.sh
# Mirror of safety-gates.md Layer 1 + output secret scanner.

set -u

ABSOLUTE_BLOCK_PATTERNS=(
    "force_push_default:git push.*--force.*(main|master)"
    "force_push_any:git push.*--force([^-]|$)"
    "rm_rf_outside_pwd:rm[[:space:]]+-rf?[[:space:]]+/"
    "destructive_db:(admin[[:space:]]+reset|DROP[[:space:]]+TABLE|TRUNCATE|DELETE FROM [^W])"
    "pr_merge:gh[[:space:]]+pr[[:space:]]+merge"
    "branch_delete:git[[:space:]]+branch[[:space:]]+-D"
    "reopen_external:gh[[:space:]]+issue[[:space:]]+reopen"
)

SECRET_OUTPUT_PATTERNS=(
    "secret_env_keyword:(API|AUTH|ACCESS|SECRET|TOKEN|PASSWORD)[_-]?(KEY|TOKEN|SECRET|PASS)?[[:space:]]*=[[:space:]]*[^[:space:]]{8,}"
    "bearer_token:Bearer[[:space:]]+[A-Za-z0-9._-]{20,}"
    "jwt:eyJ[A-Za-z0-9_=-]+\\.eyJ[A-Za-z0-9_=-]+\\.[A-Za-z0-9_.+/=-]+"
)

# stdin = command string. stdout = matching pattern_name or "OK".
gh_issue_proceed_check_command() {
    local cmd
    cmd="$(cat)"
    for entry in "${ABSOLUTE_BLOCK_PATTERNS[@]}"; do
        local name="${entry%%:*}"
        local rx="${entry#*:}"
        if printf '%s' "$cmd" | grep -qE "$rx"; then
            echo "$name"; return 1
        fi
    done
    echo "OK"
}

# stdin = output text. stdout = matching pattern_name or "OK".
gh_issue_proceed_scan_output() {
    local out
    out="$(cat)"
    for entry in "${SECRET_OUTPUT_PATTERNS[@]}"; do
        local name="${entry%%:*}"
        local rx="${entry#*:}"
        if printf '%s' "$out" | grep -qE "$rx"; then
            echo "$name"; return 1
        fi
    done
    echo "OK"
}
````

- [ ] **Step 12.2: Bats — positive + negative per pattern**

````bash
#!/usr/bin/env bats
# tests/bats/skills/gh_issue_proceed_safety.bats
load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_issue_proceed_safety.sh"
}
teardown() { teardown_isolated_home; }

# --- ABSOLUTE_BLOCK_PATTERNS ---

@test "safety: 'git push --force main' → force_push_default" {
    run bash -c 'echo "git push --force origin main" | gh_issue_proceed_check_command'
    assert_failure
    assert_output "force_push_default"
}

@test "safety: 'git push --force feat/x' → force_push_any" {
    run bash -c 'echo "git push --force origin feat/x" | gh_issue_proceed_check_command'
    assert_failure
    assert_output "force_push_any"
}

@test "safety: 'git push --force-with-lease' → OK" {
    run bash -c 'echo "git push --force-with-lease origin feat/x" | gh_issue_proceed_check_command'
    assert_success
    assert_output "OK"
}

@test "safety: 'rm -rf /tmp/foo' → rm_rf_outside_pwd" {
    run bash -c 'echo "rm -rf /tmp/foo" | gh_issue_proceed_check_command'
    assert_failure
    assert_output "rm_rf_outside_pwd"
}

@test "safety: 'rm -rf ./build' → OK" {
    run bash -c 'echo "rm -rf ./build" | gh_issue_proceed_check_command'
    assert_success
}

@test "safety: 'gh pr merge 123' → pr_merge" {
    run bash -c 'echo "gh pr merge 123" | gh_issue_proceed_check_command'
    assert_failure
    assert_output "pr_merge"
}

@test "safety: 'gh pr view 123' → OK" {
    run bash -c 'echo "gh pr view 123" | gh_issue_proceed_check_command'
    assert_success
}

@test "safety: 'git branch -D old' → branch_delete" {
    run bash -c 'echo "git branch -D old" | gh_issue_proceed_check_command'
    assert_failure
    assert_output "branch_delete"
}

@test "safety: 'admin reset' → destructive_db" {
    run bash -c 'echo "uv run python -m src.backend.cli.admin admin reset" | gh_issue_proceed_check_command'
    assert_failure
    assert_output "destructive_db"
}

@test "safety: 'gh issue reopen 99' → reopen_external" {
    run bash -c 'echo "gh issue reopen 99" | gh_issue_proceed_check_command'
    assert_failure
    assert_output "reopen_external"
}

# --- SECRET_OUTPUT_PATTERNS ---

@test "safety: output with 'API_KEY=abcd1234...' → secret_env_keyword" {
    run bash -c 'echo "config: API_KEY=abcd1234efgh5678" | gh_issue_proceed_scan_output'
    assert_failure
    assert_output "secret_env_keyword"
}

@test "safety: output with 'Authorization: Bearer <jwt>' → bearer_token" {
    run bash -c 'echo "Authorization: Bearer abc123def456ghi789jkl" | gh_issue_proceed_scan_output'
    assert_failure
    assert_output "bearer_token"
}

@test "safety: clean output → OK" {
    run bash -c 'echo "All tests pass." | gh_issue_proceed_scan_output'
    assert_success
}
````

- [ ] **Step 12.3: Run + commit**

```bash
~/dotfiles/tests/bats/lib/bats-core/bin/bats \
    ~/dotfiles/tests/bats/skills/gh_issue_proceed_safety.bats
```
Expected: 13 pass.

```bash
git -C ~/dotfiles add claude/skills/gh-issue-proceed/references/safety-gates.md \
    tests/bats/skills/_fixtures/gh_issue_proceed_safety.sh \
    tests/bats/skills/gh_issue_proceed_safety.bats
git -C ~/dotfiles commit -m "test(skill): Cover /gh:issue-proceed safety gates (Layer 1)

T12 of #874 — positive + negative case for each ABSOLUTE_BLOCK_PATTERN
and SECRET_OUTPUT_PATTERN."
```

---

## Task 13: Write `references/report-format.md`

**Files:**
- Create: `~/dotfiles/claude/skills/gh-issue-proceed/references/report-format.md`

- [ ] **Step 13.1: Author content (~80 lines)**

Translate design §6 verbatim. Sections: per-step audit table template, write-action audit template, done-criteria reconciliation rules, outcome table (close vs keep-open vs abort), ai-metrics line.

- [ ] **Step 13.2: Commit**

```bash
git -C ~/dotfiles add claude/skills/gh-issue-proceed/references/report-format.md
git -C ~/dotfiles commit -m "feat(skill): Add report-format.md SSOT

T13 of #874 — per-step audit, write-action audit, done-criteria
reconciliation, outcome table."
```

---

## Task 14: Wire SKILL.md Step 1 — Parse args + Preconditions

**Files:**
- Modify: `~/dotfiles/claude/skills/gh-issue-proceed/SKILL.md`

- [ ] **Step 14.1: Replace Step 1 stub with full content**

````markdown
## Step 1: Parse Args + Repo + Preconditions

Record `START_TS=$(date +%s)` immediately.

Positional args: `<issue-number> [remote]`.

| Arg | Description | Default | Required |
|---|---|---|---|
| `<issue-number>` | GitHub issue number (positive integer) | — | Yes |
| `[remote]` | Git remote whose repo owns the issue | `origin` | No |

Substeps:

1. **Parse + validate args** — missing/invalid → print `Run /gh-issue-proceed -h for usage.` and stop.
2. **Resolve `TARGET_REPO`** per `references/repo-resolution.md`. Missing remote → list `git remote -v` and stop.
3. **Detect precondition class** per `references/preconditions.md` — done after Step 3 fetch since class depends on body content.

The class-conditional checks (worktree, branch ≠ default, clean tree) fire in Step 3 immediately after schema validation succeeds.

Emit `printf '[step:gh-issue-proceed/parse-args] OK\n'`.
````

- [ ] **Step 14.2: Commit**

```bash
git -C ~/dotfiles add claude/skills/gh-issue-proceed/SKILL.md
git -C ~/dotfiles commit -m "feat(skill): Wire /gh:issue-proceed SKILL.md Step 1

T14 of #874."
```

---

## Task 15: Wire SKILL.md Step 3 — Fetch + Claim + Schema-Validate

**Files:**
- Modify: `~/dotfiles/claude/skills/gh-issue-proceed/SKILL.md`

- [ ] **Step 15.1: Replace Step 3 stub**

````markdown
## Step 3: Fetch + Claim + Schema-Validate

1. **Fetch** per `references/fetch-issue.md`. Closed issue → refusal stop.
   Emit `printf '[step:gh-issue-proceed/fetch-issue] OK\n'`.
2. **Block-label guard** per `references/claim.md` 3.2.
3. **Self-assign + Board transition + Depends-on guard** per `references/claim.md` 3.3-3.5 (soft-fail).
4. **Schema-validate** per `references/protocol-schema.md`. Missing/empty section → emit error report (design §3.4 format), exit 1. **No comment posted on the issue.**
   Emit `printf '[step:gh-issue-proceed/schema-validate] OK\n'`.
5. **Precondition class enforcement** — apply per-class rules from `references/preconditions.md`:
   - `read-only` → no further check.
   - `mutation-required` → branch ≠ default, clean tree, in worktree.
   - `mixed` → mutation-required + verify `allow: cross-repo: <owner/repo>` matches target.
   - `verify-only` → force read-only behavior even if mutation keywords found.

   On class/state mismatch: print remediation hint per design §5.1 and stop.
````

- [ ] **Step 15.2: Commit**

```bash
git -C ~/dotfiles add claude/skills/gh-issue-proceed/SKILL.md
git -C ~/dotfiles commit -m "feat(skill): Wire /gh:issue-proceed SKILL.md Step 3

T15 of #874 — fetch + claim + schema-validate + class enforcement."
```

---

## Task 16: Wire SKILL.md Step 5 — Execute Protocol

**Files:**
- Modify: `~/dotfiles/claude/skills/gh-issue-proceed/SKILL.md`

- [ ] **Step 16.1: Replace Step 5 stub**

````markdown
## Step 5: Execute Protocol

Follow the loop in `references/execution-flow.md`:

1. Parse `section_content[execution_protocol]` into ordered steps (matrix or numbered mode).
2. For each step:
   a. `TaskCreate` with `subject="Step <n>: <description>"`.
   b. Pre-execute scan against `references/safety-gates.md` Layer 1. Match → abort all (per §Safety).
   c. Execute the step's commands. Capture stdout + stderr.
   d. Post-execute scan output against `SECRET_OUTPUT_PATTERNS`. Match → abort, do NOT post output anywhere.
   e. Classify result against the issue's `decision_rules`. Unknown class → fail-closed (treat as BLOCKED).
   f. Apply action verb (registry in `execution-flow.md` §Verb registry). Composition calls go through `Skill(gh:commit)` / `Skill(gh:pr)` / `Skill(gh:issue-create)`. Inline `gh` CLI for comment / close / label.
   g. `TaskUpdate` → completed with `metadata={result, classification, action}`.
3. Enforce Layer 4 runtime monitors: per-step timeout (5 min default), global timeout (60 min default), write-action quota (per-type 5 / total 20 unless §Safety raises).

Emit `printf '[step:gh-issue-proceed/execute] OK\n'`.
````

- [ ] **Step 16.2: Commit**

```bash
git -C ~/dotfiles add claude/skills/gh-issue-proceed/SKILL.md
git -C ~/dotfiles commit -m "feat(skill): Wire /gh:issue-proceed SKILL.md Step 5

T16 of #874 — execute loop with safety pre/post scans + composition."
```

---

## Task 17: Wire SKILL.md Step 6 — Report + Close

**Files:**
- Modify: `~/dotfiles/claude/skills/gh-issue-proceed/SKILL.md`

- [ ] **Step 17.1: Replace Step 6 stub**

````markdown
## Step 6: Report + Close

Assemble report per `references/report-format.md`. Sections: per-step audit, write-action audit, done-criteria reconciliation, ai-metrics.

Outcome decision (per design §6.4):

| Condition | Action |
|---|---|
| All `done_criteria` `- [ ]` items matched AND no abort | `gh issue close <PROCEED_N>` + final comment with audit |
| Partial — some criteria unmet | Keep open + final comment with `N/M criteria met` |
| Abort triggered (Layer 1-4) | Keep open + final comment with `[aborted] <layer> <pattern>` |

Append ai-metrics line:

```
[ai-metrics:gh-issue-proceed] ~{ELAPSED} min — write actions: {N}, blocked: {M}
```

Compute `ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))`.

Emit `printf '[step:gh-issue-proceed/report] OK\n'`.
````

- [ ] **Step 17.2: Verify SKILL.md is ≤ 150 lines**

```bash
wc -l ~/dotfiles/claude/skills/gh-issue-proceed/SKILL.md
```
Expected: ≤ 150. If over, move detail to references/.

- [ ] **Step 17.3: Commit**

```bash
git -C ~/dotfiles add claude/skills/gh-issue-proceed/SKILL.md
git -C ~/dotfiles commit -m "feat(skill): Wire /gh:issue-proceed SKILL.md Step 6

T17 of #874 — report + close decision + ai-metrics + step marker."
```

---

## Task 18: Cross-link sibling skills

**Files:**
- Modify: `~/dotfiles/claude/skills/gh-issue-implement/SKILL.md` (frontmatter description)
- Modify: `~/dotfiles/claude/skills/gh-issue-read/SKILL.md` (frontmatter description)

- [ ] **Step 18.1: Edit gh-issue-implement description**

Use `Edit` to append after `... Accepts ... \`-h\`/\`--help\`/\`help\`.`:

```
Sister skill of [[gh:issue-proceed]] for directive (work-order) issues with an embedded execution protocol.
```

- [ ] **Step 18.2: Edit gh-issue-read description**

Use `Edit` to append after `... \`-h\`/\`--help\`/\`help\` to print usage.`:

```
Output feeds [[gh:issue-implement]] for code-change issues or [[gh:issue-proceed]] for directive issues.
```

- [ ] **Step 18.3: Commit**

```bash
git -C ~/dotfiles add claude/skills/gh-issue-implement/SKILL.md \
                    claude/skills/gh-issue-read/SKILL.md
git -C ~/dotfiles commit -m "docs(skill): Cross-link sibling skills with /gh:issue-proceed

T18 of #874."
```

---

## Task 19: Run full test suite + lint

**Files:** none modified.

- [ ] **Step 19.1: Run all new bats tests**

```bash
~/dotfiles/tests/bats/lib/bats-core/bin/bats \
    ~/dotfiles/tests/bats/skills/gh_issue_proceed_schema.bats \
    ~/dotfiles/tests/bats/skills/gh_issue_proceed_preconditions.bats \
    ~/dotfiles/tests/bats/skills/gh_issue_proceed_steps.bats \
    ~/dotfiles/tests/bats/skills/gh_issue_proceed_safety.bats
```
Expected: 27 tests pass (5 + 4 + 5 + 13).

- [ ] **Step 19.2: Run shellcheck on all new fixtures**

```bash
shellcheck ~/dotfiles/tests/bats/skills/_fixtures/gh_issue_proceed_*.sh
```
Expected: no output, exit 0.

- [ ] **Step 19.3: Run repo lint gate**

```bash
mise run lint -C ~/dotfiles 2>&1 | tail -20
```
Expected: green or only pre-existing warnings (not introduced by this PR).

- [ ] **Step 19.4: Existing test suite still green**

```bash
~/dotfiles/tests/test 2>&1 | tail -30
```
Expected: full suite passes. If pre-existing failures, document them in the PR body as not-introduced-by-this-PR.

---

## Task 20: Open PR

**Files:** none.

- [ ] **Step 20.1: Verify branch state**

```bash
git -C ~/dotfiles status
git -C ~/dotfiles log --oneline origin/main..HEAD | head -25
```
Expected: clean tree, ~20 commits ahead of `origin/main`.

- [ ] **Step 20.2: Push latest commits**

```bash
git -C ~/dotfiles push
```
Expected: fast-forward push, no force.

- [ ] **Step 20.3: Open PR**

```bash
gh pr create --repo dEitY719/dotfiles \
  --title "feat(skill): Add /gh:issue-proceed — directive issue executor" \
  --body "$(cat <<'EOF'
## Summary

Adds the `/gh:issue-proceed` skill — a sibling of `/gh:issue-implement` for **directive issues** (work-order issues whose body embeds an 8-section execution protocol). Closes #874.

## What it does

Reads a GitHub directive issue, validates the body against a strict 8-section schema, executes the embedded protocol end-to-end without human intervention, and applies write actions (commit / PR / comment / close / file follow-up) per the protocol's `Decision Rules`.

## Sections enforced

`Goal`, `Preconditions`, `Execution Protocol`, `Decision Rules`, `Deliverables`, `Done Criteria`, `Out of Scope`, `Safety / Abort`. Bilingual aliases (KO/EN) supported.

## Safety

Four-layer gates: absolute prohibitions (force-push, `gh pr merge`, secret leakage, cross-worktree mutation) override any issue body. Layer 2 conditional permissions, Layer 3 pre-flight, Layer 4 runtime monitors (per-step + global timeout, write-action quota).

## Test plan

- 27 new bats tests (`tests/bats/skills/gh_issue_proceed_*.bats`)
  - schema validator (5 fixtures: all-OK, missing, empty, H3-nested, KO-aliases)
  - precondition class detector (4 cases)
  - step parser (5 cases)
  - safety gates (13 cases — positive + negative per pattern)
- shellcheck clean on all new `_fixtures/*.sh`
- Existing test suite still green

## Files

- New: `claude/skills/gh-issue-proceed/SKILL.md` + 9 `references/*.md`
- New: `tests/bats/skills/gh_issue_proceed_*.bats` (4 files) + `_fixtures/*.sh` (4 files) + `_fixtures/gh_issue_proceed_bodies/*.md` (5 fixtures)
- Modified: sibling skill descriptions (`gh-issue-implement`, `gh-issue-read`) cross-link `[[gh:issue-proceed]]`

## Follow-up (not in this PR)

- STRUCTURED payload contract for composed skills (`/gh:commit`, `/gh:pr`, `/gh:issue-create`) — design §5.4, marked as v2 in plan. Will file as a separate issue on merge.

## Design references

- Spec: `docs/feature/gh-issue-proceed-skill/design.md`
- Plan: `docs/feature/gh-issue-proceed-skill/plan.md`
- Tracking issue: #874
EOF
)"
```
Expected: PR URL printed.

- [ ] **Step 20.4: File STRUCTURED-payload v2 follow-up issue**

```bash
gh issue create --repo dEitY719/dotfiles \
  --label "skill,feat,enhancement" \
  --title "[skill] STRUCTURED payload contract for composed skills (v2 follow-up of #874)" \
  --body "$(cat <<'EOF'
## TL;DR

Add an opt-in `STRUCTURED:` / `NO_INTERACTIVE: true` payload contract to `/gh:commit`, `/gh:pr`, `/gh:issue-create`. Marked as design §5.4 v2 follow-up of the `/gh:issue-proceed` skill (#874).

## Why

`/gh:issue-proceed` composes with these three skills. Today it can call them with free-form prompts, but that mixes conversation history with structured action payloads. A formal `STRUCTURED` envelope lets the caller specify exact title/body/labels/etc. without ambiguity, and `NO_INTERACTIVE: true` skips any confirmation prompts so end-to-end execution doesn't stall.

## Acceptance

- [ ] `/gh:commit` accepts `STRUCTURED:` envelope (type, scope, body, files) and respects `NO_INTERACTIVE: true`
- [ ] `/gh:pr` accepts `STRUCTURED:` envelope (title, body, base, draft, NO_INTERACTIVE)
- [ ] `/gh:issue-create` accepts `STRUCTURED:` envelope (title, body, labels, NO_INTERACTIVE)
- [ ] `/gh:issue-proceed` switches its composition calls to use STRUCTURED
- [ ] Bats coverage on each skill's STRUCTURED parsing

## References

- Source: #874 PR (this skill)
- Design: `docs/feature/gh-issue-proceed-skill/design.md` §5.4
EOF
)"
```
Expected: issue URL printed.

- [ ] **Step 20.5: Final report**

Print:

```
[OK] /gh:issue-proceed plan executed end-to-end.
  PR: <url>
  Closes: #874
  Follow-up filed: <url for STRUCTURED v2>
  Tests: 27 bats green, shellcheck clean, repo lint green
```

---

## Self-Review Checklist (mental note for the implementer)

After all tasks complete, verify:

- [ ] Every design §3-6 requirement maps to a Task above (spec coverage).
- [ ] No "TBD" / "TODO" left in any committed file.
- [ ] Function names consistent (`gh_issue_proceed_validate_body`, `gh_issue_proceed_classify`, `gh_issue_proceed_step_mode`, `gh_issue_proceed_step_count`, `gh_issue_proceed_check_command`, `gh_issue_proceed_scan_output`) — no drift between fixtures and bats.
- [ ] All commits link `#874` in the commit message (`T<N> of #874`).
- [ ] PR body references the tracking issue with `Closes #874`.
