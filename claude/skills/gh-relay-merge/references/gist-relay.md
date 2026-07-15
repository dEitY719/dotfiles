# gh:relay-merge — Gist Upload (one file per call)

Step 5. Uploads each patch file from Step 4 as its own gist.

## The hard rule: one file, one call, sequential

```bash
for patch in "$tmpdir"/*.patch; do
    gh gist create "$patch" --desc "relay: $(basename "$patch")"
    # capture the returned gist URL for the apply-guide table
done
```

- **Exactly one file per `gh gist create` invocation.** Multi-file gist
  creation (`gh gist create a.patch b.patch ...`) is reported to **always**
  fail under this network policy, regardless of file count — so never batch.
- **Sequential, never parallel.** Parallel uploads risk rate-limit / abuse
  triggers on the same policy. Run one at a time.

## Capturing the raw URL

`gh gist create` prints the gist's web URL. The apply-guide needs the
**raw** URL for `curl … | git am`. Derive it after creation:

```bash
GIST_URL=$(gh gist create "$patch" --desc "...")            # https://gist.github.com/<user>/<id>
GIST_ID=${GIST_URL##*/}
RAW_URL=$(gh api "gists/$GIST_ID" --jq '.files[].raw_url')  # exact file's raw URL
```

Resolve the raw URL from the gist API (`.files[].raw_url`) so it points at
the exact file, rather than hand-constructing it. Record `(order,
description, web URL, raw URL)` per patch for the Step 6 table.

## Failure handling

- **Size-related failure on an individual file** — Step 4's exclusion did
  not clear the cutoff, or a non-artifact file is itself oversized. Report
  which file and stop; do not force it through (no-silent-truncation rule,
  see `references/patch-generation.md`).
- **Transient/network failure** — retry that single upload once after a
  short backoff (same policy as the push probe). Still failing → stop.
- **Any other failure** — report and stop. No automatic retries beyond the
  one transient-error backoff.

On stop, list the gists already created (so the user knows what exists) and
do not proceed to Step 6 with a partial set — a partial apply-guide would
be misleading.

## One-line description per patch

While uploading, keep a human-readable one-line summary for each patch
(from the commit subject) — it becomes the description column in the
apply-guide table so the destination reader knows what each patch does
without opening it.
