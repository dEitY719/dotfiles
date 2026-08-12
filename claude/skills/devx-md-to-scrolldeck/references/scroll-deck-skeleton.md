# Scroll-Deck Skeleton — mandatory copy-paste base

Never write this HTML from scratch. Copy the whole skeleton, then replace
every `YOUR ... HERE` token. The chrome (progress bar, header, dot rail,
observer JS, print styles) is load-bearing — the checklist verifies it.

## Token map

| Token | Replace with |
|---|---|
| `YOUR DECK TITLE HERE` | `<title>` + hero headline source |
| `YOUR DESCRIPTION HERE` | one-sentence `<meta name="description">` |
| `YOUR BRAND HERE` | 1–3 word deck label shown top-left (uppercase) |
| `YOUR MARK HERE` | single letter/glyph for the header badge |
| `NN` | total slide count, zero-padded (`14`) |
| `YOUR NAV DOTS HERE` | one `<a class="deck-nav__dot">` per slide, in order |
| `YOUR SLIDES HERE` | the `<section class="slide ...">` blocks |
| `YOUR NOSCRIPT NOTE HERE` | one line telling non-JS readers to just scroll |

## Language

Set `<html lang="...">` to the source document's language. For Korean
content keep `lang="ko"` and `word-break: keep-all` (already in the CSS) —
it is what stops Korean headlines breaking mid-word.

---

## Full skeleton

```html
<!doctype html>
<html lang="ko">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="description" content="YOUR DESCRIPTION HERE" />
    <title>YOUR DECK TITLE HERE</title>

    <!-- Webfont via CDN. NEVER inline a base64 @font-face by default -
         see font-and-bedrock-safety.md. -->
    <link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin />
    <link
      rel="stylesheet"
      href="https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/dist/web/static/pretendard.min.css"
    />

    <style>
      :root {
        /* Paper palette - light/print first. Retune hues per deck, keep names. */
        --paper: #f3f0e8;
        --paper-bright: #fbfaf6;
        --soft: #e9ebe5;
        --ink: #12212e;
        --ink-muted: #52606a;
        --navy: #071a28;
        --navy-deep: #04111b;
        --line: rgba(18, 33, 46, 0.17);
        --line-dark: rgba(255, 255, 255, 0.17);

        /* Phase accents - reuse across pills, rails, progress bar. */
        --now: #37b87c;
        --now-soft: #d8f2e5;
        --next: #347ee8;
        --next-soft: #dce9fb;
        --vision: #9f85ff;
        --vision-soft: #e8e1ff;
        --signal: #e9673f;

        --display:
          "Iowan Old Style", "Palatino Linotype", "Book Antiqua",
          "Noto Serif KR", Pretendard, serif;
        --sans:
          Pretendard, "Apple SD Gothic Neo", "Noto Sans KR", "Malgun Gothic",
          system-ui, sans-serif;
        --mono: "SFMono-Regular", "Cascadia Code", "Roboto Mono", monospace;

        /* Fluid type scale. h1 >= h2 >= h3 >= body, always. */
        --title-hero: clamp(42px, 4.4vw, 72px);
        --title-section: clamp(38px, 4vw, 62px);
        --lead-size: clamp(18px, 1.25vw, 21px);
        --text-sm: clamp(16px, 1.08vw, 18px);
        --text-xs: clamp(15px, 1vw, 17px);
        --page-x: clamp(28px, 6vw, 112px);
        --header-h: 76px;
      }

      *,
      *::before,
      *::after { box-sizing: border-box; }

      /* The scroll-snap container. Do not move these three lines. */
      html {
        scroll-behavior: smooth;
        scroll-snap-type: y mandatory;
        background: var(--navy-deep);
      }

      body {
        margin: 0;
        min-width: 320px;
        color: var(--ink);
        background: var(--paper);
        font-family: var(--sans);
        line-height: 1.55;
        text-rendering: optimizeLegibility;
        -webkit-font-smoothing: antialiased;
      }

      a { color: inherit; }
      p, h1, h2, h3, blockquote, ul, ol, pre { margin: 0; }
      ul, ol { padding: 0; }
      :focus-visible { outline: 3px solid var(--signal); outline-offset: 5px; }

      /* --- progress bar --- */
      .progress {
        position: fixed;
        z-index: 100;
        inset: 0 0 auto;
        height: 3px;
        background: rgba(255, 255, 255, 0.12);
        pointer-events: none;
      }
      .progress__bar {
        display: block;
        width: 100%;
        height: 100%;
        background: linear-gradient(90deg, var(--now), var(--next) 55%, var(--vision));
        transform: scaleX(0);
        transform-origin: left;
        will-change: transform;
      }

      /* --- fixed header: brand + phase + counter --- */
      .deck-header {
        position: fixed;
        z-index: 90;
        inset: 3px 0 auto;
        height: var(--header-h);
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 0 var(--page-x);
        color: white;
        mix-blend-mode: difference; /* stays legible over light AND dark slides */
        pointer-events: none;
      }
      .deck-header a { pointer-events: auto; }
      .deck-header__brand {
        display: inline-flex;
        align-items: center;
        gap: 12px;
        font-size: var(--text-xs);
        font-weight: 800;
        letter-spacing: 0.16em;
        text-decoration: none;
        text-transform: uppercase;
      }
      .deck-header__mark {
        display: grid;
        width: 30px;
        height: 30px;
        place-items: center;
        border: 1px solid currentColor;
        font-family: var(--display);
        font-size: 17px;
        font-style: italic;
      }
      .deck-header__status {
        display: flex;
        align-items: center;
        gap: 24px;
        font-family: var(--mono);
        font-size: var(--text-sm);
        letter-spacing: 0.13em;
      }
      .deck-header__phase { opacity: 0.68; }
      .deck-header__count strong { font-size: 15px; font-weight: 700; }

      /* --- right-edge dot rail --- */
      .deck-nav {
        position: fixed;
        z-index: 95;
        top: 50%;
        right: clamp(18px, 2.2vw, 42px);
        display: flex;
        flex-direction: column;
        gap: 10px;
        transform: translateY(-50%);
        mix-blend-mode: difference;
      }
      .deck-nav__dot {
        display: block;
        width: 8px;
        height: 8px;
        border: 1px solid white;
        border-radius: 50%;
        opacity: 0.44;
        transition: opacity 180ms ease, transform 180ms ease, background 180ms ease;
      }
      .deck-nav__dot:hover,
      .deck-nav__dot[aria-current="step"] {
        background: white;
        opacity: 1;
        transform: scale(1.45);
      }

      /* --- slide shell --- */
      .slide {
        position: relative;
        min-height: 100svh;
        overflow: hidden;
        scroll-snap-align: start;
        scroll-snap-stop: always;
        isolation: isolate;
      }
      .slide::before { /* faint vertical column rule - quiet texture */
        position: absolute;
        z-index: -2;
        inset: 0;
        background-image: repeating-linear-gradient(
          90deg,
          transparent 0,
          transparent calc(12.5% - 1px),
          rgba(18, 33, 46, 0.035) calc(12.5% - 1px),
          rgba(18, 33, 46, 0.035) 12.5%
        );
        content: "";
        pointer-events: none;
      }

      .slide--paper { background: var(--paper); }
      .slide--soft { background: var(--soft); }
      .slide--dark { color: #f6f4ed; background: var(--navy); }
      .slide--dark::before {
        background-image: repeating-linear-gradient(
          90deg,
          transparent 0,
          transparent calc(12.5% - 1px),
          rgba(255, 255, 255, 0.045) calc(12.5% - 1px),
          rgba(255, 255, 255, 0.045) 12.5%
        );
      }
      .slide--hero {
        background:
          radial-gradient(circle at 73% 50%, rgba(55, 184, 124, 0.15), transparent 27%),
          linear-gradient(135deg, #06131f, #0b2536 68%, #061923);
      }
      .slide--vision {
        background:
          radial-gradient(circle at 74% 46%, rgba(159, 133, 255, 0.22), transparent 28%),
          linear-gradient(145deg, #071824, #111633 72%, #170e31);
      }
      .slide--action {
        background:
          linear-gradient(120deg, rgba(55, 184, 124, 0.1), transparent 38%),
          radial-gradient(circle at 84% 24%, rgba(159, 133, 255, 0.16), transparent 26%),
          var(--navy-deep);
      }

      .slide__inner {
        width: min(100%, 1600px);
        min-height: 100svh;
        margin: 0 auto;
        padding: clamp(100px, 12vh, 142px) var(--page-x) clamp(82px, 9vh, 112px);
        display: flex;
        flex-direction: column;
        justify-content: center;
      }
      .slide__inner--split {
        display: grid;
        grid-template-columns: minmax(0, 0.92fr) minmax(460px, 1.08fr);
        align-items: center;
        gap: clamp(48px, 7vw, 120px);
      }

      /* --- typography --- */
      .eyebrow {
        display: flex;
        align-items: center;
        gap: 14px;
        margin-bottom: clamp(22px, 3.2vh, 38px);
        color: var(--ink-muted);
        font-family: var(--mono);
        font-size: var(--text-sm);
        font-weight: 700;
        letter-spacing: 0.16em;
        text-transform: uppercase;
      }
      .eyebrow span:first-child::before {
        display: inline-block;
        width: 34px;
        margin-right: 14px;
        border-top: 1px solid currentColor;
        content: "";
        vertical-align: middle;
      }
      .slide--dark .eyebrow { color: rgba(246, 244, 237, 0.6); }

      h1, h2 {
        max-width: 1050px;
        color: inherit;
        font-family: var(--display);
        font-size: var(--title-section);
        font-weight: 500;
        letter-spacing: -0.055em;
        line-height: 1.07;
        text-wrap: balance;
        word-break: keep-all;
      }
      h1 { font-size: var(--title-hero); }
      h1 em, h2 em { color: var(--signal); font-weight: 500; font-style: italic; }
      .slide--dark h1 em, .slide--dark h2 em { color: #70d5a4; }
      .slide--vision h2 em { color: #c0afff; }

      .lead {
        max-width: 760px;
        margin-top: clamp(22px, 3vh, 34px);
        color: var(--ink-muted);
        font-size: var(--lead-size);
        line-height: 1.8;
        word-break: keep-all;
      }
      .slide--dark .lead { color: rgba(246, 244, 237, 0.68); }

      .section-heading {
        display: grid;
        grid-template-columns: minmax(0, 1.1fr) minmax(360px, 0.72fr);
        column-gap: clamp(44px, 7vw, 128px);
        align-items: end;
        margin-bottom: clamp(34px, 5vh, 62px);
      }
      .section-heading .eyebrow,
      .section-heading .status-pill { grid-column: 1 / -1; }
      .section-heading .lead { margin: 0 0 5px; }

      .status-pill {
        justify-self: start;
        margin: -7px 0 22px;
        padding: 7px 12px 6px;
        border-left: 3px solid currentColor;
        color: var(--ink);
        background: rgba(255, 255, 255, 0.58);
        font-family: var(--mono);
        font-size: var(--text-sm);
        font-weight: 800;
        letter-spacing: 0.08em;
      }
      .status-pill--now { color: #14734b; background: var(--now-soft); }
      .status-pill--next { color: #1f60bb; background: var(--next-soft); }
      .status-pill--vision { color: #d7cdff; background: rgba(159, 133, 255, 0.19); }
      .status-pill--on-dark { color: #a9ccff; background: rgba(52, 126, 232, 0.18); }

      /* Pull-quote / thesis line. One per slide, at most. */
      .statement {
        max-width: 980px;
        margin-top: clamp(30px, 4.5vh, 54px);
        padding-left: clamp(20px, 2vw, 30px);
        border-left: 3px solid var(--signal);
        font-family: var(--display);
        font-size: clamp(22px, 1.9vw, 31px);
        line-height: 1.45;
        word-break: keep-all;
      }
      .statement strong { font-weight: 700; }
      .slide--dark .statement { border-left-color: #70d5a4; }

      /* Generic content grids - reuse instead of inventing per slide. */
      .card-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
        gap: clamp(18px, 2vw, 28px);
      }
      .card {
        padding: 24px;
        border: 1px solid var(--line);
        background: var(--paper-bright);
      }
      .slide--dark .card {
        border-color: var(--line-dark);
        background: rgba(255, 255, 255, 0.04);
      }
      .card > span {
        display: block;
        margin-bottom: 10px;
        color: var(--ink-muted);
        font-family: var(--mono);
        font-size: var(--text-xs);
        font-weight: 700;
      }
      .slide--dark .card > span { color: rgba(246, 244, 237, 0.55); }
      .card > strong { display: block; margin-bottom: 8px; font-size: 20px; font-weight: 700; }
      .card > p { font-size: var(--text-sm); line-height: 1.7; word-break: keep-all; }

      /* --- scroll cue --- */
      .next-cue {
        position: absolute;
        z-index: 4;
        right: var(--page-x);
        bottom: 26px;
        display: flex;
        align-items: center;
        gap: 12px;
        color: currentColor;
        font-family: var(--mono);
        font-size: var(--text-xs);
        font-weight: 700;
        letter-spacing: 0.13em;
        opacity: 0.55;
        text-decoration: none;
        text-transform: uppercase;
        transition: opacity 180ms ease;
      }
      .next-cue b {
        display: grid;
        width: 30px;
        height: 30px;
        place-items: center;
        border: 1px solid currentColor;
        border-radius: 50%;
        font-size: 16px;
        animation: cue 1.8s ease-in-out infinite;
      }
      .next-cue:hover { opacity: 1; }
      @keyframes cue {
        0%, 100% { transform: translateY(0); }
        50% { transform: translateY(4px); }
      }

      /* --- entrance animation: opt-in via .js, so content is visible without JS --- */
      .js .reveal {
        opacity: 0;
        transform: translateY(24px);
        transition:
          opacity 700ms ease,
          transform 700ms cubic-bezier(0.2, 0.75, 0.25, 1);
      }
      .js .slide[data-active="true"] .reveal { opacity: 1; transform: none; }
      .js .slide[data-active="true"] .reveal:nth-child(2) { transition-delay: 90ms; }
      .js .slide[data-active="true"] .reveal:nth-child(3) { transition-delay: 170ms; }

      .noscript-note {
        padding: 12px var(--page-x);
        font-size: var(--text-sm);
      }

      /* --- responsive --- */
      @media (max-width: 900px) {
        .slide__inner--split { display: flex; flex-direction: column; }
        .section-heading { display: block; }
        .section-heading .lead { margin-top: 20px; }
      }

      @media (max-width: 767px) {
        :root {
          --page-x: 22px;
          --header-h: 62px;
          --title-hero: clamp(38px, 10.5vw, 48px);
          --title-section: clamp(34px, 9.4vw, 44px);
          --lead-size: 16px;
        }
        /* Free scrolling on phones - mandatory snap fights touch momentum. */
        html { scroll-snap-type: none; }
        .deck-header__brand > span:last-child,
        .deck-header__phase { display: none; }
        .deck-nav { display: none; }
        .slide__inner { padding: 92px var(--page-x) 78px; }
        .eyebrow span:last-child { display: none; }
        .next-cue { right: 20px; bottom: 18px; }
        .next-cue span { display: none; }
      }

      @media (prefers-reduced-motion: reduce) {
        html { scroll-behavior: auto; }
        *,
        *::before,
        *::after {
          animation-duration: 0.01ms !important;
          animation-iteration-count: 1 !important;
          transition-duration: 0.01ms !important;
        }
        .js .reveal { opacity: 1; transform: none; }
      }

      /* --- print: snap off, every slide stacked on its own page --- */
      @media print {
        @page { size: A4 landscape; margin: 0; }
        html, body { background: white; scroll-snap-type: none; }
        .progress,
        .deck-header,
        .deck-nav,
        .next-cue,
        .noscript-note { display: none !important; }
        .slide { min-height: 100vh; break-after: page; page-break-after: always; overflow: hidden; }
        .slide__inner { min-height: 100vh; padding: 52px 58px; }
        .reveal { opacity: 1 !important; transform: none !important; }
        .slide--dark,
        .slide--hero,
        .slide--vision,
        .slide--action {
          print-color-adjust: exact;
          -webkit-print-color-adjust: exact;
        }
      }
    </style>
  </head>

  <body>
    <div class="progress" aria-hidden="true"><span class="progress__bar"></span></div>

    <header class="deck-header">
      <a class="deck-header__brand" href="#hero" aria-label="첫 슬라이드로 이동">
        <span class="deck-header__mark" aria-hidden="true">YOUR MARK HERE</span>
        <span>YOUR BRAND HERE</span>
      </a>
      <div class="deck-header__status" aria-live="polite">
        <span class="deck-header__phase">INTRO</span>
        <span class="deck-header__count"><strong>01</strong> / NN</span>
      </div>
    </header>

    <nav class="deck-nav" aria-label="슬라이드 바로가기">
      <!-- One dot per slide, same order as <main>. aria-current on the first. -->
      <a class="deck-nav__dot" href="#hero" aria-label="1. 표지" aria-current="step"></a>
      YOUR NAV DOTS HERE
    </nav>

    <main id="deck">
      <!-- Slide 1: hero. Pattern for every later slide:
             <section class="slide slide--VARIANT" id="SLUG"
                      aria-labelledby="SLUG-title" data-phase="PHASE"> -->
      <section
        class="slide slide--hero slide--dark"
        id="hero"
        aria-labelledby="hero-title"
        data-phase="INTRO"
      >
        <div class="slide__inner slide__inner--split">
          <div class="reveal">
            <p class="eyebrow"><span>YOUR BRAND HERE</span><span>01</span></p>
            <h1 id="hero-title">YOUR DECK TITLE HERE</h1>
            <p class="lead">YOUR DESCRIPTION HERE</p>
          </div>
          <div class="reveal">YOUR HERO VISUAL HERE</div>
        </div>
        <a class="next-cue" href="#SECOND-SLUG"
          ><span>YOUR CUE LABEL HERE</span><b aria-hidden="true">↓</b></a
        >
      </section>

      YOUR SLIDES HERE

      <!-- Last slide carries NO .next-cue - it has nowhere to point. -->
    </main>

    <script>
      (() => {
        document.documentElement.classList.add("js");

        const slides = [...document.querySelectorAll(".slide")];
        const dots = [...document.querySelectorAll(".deck-nav__dot")];
        const phase = document.querySelector(".deck-header__phase");
        const count = document.querySelector(".deck-header__count strong");
        const progress = document.querySelector(".progress__bar");
        const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
        let activeIndex = 0;
        let progressFrame = 0;

        function setActive(index) {
          const nextIndex = Math.max(0, Math.min(index, slides.length - 1));
          activeIndex = nextIndex;

          slides.forEach((slide, i) => {
            if (i === nextIndex) slide.setAttribute("data-active", "true");
            else slide.removeAttribute("data-active");
          });
          dots.forEach((dot, i) => {
            if (i === nextIndex) dot.setAttribute("aria-current", "step");
            else dot.removeAttribute("aria-current");
          });

          if (phase) phase.textContent = slides[nextIndex]?.dataset.phase ?? "";
          if (count) count.textContent = String(nextIndex + 1).padStart(2, "0");
        }

        function goTo(index) {
          const nextIndex = Math.max(0, Math.min(index, slides.length - 1));
          const target = slides[nextIndex];
          if (!target) return;
          setActive(nextIndex);
          target.scrollIntoView({
            behavior: reduceMotion ? "auto" : "smooth",
            block: "start",
          });
        }

        function updateProgress() {
          progressFrame = 0;
          const maxScroll = document.documentElement.scrollHeight - innerHeight;
          const ratio = maxScroll > 0 ? Math.min(1, Math.max(0, scrollY / maxScroll)) : 0;
          progress?.style.setProperty("transform", `scaleX(${ratio})`);
        }

        const observer = new IntersectionObserver(
          (entries) => {
            const visible = entries
              .filter((entry) => entry.isIntersecting)
              .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
            // No ratio floor: a slide taller than ~3.57x the viewport can
            // never reach a 0.28 intersection ratio, so gating on one here
            // would permanently strand it as "never active".
            if (!visible) return;
            const index = slides.indexOf(visible.target);
            if (index >= 0 && index !== activeIndex) setActive(index);
          },
          { threshold: [0, 0.28, 0.45, 0.62, 0.8] },
        );
        slides.forEach((slide) => observer.observe(slide));

        addEventListener(
          "scroll",
          () => {
            if (!progressFrame) progressFrame = requestAnimationFrame(updateProgress);
          },
          { passive: true },
        );
        addEventListener("resize", () => requestAnimationFrame(updateProgress), {
          passive: true,
        });

        const navigationKeys = new Set([
          "ArrowDown",
          "ArrowUp",
          "PageDown",
          "PageUp",
          "Home",
          "End",
        ]);

        // A slide taller than the viewport still needs native scrolling to
        // read its own overflow — only jump to the next/prev slide once
        // the active slide has no more room to scroll in that direction.
        function activeSlideHasScrollRoom(dir) {
          const slide = slides[activeIndex];
          if (!slide) return false;
          const rect = slide.getBoundingClientRect();
          return dir > 0 ? rect.bottom > innerHeight + 1 : rect.top < -1;
        }

        addEventListener("keydown", (event) => {
          if (event.ctrlKey || event.metaKey || event.altKey) return;
          if (
            event.target.closest("a, button, input, textarea, select, summary, [contenteditable]")
          )
            return;
          if (!navigationKeys.has(event.key) && event.key !== " " && event.key !== "Spacebar")
            return;

          const isSpace = event.key === " " || event.key === "Spacebar";
          const forward = event.key === "ArrowDown" || event.key === "PageDown" ||
            (isSpace && !event.shiftKey);
          const backward = event.key === "ArrowUp" || event.key === "PageUp" ||
            (isSpace && event.shiftKey);
          if (forward && activeSlideHasScrollRoom(1)) return;
          if (backward && activeSlideHasScrollRoom(-1)) return;

          const keyActions = {
            ArrowDown: () => goTo(activeIndex + 1),
            PageDown: () => goTo(activeIndex + 1),
            ArrowUp: () => goTo(activeIndex - 1),
            PageUp: () => goTo(activeIndex - 1),
            Home: () => goTo(0),
            End: () => goTo(slides.length - 1),
          };

          let action = keyActions[event.key];
          if (isSpace) {
            action = () => goTo(activeIndex + (event.shiftKey ? -1 : 1));
          }
          if (action) {
            event.preventDefault();
            action();
          }
        });

        const hashIndex = slides.findIndex((slide) => `#${slide.id}` === location.hash);
        setActive(hashIndex >= 0 ? hashIndex : 0);
        updateProgress();
      })();
    </script>

    <noscript>
      <p class="noscript-note">YOUR NOSCRIPT NOTE HERE</p>
    </noscript>
  </body>
</html>
```

---

## Slide block patterns

Standard content slide — reuse `.section-heading` for every non-hero slide:

```html
<section class="slide slide--paper" id="SLUG" aria-labelledby="SLUG-title" data-phase="PHASE">
  <div class="slide__inner">
    <div class="section-heading reveal">
      <p class="eyebrow"><span>SHORT KICKER</span><span>02</span></p>
      <h2 id="SLUG-title">Headline with an <em>emphasis</em> span</h2>
      <p class="lead">One sentence of context. Never a paragraph.</p>
    </div>

    <div class="card-grid reveal">YOUR CONTENT HERE</div>

    <blockquote class="statement reveal">The one thing to remember.</blockquote>
  </div>
  <a class="next-cue" href="#NEXT-SLUG"><span>NEXT LABEL</span><b aria-hidden="true">↓</b></a>
</section>
```

Variant rotation — alternate so consecutive slides never look identical.
A good default rhythm for a 12–16 slide scroll deck:

```
hero(dark) -> paper -> soft -> paper -> dark -> paper -> soft
  -> dark -> paper -> vision(dark) -> soft -> action(dark)
```

## Wiring rules the checklist enforces

1. `#hero` is the id of slide 1 and the header brand links to it.
2. `.deck-nav__dot` count == `.slide` count, same order, hrefs match ids.
3. Every slide but the last has a `.next-cue` pointing at the next id.
4. `data-phase` is a short uppercase word (`INTRO` / `WHY` / `NOW` / `NEXT`
   / `VISION` / `START`); the header reads it live.
5. `NN` in the counter equals the slide count.
6. Each slide gets `aria-labelledby` matching its own `h1`/`h2` id.
7. `.reveal` is applied to direct children of `.slide__inner` only — the
   `nth-child` delays are relative to that parent.
