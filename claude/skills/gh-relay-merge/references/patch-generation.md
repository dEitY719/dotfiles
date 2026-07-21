# gh:relay-merge — Patch Generation, Size Cutoff, Artifact Exclusion

Steps 3-4. Runs only after Step 2 confirmed the push is blocked.

## Pre-flight (Step 3): destination divergence sanity check

Resolve the real commit range first, then resolve `$DEST_DEFAULT` — the
destination's default branch (e.g. `git ls-remote --symref "$REMOTE" HEAD`)
— once. Where `HEAD_SHA` comes from depends on Step 1's input mode:

```bash
# PR mode:      reuse the headRefOid captured by Step 1's gh pr view (no re-fetch)
# --commits mode: no PR object exists — use the head SHA parsed from <base>..<head>
HEAD_SHA=$HEAD_REF_OID                                          # PR mode
BASE_SHA=$(git merge-base "$REMOTE/$DEST_DEFAULT" "$HEAD_SHA")   # or the PR's recorded base
```

For a merged PR use the merge commit's parents; for an open PR use the
current head and the PR's base. In `--commits <base>..<head>` mode the range
is exactly git's `<base>..<head>` (base excluded, head included) — use it
directly, no `gh pr view`. Either way the range is `BASE..HEAD`.

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

## File-group pre-split (oversized non-artifact commit)

When a patch is **still** over `RELAY_PATCH_MAX_BYTES` after artifact
exclusion **and** the excess is *not* attributable to a recognized
generated-artifact pattern — it's just a large real code change in one
commit — pre-split that single commit into multiple sub-patches by file
group. This runs **before** the no-silent-truncation FAIL below; the FAIL
now fires only when pre-split itself cannot get every sub-patch under the
limit.

1. Compute each file's diff size within the commit (`git format-patch` is
   per-commit, so size per file directly):

   ```bash
   git diff --no-color --no-ext-diff -z --name-only "$SHA"^.."$SHA" |
     while IFS= read -r -d '' f; do
       bytes=$(git diff --no-color --no-ext-diff "$SHA"^.."$SHA" -- "$f" | wc -c)
       printf '%s\t%s\n' "$bytes" "$f"
     done
   ```

2. Greedily bucket files into groups so each group's cumulative patch size
   stays under `RELAY_PATCH_MAX_BYTES` (account for ~1KB of per-patch header
   overhead when bucketing near the limit).

3. Generate one independent sub-patch per group. `git format-patch -1 <SHA>`
   with a pathspec clones the original commit's `From`/`Subject`/date/author
   headers onto each sub-patch (git's default for `-1` + pathspec — verified),
   so every sub-patch stays independently `git am`-able:

   ```bash
   git format-patch -1 "$SHA" -o "$tmpdir" -- <files-in-group>   # per group
   ```

   Number the sub-patches so apply order — relative to each other and to the
   rest of the series — is unambiguous: keep the commit's `NNNN` slot and add
   a sub-index so they sort between it and the next commit, e.g. rename to
   `NNNN-1-<name>.patch`, `NNNN-2-<name>.patch`. `git am` order follows the
   order the apply-guide lists them, so the guide must render them as
   "commit N의 1/2, 2/2" (Step 6 / `references/apply-guide-template.md`) so a
   human applying in order knows they belong to one commit.

A single **file** whose own diff alone exceeds the limit cannot be
file-group-split — fall through to the FAIL below (no arbitrary truncation).

## No silent truncation

If a patch is **still** over `RELAY_PATCH_MAX_BYTES` after excluding
recognized generated artifacts **and** after the file-group pre-split above
— i.e. a single **file's** own diff alone exceeds the limit and cannot be
split further — do **not** truncate or split arbitrary code diffs. Stop and
report:

```
[FAIL] <NNNN>-<name>.patch is <size> bytes (> RELAY_PATCH_MAX_BYTES=40960):
a single file's diff exceeds the limit even after file-group pre-split, and
its bulk is not a recognized generated artifact.
Refusing to truncate — arbitrary truncation would corrupt the applied commit.
Options: add its path to --generated-patterns if it IS generated, or split
the origin commit into smaller commits and re-run.
```

Arbitrary content truncation corrupts the commit `git am` reconstructs;
only recognized generated-artifact diffs are ever dropped, and only
whole-file groups are ever pre-split.
