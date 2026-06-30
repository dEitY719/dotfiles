# karakeep:add — REST mechanics

All calls are plain `curl` against the **live** Karakeep instance. The
karakeep-sync project's `KarakeepClient` is read/sync only — it has no
List-create or attach method, so REST is the correct (and verified) path.

## Env + base URL

Load from the working directory's `.env` (do not hardcode):

```bash
set -a; . ./.env 2>/dev/null; set +a
: "${NEXTAUTH_URL:?NEXTAUTH_URL not set — refusing to guess base URL}"
: "${KARAKEEP_API_KEY:?KARAKEEP_API_KEY not set — cannot authenticate}"
BASE="${NEXTAUTH_URL%/}"
AUTH="Authorization: Bearer ${KARAKEEP_API_KEY}"
```

- **Base URL is `NEXTAUTH_URL`** (e.g. `https://karakeep.tail7f8427.ts.net`),
  reachable from home/internal over tailscale. It is **not** the
  `config.yaml` `localhost:3001` value.
- If either var is unset, fail with the message above — never invent a URL.

## Resolve or create a List

Lists nest via `parentId`. To resolve a slash path like `github/repository`,
start at the root and walk one segment at a time, carrying `parentId`.

```bash
# List all lists once, then match by name + parentId locally.
curl -fsS -H "$AUTH" "$BASE/api/v1/lists" | jq -c '.lists[]'
```

For each segment:
- Match an existing list where `name == <segment>` and `parentId` equals the
  running parent (`null` at the root). Found → reuse `.id`.
- Not found → create it:

```bash
curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' \
  "$BASE/api/v1/lists" \
  -d '{"name":"<segment>","icon":"<emoji>","parentId":<parentId-or-omit>}' | jq -r '.id'
```

`icon` is **required** by the API and must be a single emoji — substitute a
sensible one for `<emoji>` (a folder glyph as default, or a topic-fitting
one). Omit `parentId` (or send `null`) for a root list.
Creating parents first preserves full-path membership. Idempotent: a second
run finds every segment and creates nothing.

## Resolve or create a bookmark

Dedup on the trailing-slash-stripped URL:

```bash
KEY="$(printf '%s' "$URL" | sed 's:/*$::')"   # url.rstrip("/")
```

Search existing bookmarks for one whose URL (also stripped) equals `KEY`;
reuse its id. None → create:

```bash
curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' \
  "$BASE/api/v1/bookmarks" \
  -d '{"type":"link","url":"<url>","title":"<title>"}' | jq -r '.id'
```

`title` may be the URL itself when no better title is known; Karakeep
backfills metadata asynchronously.

## Attach + verify

```bash
# Idempotent; success returns an empty body / 2xx.
curl -fsS -X PUT -H "$AUTH" \
  "$BASE/api/v1/lists/<list_id>/bookmarks/<bookmark_id>"

# Verify membership.
curl -fsS -H "$AUTH" "$BASE/api/v1/lists/<list_id>/bookmarks" \
  | jq -e --arg id "<bookmark_id>" '.bookmarks[] | select(.id==$id)' >/dev/null \
  && echo verified || echo NOT-verified
```

## Reading the live tree on an external host

When REST is awkward or the host is external, read the SQLite DB directly —
the `sqlite3` CLI is not installed, so use Python stdlib:

```bash
python3 - <<'PY'
import sqlite3
db = sqlite3.connect("data/db.db")
for row in db.execute("SELECT id, name, parentId FROM bookmarkLists"):
    print(row)
PY
```

## Company boundary

`Company` and every descendant list form a confidentiality boundary
(CLAUDE.md §4.3). Refuse to attach a public or personal URL anywhere under
`Company/`. Only proceed if the URL is genuinely company-internal **and** the
user confirmed the target. When refusing, name the rule and suggest a
non-Company list instead.

## Error cases

| Situation | Behavior |
|---|---|
| List name already exists under parent | Skip create, reuse existing id (idempotent). |
| URL already bookmarked | Skip create, attach existing bookmark id only. |
| `NEXTAUTH_URL` / `KARAKEEP_API_KEY` unset | Fail clearly, no fallback guess. |
| Public URL → `Company` subtree | Block with a warning; do not write. |
| `curl` non-2xx | Print status + response body, stop; do not retry blindly. |
