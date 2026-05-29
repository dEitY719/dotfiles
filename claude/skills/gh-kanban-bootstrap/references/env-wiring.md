# Step 7 — gh:pr-reply auto-approve env wiring

After board creation `lib/setup.sh` idempotently appends `OWNER/REPO`
into the `GH_PR_REPLY_AUTO_APPROVE_REPOS` CSV in `~/.zshrc.local`, so the
next session passes the `gh:pr-reply` Step 8 solo-repo auto-approve G1
(repo allowlist) guard without manual edits.

Suppress with `--no-auto-approve-env` (e.g. org / collab repos).
