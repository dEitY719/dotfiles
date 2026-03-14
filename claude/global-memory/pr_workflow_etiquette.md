---
name: PR workflow etiquette - always reply to review comments
description: When PR receives comments and you make fixes, always reply to acknowledge feedback. This is standard code review courtesy, applies across all projects.
type: feedback
---

## Rule: Always Reply to PR Review Comments When Fixing Issues

**Do:** When reviewers (Gemini, Sourcery, etc.) comment on a PR and you make fixes in response, always add a reply comment acknowledging the feedback and confirming what you changed.

**Why:** Standard code review etiquette. It closes the feedback loop, shows you took the review seriously, and helps reviewers track whether their feedback was implemented correctly. Without replies, reviewers can't tell if issues were addressed or ignored.

**How to apply:**
1. After creating/updating a PR, check for review comments with `gh pr view <PR> --comments`
2. If comments exist, read them thoroughly
3. If you make code changes in response, commit and push those changes
4. **Always** add a reply comment (example: "Applied both suggestions: 1. Removed X per guidelines 2. Fixed Y in template. Changes pushed.")
5. Include concrete details about what was changed (not generic "fixed it" messages)

**Example workflow:**
```
1. gh pr create → PR #11
2. Gemini comments: "Remove README.md" + "Fix subtitle heading"
3. You: git rm README.md; edit SKILL.md; git push
4. You: gh pr comment 11 --body "Applied both suggestions: ..."  ← THIS STEP IS REQUIRED
```

Skipping step 4 leaves reviewers wondering if you saw or agree with their feedback.
