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

Compose a fresh `claude-plugin-<domain>` marketplace repo end-to-end: generate
the `mono`-layout golden structure, copy skills **without mutating the
source**, write manifests/README, then `git init` → repo create → push — the
"new repo" entry point the three sister skills do not cover.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output it
verbatim, then stop. No filesystem or network calls.

**Stop-on-error** — HARD-abort on: Step 1 validation (prefix/naming, missing
`--src`, existing dest), Step 7 `gh auth status` failure, and any push rejection. Everything else fails loudly without partial cleanup.

## Step 1: Parse & Validate

Read `references/options.md` for the full flag/argument table and validation
rules. In short: `<plugin-name>` (required) + optional `[skill ...]`, flags
`--src/--dest/--host/--owner/--plugin/--dry-run/-h`. Prepend `claude-plugin-` if
missing, enforce lowercase-hyphen naming, abort if `--src` missing or dest
exists (NOT idempotent), infer skills from chat else ask.

## Step 2: Plan (always)

Print the `[PLAN]` block per `references/help.md` → "Plan output" (plugin
name/key, destination, skill→dest copy map, GH repo, dry-run flag). If
`--dry-run`, stop here — write nothing, create no repo.

## Step 3: Build the Directory Structure

Create the `mono` golden layout under `<dest>/<plugin-name>/` — see
`references/options.md` → "Golden `mono` layout" for the full tree. May
delegate the skeleton dirs to `claude-plugin:structure-refactor --apply
--mandatory`.

## Step 4: Copy Skills (source is read-only)

`cp -r <src>/<skill> <dest>/<plugin-name>/plugins/<plugin>/skills/` per skill —
copy **into** the parent `skills/` dir, never target `skills/<skill>` (nests to
`skills/<skill>/<skill>/`). Re-confirm each source dir unchanged afterward.
**Never edit, move, delete, or symlink the source.**

## Step 5: Write Manifests, README, LICENSE, .gitignore

Fill from `references/manifest-templates.md` and
`references/readme-template.md` (MIT LICENSE, current year), using the
discovered plugin/skill names.

## Step 6: git init & Branch

`git init <dest>/<plugin-name>`, then `git -C <dest>/<plugin-name> checkout -B main` (`-B` not `-b` — Git may already default to `main`, where `-b` fails).

## Step 7: Create the Remote Repo (outward-facing — confirm first)

After `GH_HOST=<host> gh auth status` and explicit confirmation: `gh repo
create <owner>/<plugin-name> --public --description "<desc>"`, then `git remote
add origin git@<host>:<owner>/<plugin-name>.git`. On GHES `gh` failure, point to the web UI.

## Step 8: Initial Commit & Push (confirm first)

`git add .` → `git commit -m "feat: init <plugin-name>"` → after confirmation,
`git push -u origin main`. **Never `git push --force`.**

## Step 9: Verify & Report

Run `claude-plugin:structure-check <dest>/<plugin-name>`, confirm M1-M9 PASS,
emit the `[OK]` report per `references/help.md` → "Completion report" (repo
URL, skills copied, M1-M9 verdict) plus the next-action hint.

## Constraints

- **Source is copy-only** — never modify/delete/symlink `--src`. Abort if dest
  exists (not idempotent); `--dry-run` writes nothing. `gh auth status` before
  any `gh` call; confirm repo-create + push; never force-push.
- Sisters: `structure-check` (verify) · `structure-refactor` (fix) ·
  `rename-repo` (rename). This skill creates.
