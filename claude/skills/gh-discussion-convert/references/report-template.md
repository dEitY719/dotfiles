# Report Template — gh:discussion-convert Step 9

Print exactly one line on success, then the steps summary and the
follow-up hint:

```
[OK] Discussion #<N> -> Issue #<M>: <issue-url>
  steps: comment=<on|off|skip>, lock=<on|off|skip>, close=<on|off|skip>, board=<synced|skipped>
Next: /gh-issue-implement <M>
```

The `steps:` line lets the user tell at a glance which optional
side-effects ran. On failure — show the failing step name and quote the
first stderr line from the helper, mirroring the format used by
[[gh-discussion-create]] Step 5.
