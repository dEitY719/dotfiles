# Debugging Patterns — Fix common visualization failures

Load this when charts, counters, or menus behave unexpectedly.

## Table of Contents
- [Counter Animation Debug](#counter-animation-debug)
- [Chart.js Safety Pattern](#chartjs-safety-pattern)
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

## Chart.js Safety Pattern

Full defensive initialization to prevent console errors:

```javascript
// STEP 1: Global variables - MUST use var, never let/const
var chartsBuilt = false;

// STEP 2: Chart building function with validation
function buildCharts() {
  // CRITICAL: Always validate Chart.js loaded first
  if (chartsBuilt || typeof Chart === 'undefined') return;

  // STEP 3: Destroy existing charts to prevent "Canvas already in use"
  if (window.myChart) {
    try { window.myChart.destroy(); } catch(e) {}
  }

  // STEP 4: Reset canvas elements
  var canvas = document.getElementById('chartId');
  if (!canvas) return;

  // STEP 5: Get theme colors from CSS variables
  var isDark = document.documentElement.className.includes('theme-dark');
  var textColor = isDark ? '#EDEDED' : '#0f172a';
  var gridColor = isDark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.06)';

  // STEP 6: Create chart with proper options
  try {
    window.myChart = new Chart(canvas.getContext('2d'), {
      // Your chart configuration here
      options: {
        responsive: true,
        maintainAspectRatio: false,   // REQUIRED
        plugins: {
          tooltip: { enabled: true }, // REQUIRED - never disable
          legend: {
            labels: { color: textColor, font: { family: 'Inter' } }
          }
        },
        scales: {
          x: {
            ticks: { color: textColor },
            grid: { color: gridColor }
          },
          y: {
            ticks: { color: textColor },
            grid: { color: gridColor }
          }
        }
      }
    });
    chartsBuilt = true;
  } catch (error) {
    console.error('Chart creation failed:', error);
  }
}

// STEP 7: Theme change handler
function onThemeChange() {
  if (chartsBuilt) {
    chartsBuilt = false;
    buildCharts();
  }
}

// STEP 8: Wire up
document.addEventListener('DOMContentLoaded', buildCharts);
```

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
