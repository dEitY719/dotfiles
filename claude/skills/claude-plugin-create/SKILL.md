---
name: claude-plugin:create
description: >-
  Create a new claude-plugin marketplace repo from scratch — build the
  directory structure, copy skills in, write the manifests, git init,
  create the GHES/GitHub repo, and push the initial commit, all in one
  pass. NEVER modifies the source tree (dotfiles etc.) — copy-only. Use
  when the user says "새 플러그인 만들어", "스킬 묶어서 플러그인으로",
  "claude-plugin 신규 생성", "/claude-plugin:create <name>", or any request
  to bundle skills into a new plugin repo. Sister skills:
  `claude-plugin:structure-check` (verify after create),
  `claude-plugin:structure-refactor` (fix structure),
  `claude-plugin:rename-repo` (rename to the team convention).
compatibility:
  tools: Read, Write, Edit, Bash, Glob
metadata:
  model_recommendation:
    tier: sonnet
    reason: "multi-step composition: file writes + git/gh CLI orchestration; moderate complexity, no deep reasoning"
    claude: prefer
    non_claude: advisory-only
---

# claude-plugin Repo Creator

Compose a fresh `claude-plugin-<domain>` marketplace repo end-to-end:
generate the `mono`-layout golden structure, copy skills **without mutating
the source**, write manifests/README, then `git init` → repo create → push.
The "new repo" entry point the three sister skills do not cover.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No filesystem or network calls.

**Stop-on-error policy** — HARD-abort on: Step 1 validation (prefix/naming,
missing `--src`, existing dest), Step 7 `gh auth status` failure, and any
push rejection. Everything else fails loudly without partial cleanup.

## Step 1: Parse & Validate

Positional `<plugin-name>` (required) + optional `[skill ...]` list, plus:

| Option | Description | Default |
|--------|-------------|---------|
| `--src <path>` | skill source directory | `~/dotfiles/claude/skills/` |
| `--dest <path>` | repo creation location | `~/para/project/` |
| `--host <host>` | GitHub host | `github.samsungds.net` |
| `--owner <owner>` | GitHub owner | `byoungwoo-yoon` |
| `--plugin <name>` | plugin key (inner name) | domain part of name |
| `--dry-run` | plan only — no writes/repo/commit | off |
| `-h`/`--help` | print help, stop | — |

Validate: prepend `claude-plugin-` if missing (tell the user) + enforce
lowercase-hyphen naming; abort if `--src` missing or `<dest>/<plugin-name>`
exists (no overwrite — NOT idempotent); infer `[skill ...]` from the
conversation when omitted, else ask (never guess).

## Step 2: Plan (always)

Print the `[PLAN]` block per `references/help.md` → "Plan output" (plugin
name/key, destination, the resolved skill→dest copy map, GH repo, dry-run
flag). If `--dry-run`, stop here — write nothing, create no repo.

## Step 3: Build the Directory Structure

Create the `mono` golden layout under `<dest>/<plugin-name>/`:
`.claude-plugin/marketplace.json`, `plugins/<plugin>/.claude-plugin/plugin.json`,
empty `plugins/<plugin>/skills/`, `docs/skill-guides/`, `docs/skill-output/`,
`README.md`, `LICENSE`, `.gitignore`. May delegate the skeleton dirs to
`claude-plugin:structure-refactor --apply --mandatory`.

## Step 4: Copy Skills (source is read-only)

`cp -r <src>/<skill> <dest>/<plugin-name>/plugins/<plugin>/skills/<skill>` per
skill; re-confirm every source dir is still present and unchanged afterward.
**Never edit, move, delete, or symlink the source.**

## Step 5: Write Manifests, README, LICENSE, .gitignore

Fill the files from `references/manifest-templates.md` and
`references/readme-template.md` (MIT LICENSE, current year), using the
discovered plugin/skill names.

## Step 6: git init & Branch

`git init <dest>/<plugin-name>`, then `git -C <dest>/<plugin-name> checkout -b main`.

## Step 7: Create the Remote Repo (outward-facing — confirm first)

After `GH_HOST=<host> gh auth status` and explicit user confirmation:
`gh repo create <owner>/<plugin-name> --public --description "<desc>"`, then
`git remote add origin git@<host>:<owner>/<plugin-name>.git`. On GHES `gh`
failure, point the user to the web UI.

## Step 8: Initial Commit & Push (confirm first)

`git add .` → `git commit -m "feat: init <plugin-name>"` → after
confirmation, `git push -u origin main`. **Never `git push --force`.**

## Step 9: Verify & Report

Run `claude-plugin:structure-check <dest>/<plugin-name>`, confirm M1-M6 PASS,
and emit the `[OK]` report per `references/help.md` → "Completion report"
(repo URL, skills copied, M1-M6 verdict) plus the next-action hint.

## Constraints

- **Source is copy-only** — never modify/delete/symlink the `--src` tree.
- Abort if `<dest>/<plugin-name>` exists (no overwrite; not idempotent).
- `--dry-run` writes nothing, creates no repo or commit.
- `gh auth status` before any `gh` call; confirm before repo-create + push;
  never `git push --force`.
- Sister skills: `claude-plugin:structure-check` (verify),
  `claude-plugin:structure-refactor` (fix), `claude-plugin:rename-repo`
  (rename). This skill creates.
