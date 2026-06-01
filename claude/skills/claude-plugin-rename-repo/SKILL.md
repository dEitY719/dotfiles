---
name: claude-plugin:rename-repo
description: >-
  Rename a claude-plugin marketplace repo to the team naming convention
  (claude-plugin-<domain>). Walks through: env check → name proposal →
  gh repo rename → remote URL update → hardcoded reference scan & fix →
  commit. Destructive steps (rename, push) require user confirmation.
  Use when the user says "rename this plugin repo", "이 레포 이름 바꿔",
  "/claude-plugin:rename-repo <name>".
  Sister skills: `claude-plugin:structure-check`, `claude-plugin:structure-refactor`.
compatibility:
  tools: Read, Bash, Edit, Write, Grep
metadata:
  model_recommendation:
    tier: sonnet
    reason: "multi-step repo rename: git/gh CLI, regex scan, multi-file edit; needs tool orchestration but not deep reasoning"
    claude: prefer
    non_claude: advisory-only
---

# claude-plugin Repo Renamer

Rename an existing `claude-plugin-*` marketplace repo to the team naming
convention `claude-plugin-<domain>`, then fix every hardcoded reference.
The full procedure (the embedded SSOT) lives in `references/playbook.md` —
read it before executing.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No git/gh calls.

## Step 0: Environment + Host Check

- Confirm the current directory is a clone of the target repo: `git remote -v`.
- Resolve `owner/repo` by parsing `git remote get-url <remote>` with a
  host-agnostic pattern (`<protocol>://<host>/<owner>/<repo>.git`) rather
  than depending on `gh` — never hardcode `github.com`, so GHES/self-hosted
  remotes work too.
- Identify whether the remote host is `github.com` or an internal GHES
  host (e.g. `github.our-company.com`) from the remote URL.
- Confirm `gh` is authenticated for that host: `gh auth status`. If the
  target host is missing, tell the user to run `gh auth login --hostname
  <host>` themselves — interactive login cannot be done on their behalf.
- Refuse to work on the default branch; require a feature branch.

## Step 1: Decide the New Name

- If `<new-name>` was passed as an argument, use it verbatim. It must
  include the `claude-plugin-` prefix and follow GitHub repo naming rules
  (lowercase + hyphens only, e.g. `claude-plugin-visuals`) — uppercase or
  underscores can break `gh repo rename` or violate the convention.
- If no argument, inspect the plugin composition
  (`.claude-plugin/marketplace.json` `plugins[]` + `plugins/` dirs) and
  propose 1-2 `claude-plugin-<domain>` names. The user picks the final
  name. Do NOT rename before their choice.

## Step 2: Rename the Repo (DESTRUCTIVE — confirm first)

After the user confirms the name:
`gh repo rename <new-name> --repo <org>/<OLD_REPO> --yes` (add
`--hostname <host>` on GHES). If `gh` fails on GHES, guide the user to the
web UI (Settings → Repository name).

## Step 3: Update the Local Remote URL

- `git remote set-url origin <new repo URL>`.
- Verify: `git remote get-url origin` and
  `git ls-remote --heads origin >/dev/null && echo REMOTE_OK`.

## Step 4: Scan + Fix Hardcoded Old Names

- `git grep -n "<OLD_REPO>"` across tracked files.
- Replace in: `marketplace.json` `name` (1:1 with the new repo name),
  `plugins/<p>/.claude-plugin/plugin.json` `homepage`/`repository`,
  `README.md` title + `/plugin marketplace add <org>/<OLD_REPO>` install
  command, and each skill README's marketplace link/install command.
- Do NOT touch fields whose `source` is a relative path (`./plugins/...`)
  — those are repo-name-independent.
- Confirm `git grep -n "<OLD_REPO>"` returns 0 hits afterward.

## Step 5: Commit (push is separate — confirm first)

- Match the repo's existing git-log style (Conventional Commits). Title
  e.g. `chore: rename repo to <new-name> and update references`; body
  records the why (convention) and the changed-file list.
- Push only after explicit user confirmation.

## Constraints

- Destructive actions (repo rename, push) require user confirmation first.
- Works on both github.com and GHES — identify the host from the remote URL.
- Never edit fields whose value is a relative `source` path.
- Never work directly on the default branch.
- `marketplace.json` `name` must equal the new repo name 1:1.
- Sister skills: `claude-plugin:structure-check` (audit layout),
  `claude-plugin:structure-refactor` (fix layout). This skill renames.
