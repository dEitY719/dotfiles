# `docs/.ssot/watched-repos.json` — schema (F-1, issue #1511)

JSON carries no comments, so the schema lives here and the file itself only
carries data plus one `$`-prefixed metadata key.

## Shape

```jsonc
{
  "$doc": { "...": "reserved metadata — see below" },

  "<owner>/<repo>": {
    "verify_skill": "devx:pr-verify-merged",   // required
    "main_checkout": "~/dotfiles",             // optional
    "note": "why this variant"                 // optional, free text
  }
}
```

| Key | Required | Meaning |
|---|---|---|
| `verify_skill` | yes | **Allowlisted**: `devx:pr-verify-merged` or `devx:pr-verify-live`, nothing else. Typed into the new session as its dash form (`/devx-pr-verify-merged <N>`). |
| `main_checkout` | no | Absolute or `~`-relative path of the original checkout to rebase. Omitted → derived from `git rev-parse --path-format=absolute --git-common-dir` with the trailing `/.git` stripped, which resolves the main checkout even when the skill runs inside a linked worktree. |
| `note` | no | Free text for humans. Never read by the skill. |

## Why `verify_skill` is an allowlist, not free text

The value does not label anything — it is interpolated into
`herdr agent prompt` for a session started with
`--dangerously-skip-permissions`, i.e. it is an input to an unattended agent's
prompt. A registry file is editable by anyone who can edit the repo (or, in a
worktree, anyone who can write `$DOTFILES_ROOT`), so the dispatch refuses any
value outside the two known skills with one `[WARN]` and stops **before** the
first herdr mutation — a bad registry never even closes a tab. Adding a third
verification skill means adding it to that allowlist in all three places:
`references/dispatch.sh.md`, `tests/bats/skills/_fixtures/gh_pr_post_merge_verify.sh`,
and this table.

## Reserved keys

Top-level keys beginning with `$` are metadata, never a repo slug — a GitHub
slug is `owner/repo` and cannot start with `$`. The lookup the skill runs is

```
jq -r --arg r "$TARGET_REPO" '.[$r].verify_skill // empty' "$WATCHED_FILE"
```

so a metadata key is only ever reached by a literal `$…` repo argument, and
because `$doc`'s value is an **object** even that answers empty rather than
raising a jq type error. Keep any future metadata key an object for the same
reason.

## Registering a repo

1. Add an `"<owner>/<repo>"` entry with `verify_skill`.
2. Pick the variant by what the repo can prove:
   - **`devx:pr-verify-merged`** — no long-running app. It makes its own fresh
     clone of the merge commit, so the rebase in step 3 is hygiene (the human
     is left on an up-to-date `main`), not a hard precondition.
   - **`devx:pr-verify-live`** — there is a running dev app, and the proof is
     that the *serving checkout* is the target commit. Here the rebase **is**
     the precondition: an un-rebased checkout would have the session verify
     the previous commit and call it proven.
3. Add a row to `docs/.ssot/README.md` only if the index changes; the file is
   already listed there.

Removing an entry is the supported off switch — it restores exactly the
pre-#1511 behavior for that repo, silently.
