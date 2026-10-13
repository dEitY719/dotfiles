# mcporter/

Converts mcporter's exa server to read `${EXA_API_KEY:-}` instead of a plaintext key (#2106).

## Files

| File | Role |
| --- | --- |
| `setup.sh` | Runs `mcporter_exa_setup` (shell-common/functions/secret_run.sh) when mcporter and jq exist and the config is not yet converted (called by root `./setup.sh`, step `mcporter`, optional) |

Tests: `tests/bats/setup/mcporter_setup.bats` (stubbed `sops` and `mcporter`).

## Behavior

- Never fails the parent setup: every problem is a `ux_warning` + exit 0.
- Idempotent: skips when `~/.mcporter/mcporter.json` already holds the placeholder.
- Needs `EXA_API_KEY` in `.enc.env` and the age key (`senv key import`); without them it warns and leaves the config untouched. Add the key first: `sops-help secrets`.
