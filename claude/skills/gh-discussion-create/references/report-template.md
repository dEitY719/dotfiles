# Report Template — gh:discussion-create Step 5

On success:

```
[OK] Discussion (<category>): <url>
Next: /gh-discussion-convert <discussion-number>   # when decision lands
```

On failure — quote the first stderr line verbatim:

```
[FAIL] <gh stderr first line>
Next: <recovery — e.g. enable Discussions in repo settings, gh auth refresh>
```

Routing-guard refusal (Step 2.1) prints its own message from
`references/scope-guard.md` and skips Steps 3-5.
