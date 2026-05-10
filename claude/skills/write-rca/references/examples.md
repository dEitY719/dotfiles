# RCA shape examples

Three real-world sizing categories. Pick the closest match and use the
ranges as a target — do not over-fit.

## Small — single-issue RCA

- **Problem shape**: bug fix in one component, one commit's worth of code.
- **Sections**: 1–9 all present, concise. §6 (compatibility matrix) often
  skipped.
- **Length**: 1200–1500 words.
- **Frontmatter**: single `project`, clear `category`,
  `difficulty_level: beginner` or `intermediate`.
- **Typical slug**: `2026-05-11-mapfile-compatibility`.

## Medium — multi-system incident RCA

- **Problem shape**: incident spanning 2+ services, one root cause.
- **Sections**: 1–9 + Timeline (postmortem add-on) + expanded §8 Related
  Issues.
- **Length**: 1800–2500 words.
- **Frontmatter**: multiple `project` entries (array), `severity: high` or
  `critical`, multiple tags.
- **Typical slug**: `2026-05-11-cache-stampede-checkout`.

## Large — architecture / systemic pattern RCA

- **Problem shape**: systemic pattern failure (e.g. consistent class of
  bug across modules).
- **Sections**: all 9 + Decision Trees + full Comparison Matrix (§6).
- **Length**: 2500–3500 words. If you exceed 3500, split into multiple
  documents linked from §8.
- **Frontmatter**: multiple tags, multiple projects,
  `difficulty_level: advanced`.
- **Typical slug**: `2026-05-11-zsh-pipe-subshell-tracing-pattern`.

## Generated output sample

Success report from a real run:

```
[OK] write-rca — 2026-05-11-mapfile-compatibility.md written
  path: $RCA_REPO_PATH/docs/analysis/2026-05-11-mapfile-compatibility.md
  words: 2847
  sections: 9/9
  audience: all-four
  format: hybrid-jekyll (YAML frontmatter + single .md)
  reading_time: 12 min

Generated document satisfies:
  [OK] Postmortem review
  [OK] Technical blog
  [OK] AI tool training
  [OK] Junior engineer onboarding
  [OK] Jekyll / GitHub Pages compatible
  [OK] Portable to Medium, Dev.to, personal blogs

Next: cat $RCA_REPO_PATH/docs/analysis/2026-05-11-mapfile-compatibility.md
Then: git -C $RCA_REPO_PATH push  (if --commit was used)
```
