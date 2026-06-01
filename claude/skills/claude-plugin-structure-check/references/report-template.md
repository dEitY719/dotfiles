# claude-plugin:structure-check — Report Template

Use this exact format when outputting the audit report.

### Example — mono (multi-plugin bundle)

```
claude-plugin structure check — <repo-path>
  mode: mono (source "./plugins/..")   plugins: <p1> / <p2>   skills: <count>   (git: yes|no)

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

### Example — single (repo is one plugin)

```
claude-plugin structure check — <repo-path>
  mode: single (source "./")   plugins: . (root)   skills: 4   (git: yes)

[필수]
 PASS  M1 .claude-plugin/marketplace.json (유효, source "./")
 PASS  M2 root .claude-plugin/plugin.json (plugin root 1개)
 PASS  M3 .claude-plugin/plugin.json (유효)
 PASS  M4 skills/<s>/SKILL.md (4개 모두 name/description 보유)
 PASS  M5 docs/skill-guides/, docs/skill-output/
 PASS  M6 README.md

[권장]
 PASS  R1 docs/skill-guides/<s>.html (4개 모두 존재)
 PASS  R2 docs/skill-output/<s>-usage.{html,md}
 PASS  R3 README.md 가 docs/ 로 링크 (Simple)
 PASS  R4 명명 일관성
 PASS  R5 README 가 스킬별 guide+usage 링크 보유

요약: PASS — 표준 구조 준수
```

When the mode was inferred by the ambiguous fallback, append `, 추정` —
`mode: mono (추정)`.

## Layout rules

- One line per item: `<RESULT>  <ID> <subject> <note>`.
- `<RESULT>` is one of `PASS` / `WARN` / `FAIL` / `N/A` (uppercase),
  left-padded so the IDs align.
- `[필수]` block lists M1-M6 in order; `[권장]` block lists R1-R5 in order.
- R5 is per-skill: when more than one skill misses a link, emit one R5 line
  naming the first offender (or summarize `<n>개 스킬`); a clean repo → PASS,
  no skills → N/A.
- Header line names the **detected mode** (with the deciding signal:
  `source "./"`, `source "./plugins/.."`, or `추정`), the discovered
  plugins, and total skill count — proof the scan + mode detection were
  dynamic, not hard-coded. In `single` mode the plugins field is `. (root)`.

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
