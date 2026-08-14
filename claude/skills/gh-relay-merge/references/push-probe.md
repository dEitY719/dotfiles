# gh:relay-merge — Push-Capability Probe

Step 2's branch point. The whole skill exists because the network path to
`upstream` is **asymmetric**: fetch works, push is proxy-blocked. But that
block is environment-specific and may not apply, so the skill must never
assume it — it probes first and only falls into relay mode on a *confirmed*
block. If push actually works, the correct answer is the SIMPLE PATH
(delegate to `gh:pr`), not relay.

## Why a real push, not `--dry-run` (incident: 2026-08-14, AgentToolbox)

The probe used to be `git push --dry-run`. On 2026-08-14, in the
AgentToolbox repo, that dry-run probe returned `RC=0` ("push would
succeed") three separate times, but a real (non-dry-run) push of the same
commits was blocked every time with `HTTP 403` (`RPC failed; HTTP 403 curl
22`) — a clean, consistent false negative, not a flaky one-off.

Root cause (best understanding): over git's smart-HTTP protocol,
`--dry-run` only performs the ref-negotiation exchange with the server
(roughly the `info/refs` GET-equivalent phase) — it does not POST any pack
data. This network's proxy block triggers specifically on that POST step
(the `git-receive-pack` request that carries the actual objects), which
`--dry-run` never reaches. So `--dry-run` cannot see the block that a real
push hits, and reports "push would succeed" on a path that is in fact
blocked.

**Fix: probe with a real (non-dry-run) push to a throwaway ref**, and
clean the ref up immediately on success. The tradeoff this accepts: on a
successful probe, a disposable branch exists on the destination remote for
the few seconds between the push and its delete-cleanup, in the (rare)
window where cleanup itself might also fail — see "Cleanup" below. That
side effect is judged acceptable because it is the *only* observable
consequence, it is self-correcting even in the failure case (the ref is
harmless, just needs a manual delete — reported, never silently dropped),
and it is far cheaper than the false-negative it replaces: a false
negative sends the user down the SIMPLE PATH, where the real push
(`gh:pr`) then fails anyway, and the user has to notice that, re-run this
skill, and wait for relay mode from scratch. A real-push probe eliminates
that whole extra round trip.

## The probe

Use a **throwaway ref name** on the remote — never a real branch, and
never a protected/default branch name — and push it **for real**:

```bash
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
LOCAL=<PR head SHA or local branch>
PROBE_REF="refs/heads/relay-probe-$(date -u +%s)"
git push "$REMOTE" "$LOCAL:$PROBE_REF" 2>&1 | tee "$tmpdir/probe.out"
PROBE_RC=${PIPESTATUS[0]}
```

`$tmpdir` is created here — the earliest point it's needed — and reused
by every later step (patch generation, gist upload); no step re-creates it.

This is a real network write. If it succeeds, the destination now has a
`relay-probe-<timestamp>` ref that **must** be deleted immediately — see
"Cleanup on success" below, which is not optional.

## Classifying the result

| Signal | Meaning | Action |
|---|---|---|
| `PROBE_RC == 0` | push succeeded | delete the probe ref (below), then **SIMPLE PATH** — delegate to `gh:pr`, stop |
| Output matches a block signal (below) | confirmed blocked | continue to Step 3 (relay) |
| Any other non-zero (transient/network) | inconclusive | retry once (below) |

### Block signals (confirmed blocked)

Treat only these as a definite block — match against the git/curl error
text captured in `probe.out`:

- `HTTP 403` / `403 Forbidden`
- an HTML block-page marker (a configurable regex, default e.g.
  `block(ed)?|proxy|forbidden|corporate policy|access denied`)

Anything else — connection reset, timeout, DNS hiccup, `Could not resolve
host`, TLS errors — is **inconclusive**, not a confirmed block. Flaky
networks must not produce a false "blocked" positive that pushes the user
into the heavier relay flow unnecessarily.

## Cleanup on success (mandatory, not optional)

The moment `PROBE_RC == 0`, delete the probe ref before doing anything
else — do not defer this to Step 7 or leave it for later:

```bash
git push "$REMOTE" --delete "$PROBE_REF" 2>&1 | tee "$tmpdir/probe-cleanup.out"
CLEANUP_RC=${PIPESTATUS[0]}
```

- `CLEANUP_RC == 0` — proceed to SIMPLE PATH silently (the ref is gone,
  nothing to report).
- `CLEANUP_RC != 0` — retry the delete exactly once after a short pause.
  If it fails again, **do not swallow this** — report to the user plainly:
  "destination `$REMOTE` still has branch `$PROBE_REF` — please delete it
  manually" — then continue to the SIMPLE PATH anyway (the leftover ref
  does not block anything functionally, it is just clutter that needs a
  human to clear).

## One retry with backoff

On an inconclusive result, wait a short backoff and re-probe exactly once
(also a real push, same throwaway-ref discipline):

```bash
sleep 3
git push "$REMOTE" "$LOCAL:$PROBE_REF" 2>&1 | tee "$tmpdir/probe2.out"
```

- Second probe `rc == 0` → run "Cleanup on success" above, then SIMPLE PATH.
- Second probe shows a block signal → relay mode.
- Second probe still inconclusive → **treat as not-blocked** and take the
  SIMPLE PATH. Rationale: relay mode has irreversible side effects (public
  gists, a destination issue comment); do not trigger it on ambiguous
  evidence. If the subsequent `gh:pr` push then genuinely fails, the user
  can re-run this skill, and the now-consistent block will be confirmed.

## SIMPLE PATH delegation

When push works, hand off to `gh:pr` (or an equivalent normal branch push
+ PR creation) for the destination remote and stop. Note in the Step 8
report that the simple path was used and relay mode was skipped. Do not
generate patches or create any gist.
