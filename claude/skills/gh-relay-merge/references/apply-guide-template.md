# gh:relay-merge — Apply-Guide Comment Template

Step 6. Post this to the destination: a NEW issue (default) or the
`--target-issue <N>` issue/PR if supplied.

## Where to post

- **New issue (default):**

  ```bash
  gh issue create --repo "$DEST_REPO" \
    --title "Relay: origin PR #<N> — <PR title>" \
    --body-file "$tmpdir/apply-guide.md"
  ```

- **Existing target:**

  ```bash
  gh issue comment "$TARGET_ISSUE" --repo "$DEST_REPO" \
    --body-file "$tmpdir/apply-guide.md"
  ```

`--repo "$DEST_REPO"` uses the `owner/repo` resolved in
`references/remote-resolution.md`; `gh` parses both `owner/repo` and URL
forms safely.

## Body template

Fill the placeholders and write to `$tmpdir/apply-guide.md` (outer fence is
`~~~` so the inner ```bash``` blocks nest without breaking it):

~~~markdown
## Relay of origin PR #<N> — <PR title>

Source PR was **<merged|open>** on the internal remote. `git push` to this
remote is proxy-blocked, so its commits are relayed as patches below.

### Setup (destination branch)

**Note:** `<remote-name>` here is the remote name *on the destination
machine* — it may differ from the name used on the machine that ran this
relay (e.g. this side calls it `upstream`, the destination side may call
the same URL `origin`). Substitute whatever name actually resolves to this
repo on the machine applying the guide.

```bash
git fetch <remote-name> <default-branch>
git checkout -b <new-branch-name> <remote-name>/<default-branch>
```

### Apply order

| # | Patch (gist) | Description |
|---|--------------|-------------|
| 1 | [0001-…](https://gist.github.com/<user>/<id>) | <one-line summary> |
| 2 | [0002-…](https://gist.github.com/<user>/<id>) | <one-line summary> |

If a commit was pre-split by file group (`references/patch-generation.md`
→ "File-group pre-split"), its rows look like this instead — each part
lands as its own destination commit (not merged back into one), so keep
them adjacent and in order:

| 2 (commit 2의 1/2) | [0002-1-…](https://gist.github.com/<user>/<id>) | <one-line summary> — split commit, part 1/2 |
| 2 (commit 2의 2/2) | [0002-2-…](https://gist.github.com/<user>/<id>) | <one-line summary> — split commit, part 2/2 |

Omit the split rows when nothing was pre-split.

Apply **in this exact order** (each patch builds on the previous):

```bash
curl -sL <raw-url-0001> | git am
curl -sL <raw-url-0002> | git am
# … one line per patch, in order
```

### Finish (push + PR)

```bash
git push -u <remote-name> <new-branch-name>
gh pr create --repo <owner/repo> --title "<title>" --body "Closes #<N>"
```

### Excluded generated artifacts

The following files were stripped from their patches (too large / generated).
Regenerate them locally after applying:

| Artifact | Regenerate with |
|----------|-----------------|
| openapi.json | `make codegen` |
| package-lock.json | `npm install` |

(Omit this section if nothing was excluded.)

### Verification basis

What was verified on the origin side (from `gh pr view` in Step 1):

- CI: <statusCheckRollup summary — e.g. all checks green>
- Review: <reviewDecision — e.g. APPROVED by N reviewers>
- Origin PR: <origin PR URL>
~~~

## Notes

- The `git am` block uses the **raw** gist URLs captured in
  `references/gist-relay.md`, not the web URLs.
- Keep the apply order identical to the numeric patch order from
  `git format-patch` — out-of-order application breaks `git am`.
- The verification-basis section reuses data already fetched in Step 1; do
  not make extra API calls for it.
- **`--commits` mode** (no origin PR object exists): replace the header
  with `## Relay of commit range \`<base>..<head>\`` and the "Source PR
  was…" line with "Source range is `<base>..<head>` on the internal remote
  (no origin PR)."; omit the "Verification basis" section entirely — there
  is no `gh pr view` data to report.
- **The destination-side remote name may not match this side's.** The
  `<remote-name>` placeholder in "Setup" and "Finish" is resolved on the
  *destination* machine, not here — e.g. this side's `upstream` (github.com)
  may be the destination machine's `origin`. Fill the placeholder with
  whatever name the destination-side reader will actually have configured,
  or leave it as a literal placeholder for them to substitute if unknown.
