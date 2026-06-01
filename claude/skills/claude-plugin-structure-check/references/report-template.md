# claude-plugin:structure-check — Report Template

Use this exact format when outputting the audit report.

```
claude-plugin structure check — <repo-path>
  plugins: <p1> / <p2>   skills: <count>   (git: yes|no)

[필수]
 PASS  M1 .claude-plugin/marketplace.json (유효)
 PASS  M2 plugins/ — 1 plugin (visuals)
 FAIL  M3 plugins/visuals/.claude-plugin/plugin.json 없음
 FAIL  M4 plugins/visuals/skills/visualize/SKILL.md 없음
 PASS  M5 docs/skill-guides/, docs/skill-output/
 PASS  M6 README.md

[권장]
 WARN  R1 docs/skill-guides/visualize.html 없음
 N/A   R2 (스킬 없음 — 평가 대상 없음)
 PASS  R3 README.md 가 docs/ 로 링크 (Simple)
 PASS  R4 명명 일관성 (claude-plugin:structure-check ↔ 디렉터리)
 WARN  R5 README 에 excalidraw-diagram usage 링크 누락

요약: FAIL (필수 2, 권장 2, N/A 1)
→ Fix: /claude-plugin:structure-refactor <repo-path>  (먼저 dry-run, 이후 --apply)
```

## Layout rules

- One line per item: `<RESULT>  <ID> <subject> <note>`.
- `<RESULT>` is one of `PASS` / `WARN` / `FAIL` / `N/A` (uppercase),
  left-padded so the IDs align.
- `[필수]` block lists M1-M6 in order; `[권장]` block lists R1-R5 in order.
- R5 is per-skill: when more than one skill misses a link, emit one R5 line
  naming the first offender (or summarize `<n>개 스킬`); a clean repo → PASS,
  no skills → N/A.
- Header line names the discovered plugins and total skill count — proof
  the scan was dynamic, not hard-coded.

## Summary line

`요약: <VERDICT> (필수 <fail#>, 권장 <warn#>, N/A <na#>)`

- `<VERDICT>`: `FAIL` if any M failed; else `WARN` if any R warned; else
  `PASS`.
- Counts: `필수` = number of FAILs, `권장` = number of WARNs, `N/A` =
  number of N/A rows. Omit a count that is zero except keep `필수`/`권장`
  for readability.

## Next-action hint

Emit **only** when the verdict is FAIL or WARN:

`→ Fix: /claude-plugin:structure-refactor <repo-path>  (먼저 dry-run, 이후 --apply)`

When the verdict is PASS, end with a single line and no hint:

`요약: PASS — 표준 구조 준수`
