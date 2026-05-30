# devx:ssh-delegate — Help

Standardize one-shot `ssh-copy-id` key delegation into a manifest-based,
idempotent skill. The manifest (`~/.ssh/delegations.yml`, mode 0600) is the
single source of truth for *which key is installed on which host as which
account*, when it was last verified, and the host fingerprint pinned at first
install.

## Usage

```
/devx:ssh-delegate sync                       # manifest ↔ reality 일치
/devx:ssh-delegate add <user>@<host> [alias]  # 1 항목 추가 + install + verify
/devx:ssh-delegate list [--json]              # 검증 상태 표 출력
/devx:ssh-delegate test [<alias>|--all]       # BatchMode ssh 검증
/devx:ssh-delegate revoke <alias>             # 원격 authorized_keys 에서 키 제거
/devx:ssh-delegate doctor                     # 환경 + manifest health check
-h | --help | help                            # 이 도움말
```

The underlying script is `lib/ssh_delegate.sh` — callable directly:

```
lib/ssh_delegate.sh add bwyoon@12.81.221.129 gpu1-bwyoon
ssh gpu1-bwyoon            # passwordless after one password prompt
```

## Sub-commands

| Command | What it does |
|---|---|
| `sync` | Regenerates the ssh config drop-in, pins first-seen fingerprints, verifies every active alias. Aborts on a fingerprint MISMATCH. |
| `add <user>@<host> [alias]` | Upserts a manifest entry, runs `ssh-copy-id`, pins the fingerprint, regenerates config, verifies. `--dry-run` prints actions only. |
| `list [--json]` | Prints the entry table (alias / user / host / last-verified / state) or JSON. |
| `test [<alias>\|--all]` | `ssh -o BatchMode=yes <alias> true` — no password fallback. |
| `revoke <alias>` | Removes the key line from the remote `authorized_keys`, sets `revoked: true`, regenerates config. |
| `doctor` | Checks identity file, manifest perms, ssh/yq presence, audit-log writability, expired entries. |

## Safety model (3-layer)

- **L1 Identity** — only the manifest's `identity_file` is ever used.
- **L2 Host trust** — first install pins the SHA256 fingerprint. A later
  mismatch is an ALERT that halts `sync`; the skill never auto-re-trusts.
- **L3 Allowlist + audit** — AI ssh always goes through a manifest alias.
  Every event is appended as JSONL to
  `~/.local/state/devx/ssh-delegations.log` (flock-serialized).

See `references/safety-model.md` and `references/revoke-runbook.md`.

## Environment overrides

| Var | Default |
|---|---|
| `DEVX_SSH_MANIFEST` | `~/.ssh/delegations.yml` |
| `DEVX_SSH_AUDIT_LOG` | `${XDG_STATE_HOME:-~/.local/state}/devx/ssh-delegations.log` |
| `DEVX_SSH_CONFIG` | `~/.ssh/config` |
| `DEVX_SSH_CONFIG_DROPIN` | `~/.ssh/config.d/devx-delegations` |
| `DEVX_SSH_BIN` / `DEVX_SSH_COPY_ID_BIN` / `DEVX_SSH_KEYSCAN_BIN` / `DEVX_SSH_KEYGEN_BIN` | `ssh` / `ssh-copy-id` / `ssh-keyscan` / `ssh-keygen` |
| `DEVX_SSH_CONNECT_TIMEOUT` | `5` |
