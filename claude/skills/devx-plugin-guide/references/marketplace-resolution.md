# Marketplace Resolution — Step 2 detail

Exact-match lookup for `PLUGIN` (and optional `MARKETPLACE`) against
`claude/plugin/plugins.json`'s `plugins` array of `"<plugin>@<marketplace>"`
strings. Never `grep "PLUGIN@"` — a plain substring/suffix grep for `skills`
would also match `example-skills@anthropic-agent-skills`. Use `jq` so only
the plugin-name segment before `@` is compared:

```bash
MATCHES=$(jq -r --arg p "$PLUGIN" \
  '.plugins[] | select(split("@")[0] == $p)' \
  claude/plugin/plugins.json)
```

## Case A — `MARKETPLACE` given explicitly (`<plugin>@<marketplace>`)

Check that the exact string `"$PLUGIN@$MARKETPLACE"` is one of `$MATCHES`.

- Present → installed, proceed to Step 3.
- Absent → not-installed error case (below), with `MARKETPLACE` known.

## Case B — `MARKETPLACE` omitted (bare `<plugin>`)

Count the lines in `$MATCHES`:

- **Zero** → not-installed error case (below), with `MARKETPLACE` unknown.
- **One** → take `MARKETPLACE` from that entry's suffix after `@`. Proceed
  to Step 3.
- **Two or more** — the same plugin name is installed under multiple
  marketplaces (e.g. today's `plugins.json` has both
  `superpowers@claude-plugins-official` and `superpowers@superpowers-dev`).
  **Stop.** Never guess which one the user meant. Print the candidate list
  and ask the user to re-run with an explicit `<plugin>@<marketplace>`:

  ```
  플러그인 <plugin> 이 여러 marketplace에 설치되어 있습니다:
    - <plugin>@<marketplace-1>
    - <plugin>@<marketplace-2>
  재실행: /devx-plugin-guide <plugin>@<marketplace-N>
  ```

## Not-installed error case

- **`MARKETPLACE` known** (Case A, or Case B narrowed by the user's own
  `@marketplace` suffix): look up `claude/plugin/marketplaces.json[MARKETPLACE]`
  for `owner/repo` and print the install instructions block from
  `references/help.md` ("설치 안내") filled in with `<plugin>@<marketplace>` +
  `<owner/repo>`, then **stop** — never run `/plugin install` yourself.
- **`MARKETPLACE` unknown** (Case B, zero matches): there is no `owner/repo`
  to look up — printing a fabricated install command would be a guess. Stop
  with:

  ```
  플러그인 <plugin> 이 claude/plugin/plugins.json 에 없고 marketplace 정보도
  없습니다. 정확한 marketplace를 알고 있다면 <plugin>@<marketplace> 형태로
  재실행하세요.
  ```
