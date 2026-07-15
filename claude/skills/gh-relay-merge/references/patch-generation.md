# gh:relay-merge — Patch Generation, Size Cutoff, Artifact Exclusion

Steps 3-4. Runs only after Step 2 confirmed the push is blocked.

## Pre-flight (Step 3): destination divergence sanity check

Resolve the PR's real commit range first. Reuse the `headRefOid` already
captured by Step 1's `gh pr view` (no re-fetch), and resolve `$DEST_DEFAULT`
— the destination's default branch (e.g. `git ls-remote --symref "$REMOTE"
HEAD`) — once:

```bash
HEAD_SHA=$HEAD_REF_OID                                          # from Step 1; no re-fetch
BASE_SHA=$(git merge-base "$REMOTE/$DEST_DEFAULT" "$HEAD_SHA")   # or the PR's recorded base
```

For a merged PR use the merge commit's parents; for an open PR use the
current head and the PR's base. The range is `BASE..HEAD`.

Before generating anything, compare the files this PR touches against the
destination's current default branch:

```bash
# Step 1 already fetched "$REMOTE"; re-fetch only if the branch may have moved.
git diff --name-only "$BASE_SHA" "$HEAD_SHA"        # files the PR changes
# for each, check it exists / is compatible on $REMOTE/$DEST_DEFAULT
```

If a touched file falls into a **structurally-known divergence category** —
env-specific config blocks, files that deliberately differ between the
internal and external variants — warn the user up front:

```
[WARN] <path> is known to diverge between internal/external variants.
Its patch will likely fail `git am` on the destination.
```

Surface these before uploading, so the user can decide, rather than
silently shipping patches that fail on the far side.

## Generate patches (Step 4)

```bash
# Reuse the $tmpdir initialized in Step 2's push-probe — do not re-create it.
git format-patch "$BASE_SHA".."$HEAD_SHA" -o "$tmpdir"
```

One `.patch` file per commit, each independently `git am`-able, numbered so
apply order is unambiguous (`0001-*.patch`, `0002-*.patch`, ...).

## Size cutoff

Named, greppable constant — tune here if empirical limits change:

```bash
RELAY_PATCH_MAX_BYTES=40960   # 40KB. ~35KB known-good, ~62KB known-bad on
                              # the observed gist policy; no confirmed safe
                              # value between them, so 40KB is conservative.
```

For each patch, `wc -c`. Under the cutoff → ship as-is. Over → artifact
exclusion below.

## Generated-artifact exclusion

`--generated-patterns` (comma-separated globs) overrides the built-in
default list:

```
**/generated/**  **/*.generated.*  openapi.json  package-lock.json  *.lock  **/dist/**  **/build/**
```

For an oversized patch, check whether the bulk of its diff is under a
matching path (`git format-patch` reports per-file; or inspect the patch's
`diff --git` headers). If so, regenerate that one commit's patch with those
paths excluded via pathspec:

```bash
git format-patch -1 "$SHA" -o "$tmpdir" -- . \
  ':(exclude)**/generated/**' ':(exclude)*.lock'   # etc., per matched globs
```

Record a regeneration note for each excluded artifact so the destination
can rebuild it — e.g. `openapi.json` → `make codegen`, a lockfile →
`npm install`. These notes go into the apply-guide comment (Step 6).

## No silent truncation

If a patch is **still** over `RELAY_PATCH_MAX_BYTES` after excluding
recognized generated artifacts — or is oversized and *not* attributable to
any known generated pattern — do **not** truncate or split arbitrary code
diffs. Stop and report:

```
[FAIL] <NNNN>-<name>.patch is <size> bytes (> RELAY_PATCH_MAX_BYTES=40960)
and its bulk is not a recognized generated artifact.
Refusing to truncate — arbitrary truncation would corrupt the applied commit.
Options: add its path to --generated-patterns if it IS generated, or split
the origin commit into smaller commits and re-run.
```

Arbitrary content truncation corrupts the commit `git am` reconstructs;
only recognized generated-artifact diffs are ever dropped.
