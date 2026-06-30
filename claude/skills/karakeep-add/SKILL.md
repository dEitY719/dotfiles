---
name: karakeep:add
description: >-
  Add a URL to a Karakeep List via REST, creating the List (and any nested
  parent path) on demand. Use when the user runs /karakeep:add,
  /karakeep-add, or asks "이 URL Karakeep <list>에 넣어줘", "북마크를
  github/repository 에 추가", "add <url> to list <path>". Idempotent —
  reuses an existing bookmark for the same URL and an existing List for the
  same name/parent, so re-runs never duplicate. Writes directly to the live
  Karakeep instance (base URL = `.env` `NEXTAUTH_URL`, not localhost) and
  verifies membership after attaching. Respects the Company confidentiality
  boundary (refuses public/personal URLs into `Company` or its children).
  Sister skill of [[karakeep:classify]] — that one suggests a List (default
  dry-run); this one performs the write. Accepts `<url> --list <path>` and
  `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read
metadata:
  model_recommendation:
    tier: sonnet
    reason: "deterministic REST writes, but needs judgment for the Company guardrail and nested-path creation"
    claude: prefer
    non_claude: advisory-only
---

# karakeep:add — URL → List (write path via REST)

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Role

Add `<url>` to the Karakeep List at `<path>`, creating the List (and every
missing parent in a nested `부모/자식` path) first. The write path is pure
REST — `KarakeepClient` in the karakeep-sync project is read/sync only and
has no create/attach methods. Idempotent end to end.

## Step 1: Parse Args + Load Env

Positional `<url>`; required flag `--list <path>` (slash-delimited nesting).
Missing either → print the usage pointer (`Run /karakeep-add -h for usage.`)
and stop.

Load `NEXTAUTH_URL` and `KARAKEEP_API_KEY` from the working directory's
`.env` per `references/rest-mechanics.md` → "Env + base URL". If either is
unset, **fail clearly** — never guess a base URL or hardcode `localhost`.

## Step 2: Company Guardrail

If `<path>` is `Company` or starts with `Company/`, refuse unless the URL is
explicitly company-internal and the user confirmed. Public/personal URLs
into the Company subtree are blocked — see `references/rest-mechanics.md`
→ "Company boundary". This is acceptance-criterion-critical, not advisory.

## Step 3: Resolve / Create the List Path

Walk `<path>` segment by segment from the root, per
`references/rest-mechanics.md` → "Resolve or create a List". For each
segment: look it up under the current parent; reuse its id if present,
else `POST /api/v1/lists` with an emoji `icon` and the running `parentId`.
List membership is preserved by full path, so create parents first.

## Step 4: Resolve / Create the Bookmark

Dedup by `url.rstrip("/")` per `references/rest-mechanics.md` → "Resolve or
create a bookmark". Found → reuse its id. Not found → `POST
/api/v1/bookmarks` `{type:"link", url, title}`.

## Step 5: Attach + Verify

`PUT /api/v1/lists/<list_id>/bookmarks/<bookmark_id>` (idempotent, empty
body on success), then `GET /api/v1/lists/<list_id>/bookmarks` and confirm
the bookmark id is present. Report the final List path, list id, bookmark
id, and a verified/not-verified verdict.

## Step 6: Report

Print a `[OK]` / `[FAIL]` line with the List path, ids, and whether each
List/bookmark was created or reused (proves idempotency). End with the
`Next:` hint: `karakeep:classify <url>` for the suggest flow, or re-run to
confirm the no-op. Error templates: `references/rest-mechanics.md`
→ "Error cases".

## Constraints

- Base URL is always `NEXTAUTH_URL` — never `localhost:3001` (that is the
  `config.yaml` internal value, wrong for live writes).
- Idempotent: never create a duplicate List (same name+parent) or bookmark
  (same `url.rstrip("/")`).
- Never write a public/personal URL into the `Company` subtree.
- This skill only touches the live Karakeep instance — it does not edit the
  karakeep-sync repo or run `karakeep-sync push` (next push materializes).
