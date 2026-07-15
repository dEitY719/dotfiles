# gh:relay-merge — Push-Capability Probe

Step 2's branch point. The whole skill exists because the network path to
`upstream` is **asymmetric**: fetch works, push is proxy-blocked. But that
block is environment-specific and may not apply, so the skill must never
assume it — it probes first and only falls into relay mode on a *confirmed*
block. If push actually works, the correct answer is the SIMPLE PATH
(delegate to `gh:pr`), not relay.

## The probe

Use a **throwaway ref name** on the remote — never a real branch, and
never a protected/default branch name — and `--dry-run` so nothing is
actually written:

```bash
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
LOCAL=<PR head SHA or local branch>
PROBE_REF="refs/heads/relay-probe-$(date -u +%s)"
git push --dry-run "$REMOTE" "$LOCAL:$PROBE_REF" 2>&1 | tee "$tmpdir/probe.out"
PROBE_RC=${PIPESTATUS[0]}
```

`$tmpdir` is created here — the earliest point it's needed — and reused
by every later step (patch generation, gist upload); no step re-creates it.

`--dry-run` still performs the network negotiation with the remote, so a
proxy block page surfaces here exactly as it would on a real push, without
creating the ref.

## Classifying the result

| Signal | Meaning | Action |
|---|---|---|
| `PROBE_RC == 0` | push would succeed | **SIMPLE PATH** — delegate to `gh:pr`, stop |
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

## One retry with backoff

On an inconclusive result, wait a short backoff and re-probe exactly once:

```bash
sleep 3
git push --dry-run "$REMOTE" "$LOCAL:$PROBE_REF" 2>&1 | tee "$tmpdir/probe2.out"
```

- Second probe `rc == 0` → SIMPLE PATH.
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
