# Skill Quality Checks

Fourteen checks, each rated PASS / WARN / FAIL / N/A.

---

## Structure Checks (1–5)

### Check 1: Line Count
PASS ≤ 100 | WARN 101–150 | FAIL > 150
Every line over 100 is a candidate for `references/` extraction.

### Check 2: Progressive Disclosure Structure
PASS — workflow phases only in SKILL.md; detail in `references/`
WARN — mostly workflow but some templates/tables inline
FAIL — large reference content embedded directly in SKILL.md

### Check 3: Frontmatter Validity
Look for: `name` present, `description` present, only known attributes present.
Known attributes: `name`, `description`, `allowed-tools`, `compatibility`,
`metadata`, `user-invocable`, `argument-hint`, `disable-model-invocation`, `license`.
**Naming**: read `references/naming-convention.md` — `category:action` colon
form is the SSOT convention and reports as PASS, not WARN. Folder/name
kebab-vs-colon mismatch is also PASS when folder is the kebab form of the
colon name (e.g., `name: gh:pr` + folder `gh-pr/`).
PASS — valid | WARN — minor issues | FAIL — missing fields or unknown attributes

### Check 4: References Directory Usage
PASS — `references/` exists with focused files, each referenced from SKILL.md
WARN — `references/` exists but not clearly triggered from SKILL.md body
FAIL — SKILL.md > 100 lines AND no `references/` directory

### Check 5: Output Report Defined
PASS — output format with example clearly defined
WARN — output described but vague
FAIL — no output format defined

---

## UX Quality Checks (6–11)

### Check 6: Help Flag Pattern
PASS — `-h`/`--help`/`help` arg → reads `references/help.md` verbatim, then stops. No API calls.
WARN — help exists but inline (not in `references/help.md`) or not verbatim
FAIL — no `-h`/`--help`/`help` support at all

### Check 7: Step Structure
PASS — execution steps numbered (Step 1, Step 2, …) with explicit stop-on-error policy
WARN — steps described but unnumbered, or no stop-on-error policy stated
FAIL — no clear execution flow
N/A — skill is a single read-only lookup (no multi-step execution)

### Check 8: Options Documentation
PASS — all accepted options in a table: Option | Description | Default
WARN — options listed but missing defaults or described in prose only
FAIL — options accepted but not documented
N/A — skill takes no arguments or options

### Check 9: Verdict Output
PASS — final output has explicit `[OK]`/`[FAIL]` verdict + structured key-value pairs
WARN — success/failure indicated but unstructured (plain prose)
FAIL — no explicit verdict in output
N/A — skill is purely informational (no action outcome to report)

### Check 10: Next-action Hint
PASS — success report includes next steps, follow-up commands, or teardown
WARN — partial guidance (mentions what comes next but no concrete commands)
FAIL — output ends without any guidance on what to do next
N/A — skill is terminal (no natural follow-up action exists)

### Check 11: No Emojis
PASS — no emoji glyphs in SKILL.md body or `references/*.md`
FAIL — emoji present AND skill name NOT in `references/allowed-emoji-skills.txt`
N/A — skill name IS in allowlist (`[N/A] allowlisted in references/allowed-emoji-skills.txt`)
WARN — allowlist file missing (degrade rather than block; skill:check stays read-only)

Rationale: CLAUDE.md "No emojis anywhere" policy with one exception — the
`ai-metrics` footer's `📊 👤 🤖` glyphs inside `<details>` / `<!-- ai-metrics -->`
blocks (#317 F-2, PR #320, #367 wrapper).

Detection: grep for codepoints in the ranges `U+1F300-U+1FAFF` (pictographic
extended) and `U+2600-U+27BF` (misc symbols & dingbats). Range is intentionally
narrower than "all emoji" to avoid false positives on BMP symbols (✓ ✗ etc).

Skill name resolution: take frontmatter `name:` colon form and convert to
hyphen form (`gh:add-ai-metrics` → `gh-add-ai-metrics`), or fall back to the
directory basename when frontmatter `name:` is absent.

Allowlist: `claude/skills/skill-check/references/allowed-emoji-skills.txt` —
one skill name per line, `#` comments allowed, blank lines ignored. Each
entry must carry an inline rationale comment.

FAIL output: list up to 5 matched files+lines and append the guidance
`Remove emoji or add to references/allowed-emoji-skills.txt with rationale`.

---

## Model Recommendation Check (12)

### Check 12: Model Recommendation Metadata
Read `references/model-recommendation.md` (rubric SSOT) for the full schema,
tier rubric, migration gate, and compatibility policy. This check is
**read-only — it recommends a tier, never switches models or writes files** (#809).

Detect `metadata.model_recommendation` in the SKILL.md frontmatter:

| Result | Criteria |
|---|---|
| PASS | valid `tier` (haiku/sonnet/opus) + `reason` + compatibility (`claude` and `non_claude`) all present |
| WARN | `tier` present but `reason` or compatibility missing — OR metadata absent while the migration gate is open (gate state = `MIGRATION_COMPLETE` in `references/model-recommendation.md`) |
| FAIL | disallowed `tier` value — OR metadata absent after the migration gate closes (gate state = `MIGRATION_COMPLETE` in `references/model-recommendation.md`) |
| N/A | skill explicitly disables model invocation (`disable-model-invocation: true`) |

On WARN-for-absence, suggest the migration command from
`references/model-recommendation.md` Section 3. On FAIL-for-tier, print the
allowed values `haiku | sonnet | opus`.

**Recommended tier (always reported, even when metadata exists):** apply the
Section 2 rubric to the audited skill and report the recommended tier with a
one-line rationale. When metadata is present, note agreement or mismatch with
the declared `tier`.

**Composite skills (F-5 / F-6):** when the SKILL.md body invokes other skills
(`/gh-*`, `gh:*`, `Skill(<name> ...)` patterns), build a 1-depth Sub-skill Model
Plan — read each sub-skill's declared `tier`, mark missing ones `unknown` (WARN),
and report it **separately from this skill's own tier** (see report-template.md).
Recursion is 1-depth by default; `--recursive` opts into deeper traversal.

---

## Security & Policy Alignment Checks (13–14)

These two checks pre-empt findings that external security scanners (e.g. an
org's AgentToolbox scanner) raise against published skills. Both are
**read-only — they flag a policy gap, never edit files** (audit-only invariant).

### Check 13: License Declaration
Cross-check frontmatter `license` against the repo-root `LICENSE` file.

| Result | Criteria |
|---|---|
| PASS | frontmatter declares a `license` field |
| WARN | no `license` in frontmatter BUT a `LICENSE` file exists at the repo root → suggest "add `license: <SPDX>` to frontmatter" (pre-empts scanner `MANIFEST_MISSING_LICENSE`) |
| N/A | repo has no `LICENSE` file (private/experimental skill — nothing to align with) |

Repo root: walk up from the SKILL.md until a `LICENSE`/`LICENSE.md`/`LICENSE.txt`
or a `.git` directory is found; the LICENSE check is relative to that root.
On WARN, recommend a concrete SPDX identifier when the LICENSE is recognizable
(e.g. `license: MIT`), else `license: <SPDX>`.

### Check 14: Capability Declaration Consistency
Scan the skill's executable scripts (primarily `scripts/`, plus any
`*.sh`/`*.py` shipped beside the SKILL.md) for network-capability signals and
compare against the `compatibility.network` declaration. 1st-scope is **network
only** — the capability the external scanner actually flags
(`TOOL_ABUSE_UNDECLARED_NETWORK`).

Network signals: imports of `requests` / `httpx` / `urllib` / `http.client` /
`socket` / `aiohttp`, or explicit MCP/HTTP call patterns (e.g. `curl`, `wget`,
`fetch(`, `http(s)://` request construction).

| Result | Criteria |
|---|---|
| PASS | no network signal found, OR network is used AND `compatibility.network` is declared |
| WARN | network signal present BUT no `compatibility.network` declaration → suggest "scripts use the network — declare `compatibility.network: required`" |
| N/A | skill ships no executable scripts (pure-prompt skill — nothing to scan) |

Extension note: filesystem-write and subprocess capabilities follow the same
detect-vs-declare pattern; 1st scope is intentionally network-only because that
is what the scanner flags today. `CROSS_SKILL_SHARED_URL` (multiple skills
sharing one external domain) is **out of scope** — it requires cross-file
analysis, while `skill:check` audits a single SKILL.md.
