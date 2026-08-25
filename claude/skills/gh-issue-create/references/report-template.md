# gh:issue-create — Report (Step 5)

Issue 경로 성공 시:

```
[OK] Issue: #123, URL: https://github.com/owner/repo/issues/123
Next: /gh:issue-implement 123
```

의존성 링크가 하나라도 실패했으면 (NF-1) verdict 줄 앞에 실패한 이슈마다
경고 1줄을 덧붙인다 — 이슈 자체는 정상 생성된 상태다:

```
[WARN] Blocked by #13 링크 실패 — GH UI에서 수동 추가 필요
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
Next: <recovery step — e.g. `gh auth login --hostname $TARGET_HOST`, fix `.gh-issue-defaults.yml`, enable Discussions in repo settings>
```
