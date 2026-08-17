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
# Instruction — execute only the 3 steps below, in order

**Do not choose a skill. Do not re-investigate. Do not create a separate worktree.**
This comment is a patch-relay apply-guide.

## 1) Create the destination branch

Commands below assume the destination remote is `origin`; substitute your
own remote name if it differs.

```bash
git fetch origin <default-branch>
git checkout -b <new-branch-name> origin/<default-branch>
```

## 2) Apply the patches in this exact order

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

Apply them in this exact order (each patch builds on the previous):

```bash
curl -sL <raw-url-0001> | git am
curl -sL <raw-url-0002> | git am
# … one line per patch, in order
```

## 3) Push and open the PR

```bash
git push -u origin <new-branch-name>
gh pr create --repo <owner/repo> --title "<title>" --body "Closes #<N>"
```

---

## Reference

Check this section only if a command above fails, if a lint/test run reports
a failure after applying, or if you need to regenerate an excluded artifact.

### Known unrelated pre-existing failures

These already failed on the origin side before this change. Do not
re-investigate them; continue.

- `<exact file path 1>`
- `<exact file path 2>`

(Omit this section entirely if none were confirmed on the origin side.)

### Excluded generated artifacts

The following files were stripped from their patches (too large / generated).
Regenerate them locally after applying:

| Artifact | Regenerate with |
|----------|-----------------|
| openapi.json | `make codegen` |
| package-lock.json | `npm install` |

(Omit this section if nothing was excluded.)

### Background

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
- The "Background" section reuses data already fetched in Step 1; do not
  make extra API calls for it.
- **`--commits` mode** (no origin PR object exists): keep the header as-is
  and replace the "Background" intro line with `Source range is
  <base>..<head> on the internal remote (no origin PR).`, dropping the
  CI/Review/Origin-PR bullets — there is no `gh pr view` data to report.
  The "Known unrelated pre-existing failures" section still applies when
  the caller supplied a list.
- **The destination-side remote name may not match this side's** — e.g.
  this side's `upstream` (github.com) may be the destination machine's
  `origin`. Steps 1 and 3 default to the literal `origin` (the
  overwhelmingly common case for a single-remote clone) precisely so the
  reader can copy-paste without editing anything; only override it inline
  if you already know the destination uses a different name. Never leave
  an unresolved `<placeholder>` in those two code blocks — that forces a
  manual edit before every single command, which is the exact friction
  this template exists to remove (#1346 review: an earlier draft used
  `<remote-name>` here and the destination-side reader could not copy-paste
  any of the three commands that referenced it).
