/claude-plugin:structure-refactor — Fix a claude-plugin marketplace repo's structure

Usage:
  /claude-plugin:structure-refactor [repo-path] [--apply] [--mp|--op] [--single|--mono]
  /claude-plugin:structure-refactor help

Arguments:
  [repo-path]   Path to the claude-plugin repo to fix (optional).
                Defaults to the current directory.

Flags:
  --apply              Execute the plan. Without it, the skill is DRY-RUN
                       (prints the plan, writes nothing).
  --mandatory | --mp   Scope = mandatory items M1-M10 only. (default scope)
  --recommended | --op Scope = M1-M10 + recommended R1-R5 fixes (R1 guides via
                       /devx:visualize, R2 placeholder stubs, R4 naming
                       correction, R5 README link backfill). R6-R8 are
                       audit-only WARNs (check surfaces them; refactor skips).
  --single             Force the SINGLE target layout (repo itself is one
                       plugin; marketplace source "./", skills at root
                       skills/<s>/ — no plugins/ directory is created).
  --mono               Force the MONO target layout (repo bundles many
                       plugins; source "./plugins/<name>", skills at
                       plugins/<p>/skills/<s>/). --single / --mono override
                       auto-detection (last one wins).
  --mp and --op together → error.

Layout modes & auto-detection:
  Without a flag the CURRENT layout is detected (same priority as
  /claude-plugin:structure-check):
    1. --single / --mono flag (forces the TARGET mode)
    2. marketplace.json plugins[].source  ("./" => single, "./plugins/.." => mono)
    3. filesystem fallback  (plugins/*/ => mono ; root plugin.json => single)
    4. still ambiguous => defaults to mono, header marks "(추정)"
  Refactor fixes toward the detected mode's golden layout and prints the
  mode in the plan/report header.

Layout conversion is NOT supported (safety guard):
  When --single/--mono names a TARGET mode different from the detected
  CURRENT layout, that is a single<->mono conversion (relocate the whole
  plugin + rewrite the manifest). Refactor does NOT perform it — the plan
  shows a "[convert] ... 현재 미지원" line and --apply stops without writing.
  Conversion is deferred to a follow-up (structure-convert). This guard
  stops refactor from force-restructuring a valid single repo (e.g.
  Superpowers) into mono and breaking upstream compatibility.

Behavior:

  DRY-RUN (default)    Compute current → target diff and print the ordered
                       plan. No file is created, moved, or edited.
  --apply              Run the plan:
                         - create missing dirs (.claude-plugin/,
                           docs/skill-guides/, docs/skill-output/,
                           plugins/<p>/skills/)
                         - move misplaced files with `git mv` (history-safe;
                           falls back to `mv` outside a git repo)
                         - write minimal marketplace.json / plugin.json
                           skeletons from discovered plugin/skill names
                         - inject a missing plugins[].source into an existing
                           marketplace (M7, #1084 install-fail fix): git URL
                           from homepage/repository, else the mode's local path
                         - prune unknown top-level plugin.json fields (M10,
                           #1084 load-fail fix): e.g. a schema-violating skills
                           array; a .bak backup is kept
                         - (--op only) generate R1 per-skill guides by
                           delegating to /devx:visualize (real content; skipped
                           when the file already exists), create R2 usage
                           placeholder stubs, correct R4 naming mismatches,
                           backfill missing R5 README guide+usage links, and
                           auto-activate GitHub Pages (github.com + GHE)

R1 vs R2 boundary (--op):
  R1 guides are real content — delegated to /devx:visualize and written to
  docs/skill-guides/<skill>.html; idempotent (skipped when it already exists),
  and it falls back to a TODO stub when /devx:visualize is unavailable.
  R2 usage samples stay placeholder stubs: an empty file with a TODO header
  pointing at /devx:visualize for a later pass. /devx:excalidraw-diagram is
  never called by this skill.

Safety:
  - GitHub Pages activation and R5 link backfill are soft-fail: a missing token
    scope or unreachable host warns and continues — it never aborts the run.
  - Not a git repo → warning (moves use plain `mv`).
  - Dirty tree → shows dry-run plan; requires explicit --apply to write.
  - Idempotent: an already-standard repo (within scope) is a no-op.

Examples:
  /claude-plugin:structure-refactor                  # dry-run, mandatory scope
  /claude-plugin:structure-refactor --apply          # apply mandatory (= --mp)
  /claude-plugin:structure-refactor --apply --op     # apply mandatory + recommended
  /claude-plugin:structure-refactor --op             # dry-run, recommended scope
  /claude-plugin:structure-refactor ../superpowers --single  # fix toward single layout
  /claude-plugin:structure-refactor . --mono --apply # fix toward mono layout
  /claude-plugin:structure-refactor ../repo --apply
  /claude-plugin:structure-refactor help

Sister skill:
  /claude-plugin:structure-check   — read-only audit (run first, and again
                                      after --apply to verify)
