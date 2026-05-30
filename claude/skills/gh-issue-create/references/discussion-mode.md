# gh:issue-create — `--as-discussion` parse (Step 1.1)

If `--as-discussion <category>` is present, bind `DISCUSSION_MODE=1` and
`CATEGORY=<value>`. Validate `<value>` against the allow-list
`Ideas` / `Q&A` / `Announcements` / `Lessons` (case-insensitive); on
mismatch, print the four allowed values and **exit 3** without calling
any API. When `DISCUSSION_MODE=1` and the user also supplied `--label`
or `--assignee`, emit a 1-line warning to stderr and drop those flags
(Discussions do not carry labels/assignees):

```
[gh-issue-create] --as-discussion: dropping --label/--assignee (Discussions do not carry these)
```

When `DISCUSSION_MODE` is unset the legacy issue path is unchanged.
