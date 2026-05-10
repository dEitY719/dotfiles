# Audience-specific rules

Step 4 (Audience apply) applies one of these presets. The default (no
`--audience` flag) keeps all four target audiences listed in the YAML
frontmatter and applies no redaction.

## Default (all four audiences)

- Postmortem — incident review and prevention planning.
- Technical Blog — narrative-driven learning content.
- AI Tool Training — pattern recognition and anti-pattern learning.
- Junior Engineer Onboarding — educational reference material.

Document is published as-is. No redaction. All sections kept.

## `--audience blog`

Optimize for narrative readability.

- Enhance narrative flow between sections.
- Add historical context / background near §2.
- Include author voice / personality where natural.
- Add a conclusion paragraph + call-to-action at the end of §9.
- Frontmatter: `blog_ready: true`, `target_audiences: ["blog", "ai-learning"]`.

## `--audience private` (alias: `--private`)

Optimize for sensitive incidents that must not leave the org.

- Redact secrets, hostnames, customer names, internal IPs, ticket numbers
  that reference customers.
- Replace concrete values with `<REDACTED>` placeholders.
- Drop the "Communication Log" section if present.
- Frontmatter: `target_audiences: ["postmortem"]` only. Set `blog_ready: false`.
- Add an HTML comment at the top of the file:
  `<!-- private: do not publish outside org -->`.

## `--audience internal`

Optimize for org-internal sharing.

- Keep links to internal tooling / runbooks / dashboards intact.
- Keep team names and reviewer handles.
- No external redaction needed.
- Frontmatter: `target_audiences: ["postmortem", "ai-learning", "junior-engineers"]`
  (drop `blog`). Set `blog_ready: false`.

## Postmortem focus add-ons

When the incident requires postmortem rigor (regardless of audience flag),
also add:

- "Timeline" section (ISO-8601 timestamps, one event per line).
- "Communication Log" section (who told whom, when) — skipped under
  `--private`.
- Emphasize prevention measures in §7.

## AI training focus add-ons

For documents intended to train downstream AI tools:

- Emphasize explicit pattern names in §5 and §8.
- Include anti-patterns explicitly under a "Don't do this" sub-heading.
- Add decision trees where branching logic exists.
- Use high-precision terminology — avoid metaphor-heavy prose.

## Junior engineer focus add-ons

- Simplify technical jargon; expand acronyms on first use.
- Add more explanations in §5.
- Include "Why this matters" callouts.
- Provide learning resources in §9's "Further reading".
