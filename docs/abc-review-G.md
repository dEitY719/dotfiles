# Engineering Team Lead Review (Reviewer: Gemini)

## 1. Situation Analysis & Persona Alignment
*   **Role:** Engineering Team Lead (20+ years exp). Focus on visibility, traceability, and knowledge management.
*   **Current Constraint:** Corporate Security Policy (Proxy) prevents direct usage of AI assistance (Claude Code/Gemini) on internal networks.
*   **Proposed Workflow:** "Air-Gap Bridge" strategy.
    *   **Code:** Synced via Git (Private Repo).
    *   **Knowledge/Status:** Generated externally, synced via Git, manually entered (Copy & Paste) into Internal Jira/Confluence.

## 2. Strategic Review: The "Copy & Paste" Protocol
Your proposed strategy is the most pragmatic approach given the security constraints. As a lead who values "Micro-control" (visibility into details), I endorse this because it ensures **Data Integrity** and **Compliance** while still leveraging AI efficiency.

However, relying solely on ad-hoc "make-jira" requests is risky. We need a **Structured Process**.

### Optimized Workflow Recommendation
Instead of just asking me to generate text to the screen, we will formalize the output into files. This creates a "Transfer Record" in your repo.

1.  **Work (External):** You perform tasks, refactoring, and experiments.
2.  **Documentation (External - AI Assisted):**
    *   You invoke the `make-jira` or `make-confluence` routine.
    *   I (Gemini) analyze the git diffs, file changes, and context.
    *   I write a Markdown file into a specific directory (e.g., `docs/sync_packet/YYYY-MM-DD_TaskID.md`).
3.  **Sync:** You `git push` from External, `git pull` on Internal.
4.  **Ingest (Internal):**
    *   Open the markdown file on the Internal PC.
    *   **Jira:** Copy the "Status Update" section.
    *   **Confluence:** Copy the "Technical Insight" section.
    *   **Evidence:** The markdown file itself serves as a backup log.

## 3. Skill Definition: `make-jira` & `make-confluence`

Since I am an AI agent, "Skills" are essentially standardized Prompt Engineering templates or Scripts we agree to use.

### A. The `make-jira` Protocol
**Trigger:** When you finish a distinct unit of work or need a Weekly Report.
**Output Format:**
```markdown
# [JIRA] Task Summary
**Ticket ID:** [Project-123] (Placeholder)
**Work Log Time:** [X] hours

## Completed Items
*   [x] Refactored `auth_module.py` to support OAuth2.
*   [x] Fixed Bug #402: Null pointer exception in user login.

## Implementation Details (Technical)
*   Replaced deprecated `legacy_hash` with `sha256`.
*   Added unit tests in `tests/test_auth.py` (Coverage +5%).

## Blockers / Risks
*   None at the moment.
```

### B. The `make-confluence` Protocol
**Trigger:** When you solve a complex problem, learn a new pattern, or set up an environment.
**Output Format:**
```markdown
# [Confluence] Title: How to [Topic]

## Context
Briefly explain why this is important for the team.

## Problem Description
What was the issue? (e.g., "Docker container fails to mount volume on Windows")

## Solution / Guide
Step-by-step instructions.
1.  Run command `...`
2.  Modify config `...`

## Code Snippet
(Block of code ready to paste)

## References
*   [Link to official docs]
```

## 4. Next Steps
1.  **Create the Sync Directory:** `mkdir -p docs/sync_packet`
2.  **Execution:** Whenever you want to trigger this, simply tell me: "Run make-jira for the last commit" or "Run make-confluence about the dotfiles setup".

I will act as your "Documentation Officer," preparing these packets so you can be the "Liaison" to the internal system.
