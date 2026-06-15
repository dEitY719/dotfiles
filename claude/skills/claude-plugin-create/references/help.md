/claude-plugin:create — Create a new claude-plugin marketplace repo from scratch

Usage:
  /claude-plugin:create <plugin-name> [skill ...] [--src <path>] [--dest <path>]
                        [--host <ghes-host>] [--owner <owner>] [--plugin <name>] [--dry-run]
  /claude-plugin:create help

Arguments:
  <plugin-name>   Repo name in `claude-plugin-<domain>` form (required).
                  Missing prefix is auto-prepended (you are told). Lowercase
                  + hyphens only — GitHub repo naming rules.
  [skill ...]     Skill directory names to copy (space-separated). Omitted →
                  inferred from the conversation; if not inferable, you are
                  asked for the list (never guessed).

Flags:
  --src <path>    Skill source directory.   default ~/dotfiles/claude/skills/
  --dest <path>   Where the repo is created. default ~/para/project/
  --host <host>   GitHub host.               default github.samsungds.net
  --owner <owner> GitHub owner.              default byoungwoo-yoon
  --plugin <name> Plugin key (inner name).   default = domain part of
                  <plugin-name>  (claude-plugin-harness → harness)
  --dry-run       Print the plan only — no files, no repo, no commit.
  -h | --help     Print this help and stop. No filesystem or network calls.

Plan output (Step 2, always printed):
  [PLAN] claude-plugin:create
    Plugin name : claude-plugin-harness
    Plugin key  : harness
    Destination : ~/para/project/claude-plugin-harness/
    Skills to copy (N):
      ~/dotfiles/claude/skills/<skill>  → plugins/harness/skills/<skill>
      ...
    GH repo     : github.samsungds.net/byoungwoo-yoon/claude-plugin-harness
    Dry-run     : off
  (--dry-run stops here.)

Behavior (mono golden layout):
  1. Parse & validate (prefix, --src exists, dest not present, skill list).
  2. Print the plan (stop if --dry-run).
  3. Build the structure: .claude-plugin/marketplace.json,
     plugins/<plugin>/.claude-plugin/plugin.json, plugins/<plugin>/skills/,
     docs/skill-guides/, docs/skill-output/, README.md, LICENSE, .gitignore.
  4. Copy each skill (cp -r). Source is RE-VERIFIED unchanged afterward.
  5. Write manifests + README + LICENSE + .gitignore from templates.
  6. git init + checkout -b main.
  7. gh repo create (after gh auth status + user confirmation).
  8. git add + commit "feat: init <plugin-name>" + push (after confirmation).
  9. claude-plugin:structure-check → confirm M1-M6 PASS.

Completion report (Step 9):
  [OK] claude-plugin:create
    Repo  : https://<host>/<owner>/<plugin-name>
    Skills: N copied
    Check : M1-M6 PASS
    Next  : /claude-plugin:structure-check <dest>/<plugin-name>  (re-verify)
            docs/skill-guides/ 시각 가이드 추가 → /devx:visualize

Safety:
  - Source (--src) is COPY-ONLY — never modified, moved, deleted, symlinked.
  - <dest>/<plugin-name> already exists → ABORT (no overwrite; not idempotent).
  - Remote repo creation and push are outward-facing — confirmed before each.
  - gh auth status is checked before any gh call; never git push --force.

Examples:
  /claude-plugin:create claude-plugin-harness skill-check skill-create
  /claude-plugin:create harness skill-check --dry-run
  /claude-plugin:create claude-plugin-visuals devx-visualize --owner acme --host github.com
  /claude-plugin:create help

Sister skills:
  /claude-plugin:structure-check     — read-only audit (run after create)
  /claude-plugin:structure-refactor  — fix an existing repo's structure
  /claude-plugin:rename-repo         — rename a repo to the team convention
