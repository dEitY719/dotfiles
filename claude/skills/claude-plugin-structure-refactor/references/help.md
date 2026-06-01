/claude-plugin:structure-refactor — Fix a claude-plugin marketplace repo's structure

Usage:
  /claude-plugin:structure-refactor [repo-path] [--apply] [--mp|--op]
  /claude-plugin:structure-refactor help

Arguments:
  [repo-path]   Path to the claude-plugin repo to fix (optional).
                Defaults to the current directory.

Flags:
  --apply              Execute the plan. Without it, the skill is DRY-RUN
                       (prints the plan, writes nothing).
  --mandatory | --mp   Scope = mandatory items M1-M6 only. (default scope)
  --recommended | --op Scope = M1-M6 + recommended R1-R5 (placeholder stubs
                       + naming correction + README link backfill).
  --mp and --op together → error.

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
                         - (--op only) create empty R1/R2 placeholder stubs,
                           correct R4 naming mismatches, and backfill missing
                           R5 README guide+usage links (stub level)

Placeholder stub boundary (--op):
  Stubs are empty files with a TODO header only. This skill never calls
  /devx:visualize or /devx:excalidraw-diagram to generate real guide/usage
  content — the stub carries a comment pointing there for a later pass.

Safety:
  - Not a git repo → warning (moves use plain `mv`).
  - Dirty tree → shows dry-run plan; requires explicit --apply to write.
  - Idempotent: an already-standard repo (within scope) is a no-op.

Examples:
  /claude-plugin:structure-refactor                  # dry-run, mandatory scope
  /claude-plugin:structure-refactor --apply          # apply mandatory (= --mp)
  /claude-plugin:structure-refactor --apply --op     # apply mandatory + recommended
  /claude-plugin:structure-refactor --op             # dry-run, recommended scope
  /claude-plugin:structure-refactor ../repo --apply
  /claude-plugin:structure-refactor help

Sister skill:
  /claude-plugin:structure-check   — read-only audit (run first, and again
                                      after --apply to verify)
