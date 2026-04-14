# Routing — When to decline and where to send the user instead

`docs/learnings/` is one home among several for technical writing in this
repo. A learning is the **smallest unit**: a 50–80 line snippet pulled
from a single concrete experience. If the candidate is bigger, more
formal, or for a different audience, refuse and route.

## Neighbor-directory map

| Material | Belongs in | Why it's not a learning |
|---|---|---|
| Long-form tech doc, hundreds of lines | `docs/technic/` | learning is a 50–80 line snippet, not a manual |
| Project SSOT / decision record / policy | `docs/standards/` | standards are normative ("we do X"), learnings are experiential ("we discovered X works") |
| Feature design bundle (multi-file, diagrams) | `docs/feature/<name>/` | feature dirs hold many artifacts together; learnings are single files |
| AI behavior instructions | `claude/skills/<name>/SKILL.md` (English) | learnings are for human teammates; SKILL files are for AI |
| User preference / collaboration style | `memory/` (auto-memory) | memory is private to Claude sessions, learnings are public |

If a candidate fits one of these rows, decline the write and tell the
user the right home in one sentence.

## Sibling write-* skills (same `~/dotfiles/claude/skills/`, different output target)

These are the other "write" skills the user has installed. Hand off to
them when the request is clearly their territory — don't try to bend
write-insight to cover them.

| Skill | Output target | Use it when |
|---|---|---|
| `write-blog-dev-learnings` | `~/para/archive/playbook/docs/dev-learnings/` | User wants a narrative "삽질" blog post in entertaining tone |
| `write-rca-doc` | `~/para/archive/rca-knowledge/` | User wants a formal RCA / postmortem with Jekyll frontmatter |
| `write-task-history` | daily task list file | User wants JIRA ticket text or PR description draft from session work |

The discriminator is **where the file lands**. write-insight always
writes inside the **current repo's** `docs/learnings/`; the siblings
write to `~/para/archive/` or task lists. If the user has any doubt,
confirm the destination before drafting.

## Decline phrasing template

When refusing, name the right home explicitly so the user can pivot:

> 이 내용은 learnings (`docs/learnings/`) 보다는 **`<target>`** 에 더 맞을 것
> 같습니다 — 이유: `<one-line reason from the table above>`. 거기로 작성을
> 진행할까요?
