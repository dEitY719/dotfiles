# gh:issue-create — Report (Step 5)

Issue 경로 성공 시:

```
[OK] Issue: #123, URL: https://github.com/owner/repo/issues/123
Next: /gh:issue-implement 123
```

Discussion 경로 (`DISCUSSION_MODE=1`) 성공 시 — Discussion URL 만 출력:

```
[OK] Discussion (<category>): https://github.com/owner/repo/discussions/45
Next: /gh-discussion-convert 45   # when decision lands
```

실패 시 (gh stderr 또는 helper stderr 첫 줄을 인용):

```
[FAIL] <stderr first line>
Next: <recovery step — e.g. `gh auth login`, fix `.gh-issue-defaults.yml`, enable Discussions in repo settings>
```
