# Debugging Patterns — Fix common visualization failures

Load this when charts, counters, or menus behave unexpectedly.

## Table of Contents
- [Counter Animation Debug](#counter-animation-debug)
- [Chart.js Blank-White-Space Checklist](#chartjs-blank-white-space-checklist)
- [Menu Outside-Click Fix](#menu-outside-click-fix)

---

## Counter Animation Debug

If KPI values show "0%" instead of animating to their target value:

```javascript
// DEBUG: Add after counter observer setup to verify intersection
var counterEl = document.querySelector('[data-count]');
if (counterEl) {
  console.log('Counter element found:', counterEl); // DEBUG
  var cObs = new IntersectionObserver(function(entries) {
    console.log('Counter intersection triggered:', entries); // DEBUG
    entries.forEach(function(e) {
      if (e.isIntersecting) {
        console.log('Starting counter animation'); // DEBUG
        animateCounters();
        cObs.disconnect();
      }
    });
  }, { threshold: 0.3 });
  cObs.observe(counterEl);
} else {
  console.warn('No [data-count] elements found'); // DEBUG
}
```

Common causes:
- `data-count` attribute missing from stat elements
- IntersectionObserver threshold too high (element never fully enters viewport)
- `animateCounters()` function not defined
- Counter elements above the fold but observer never fires (use `.animate` class instead for above-fold counters)

---

## Chart.js Blank-White-Space Checklist

For full chart initialization patterns (ChartManager, buildCharts, `chartsBuilt` guard, `onThemeChange`), see [references/chartjs-patterns.md](references/chartjs-patterns.md).

**If charts appear as blank white spaces, verify in order:**
1. Chart.js CDN is included before `</head>`
2. `Chart.defaults.animation = false;` is immediately after CDN
3. Initialization is inside `DOMContentLoaded` listener
4. No `import`/`export` syntax anywhere in the file
5. Canvas has `role="img"` and `aria-label` attributes
6. Container has explicit height (≥300px)

---

## Menu Outside-Click Fix

If the hamburger menu doesn't close when clicking outside:

```javascript
document.addEventListener('click', function(e) {
  var menu = document.querySelector('.viz-menu');
  var dropdown = document.getElementById('vizMenuDropdown');
  if (!e.target.closest('.viz-menu') && dropdown) {
    dropdown.classList.remove('open');
  }
});
```

Also add Escape key support:
```javascript
document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') {
    var dropdown = document.getElementById('vizMenuDropdown');
    if (dropdown) dropdown.classList.remove('open');
  }
});
```

The skeleton's `toggleMenu()` should already include outside-click handling. If it doesn't, add the above to the script section.
