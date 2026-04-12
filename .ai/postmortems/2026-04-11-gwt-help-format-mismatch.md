# Postmortem: gwt-help Format Mismatch

## Date
2026-04-11

## Incident
`gwt-help` summary format was delivered in legacy flat `ux_info` style, while `git-help` used the standard template (`Usage` + `ux_bullet`/`ux_bullet_sub`).

## Impact
- Output consistency between help commands was broken.
- User had to report mismatch manually.

## Root Cause
1. Validation focused on function behavior and line-count policy, but not summary-template parity.
2. No automated guard existed to reject legacy flat summary text (`sections: ...`) for `gwt-help`.

## Corrective Actions
1. Added explicit summary-template rule to `docs/standards/command-guidelines.md`.
2. Added integration test `test_gwt_help_summary_uses_standard_template` to block regression.
3. Refactored `gwt_help` to SSOT structure (`_gwt_help_rows_*`, `--list`, `--all`).

## Prevention Checklist (Mandatory for help-command changes)
1. Confirm default output uses `Usage` + `ux_bullet` + `ux_bullet_sub`.
2. Reject flat legacy summary patterns like `ux_info "sections: ..."` in review.
3. Run `pytest tests/integration/test_help_compact_policy.py -q` before reporting done.
4. Validate in both shells with the target repo root explicitly set:
   - `DOTFILES_ROOT=<repo> zsh -lc 'source <repo>/zsh/main.zsh; gwt_help'`
   - `DOTFILES_FORCE_INIT=1 DOTFILES_ROOT=<repo> bash -lc 'source <repo>/bash/main.bash; gwt_help'`
