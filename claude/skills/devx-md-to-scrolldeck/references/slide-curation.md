# Slide Curation — turning a document into narrative beats

The markup is the easy part. The reason a hand-made deck beats a generated
one is **editorial compression**: someone decided what the document is
*about*, and cut the rest. A heading-to-slide `map()` produces a deck that
reads like a table of contents, which is exactly what a leadership audience
does not want.

So: read the whole document first, decide the beats, *then* write HTML.

## Why 1:1 heading mapping fails

Measured on the reference deck (`avatar-realization-vision-and-roadmap`):

- source: ~25 headings (`##` + `###`) over 535 lines
- deck: **14 slides**
- section 3 had 4 `###` subsections (Card / Role / Task / Skill) → collapsed
  into **one** slide, because they are four facets of a single idea
  ("what an avatar is made of")
- section 5 had 5 `###` subsections (5.1–5.5) → **two** slides survived
  (the export feature, the four-values summary); the rest were folded into
  neighbouring slides or cut as operational detail
- the reference list at the end became **zero** slides

The ratio is not the point — the *judgement* is. Headings mark where an
author changed topic in prose. Slides mark where a presenter changes what
the audience should be thinking about. Those are different rhythms.

## Step A — read the whole document

Do not start outlining after the first screenful. You need the ending to
know what the opening should set up. While reading, note:

- the single claim the document is making (this becomes the hero headline)
- the ask / call to action (this becomes the closing slide)
- 3–5 structural phases (`WHY` → `WHAT` → `NOW` → `NEXT` → `START`); these
  become `data-phase` values and give the deck a shape
- anything that is reference material, appendix, links, or changelog — cut

## Step B — pick the beats

Target roughly **one slide per 30–40 source lines**, then adjust by
judgement. Treat it as a starting estimate, never as arithmetic:

| Source length | Typical deck |
|---|---|
| under 150 lines | 5–8 slides |
| 150–400 lines | 8–13 slides |
| 400–800 lines | 12–18 slides |
| over 800 lines | 15–20 slides, and ask the user whether to split |

Hard bounds: fewer than 5 slides is a one-pager, not a deck (suggest
`devx:visualize` instead); more than 20 is a document with scroll-snap
bolted on. If the content genuinely needs more than 20, say so and propose
a scope cut rather than silently producing 30 slides.

**Merge** when: consecutive headings are facets of one concept; a section is
a short list that fits as a card grid inside its parent's slide; a section
is only a bridge sentence.

**Split** when: one heading contains two distinct claims; a heading holds a
long process the audience must follow step by step; a table has more than
about 5 rows and its rows are the actual content.

**Cut** when: it is a reference list, a link dump, a caveat only the author
cares about, or repeats a point already made. Cutting is the skill. Tell
the user what you cut in the outline so they can veto it.

## Step C — draft the nav-dot outline BEFORE any HTML

This is the main quality lever of the whole skill. Print it to the user as
a table and let them react. It costs one short message and saves a rewrite
of a 3000-line file.

```
Outline (14 slides)

 #  id           label                       archetype        phase   source
 1  hero         아바타 현실화                hero             INTRO   L1-33
 2  gap          업무 맥락의 공백             two-column       WHY     L35-49
 3  definition   아바타의 정의                comparison       WHAT    L51-66
 4  anatomy      Card/Role/Task/Skill 구조    data-callout     WHAT    L68-121
 ...
14  action       지금 시작할 한 가지          closing          START   L465-524

Cut: 참고 자료 (link list), 5.2/5.4 (folded into #6)
```

Each row must carry: slide number, `id` slug (kebab-case, ASCII, short —
it goes in the URL hash), a human label for `aria-label`, the archetype,
the `data-phase`, and which source lines it draws from. The source-line
column is what keeps you honest — a slide with no source range is a slide
you invented.

## Step D — slide archetypes

Pick one per beat. The vocabulary is borrowed from standard deck practice;
the *chrome* here is vertical scroll-snap, so there is no `translateX`
carousel and no per-slide click zones.

| Archetype | Use for | Skeleton parts |
|---|---|---|
| **hero** | slide 1 only: the claim + one-line promise | `.slide--hero.slide--dark`, `.slide__inner--split`, `h1` |
| **content** | a heading + 3–5 supporting points | `.section-heading` + `.card-grid` |
| **section-divider** | phase change; one line, huge type | `.slide--dark`, `h2` alone, no body |
| **two-column** | before/after, tool vs need, gap framing | `.slide__inner--split` |
| **comparison** | "X is not A, X is B" tables | two `.card` panels side by side |
| **data-callout** | one number or one structure that carries the point | oversized figure + `.lead` |
| **quote/statement** | the thesis sentence, verbatim from the doc | `blockquote.statement` alone on a `--soft` slide |
| **process** | ordered steps the audience must follow | numbered `.card-grid` or an `<ol>` |
| **roadmap** | time-phased plan (now / 3mo / 1yr) | horizontal track + `.status-pill--now/next/vision` |
| **closing** | the ask, this week's action | `.slide--action.slide--dark`, no `.next-cue` |

Rules that keep archetypes from degenerating:

- **One idea per slide.** A second idea means a second slide or a cut.
- **Max ~40 words of body copy per slide**, headline max ~10 words. A
  leadership deck is read at a glance while someone talks over it.
- **Never repeat an archetype three times in a row.** Alternate slide
  variants too (see the rhythm in `scroll-deck-skeleton.md`).
- **Prose becomes structure.** A source paragraph becomes a card grid, a
  diagram, or a statement — never a wall of `<p>`.
- **Every number, name, and quote comes from the source.** Compression is
  allowed; invention is not. If a slide needs a figure the document does
  not contain, cut the slide.

## Step E — sanity-read the deck as a story

Read the 14 headlines in order, out loud, ignoring everything else. They
should form a coherent argument on their own. If two consecutive headlines
say the same thing, merge. If the sequence lurches, reorder or add a
section-divider. This 60-second pass catches most curation errors.
