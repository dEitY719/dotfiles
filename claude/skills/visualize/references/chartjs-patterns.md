# Chart.js Patterns — Complete implementation reference

Load this when building any visualization that uses Chart.js.

## Table of Contents
- [ChartManager Pattern](#chartmanager-pattern) — recommended for multi-chart files
- [buildCharts Pattern](#buildcharts-pattern) — alternative for simpler single-chart files
- [Container Structure](#container-structure)
- [Initialization Details](#initialization-details)
- [Theme-Aware Colors](#theme-aware-colors)
- [Configuration Options](#configuration-options)

---

## ChartManager Pattern

Use `ChartManager.safeInit()` instead of raw `new Chart()`.

```javascript
var ChartManager = {
  charts: new Map(),
  safeInit: function(canvasId, config) {
    if (typeof Chart === 'undefined') {
      console.error('Chart.js library not loaded - check CDN inclusion');
      return null;
    }
    try {
      if (this.charts.has(canvasId)) {
        this.charts.get(canvasId).destroy();
        this.charts.delete(canvasId);
      }
      var ctx = document.getElementById(canvasId);
      if (!ctx) {
        console.error('Canvas element not found: ' + canvasId);
        return null;
      }
      // Ensure no conflicting chart instances
      if (ctx.chart) {
        ctx.chart.destroy();
        delete ctx.chart;
      }
      // Set accessibility attributes
      ctx.setAttribute('role', 'img');
      if (!ctx.getAttribute('aria-label')) {
        ctx.setAttribute('aria-label', 'Chart visualization');
      }
      var chart = new Chart(ctx, config);
      this.charts.set(canvasId, chart);
      return chart;
    } catch (error) {
      console.error('Chart initialization failed for ' + canvasId + ':', error);
      return null;
    }
  },
  updateTheme: function() {
    if (typeof Chart === 'undefined') return;
    this.charts.forEach(function(chart, canvasId) {
      try {
        chart.update();
      } catch (error) {
        console.error('Chart theme update failed for ' + canvasId + ':', error);
      }
    });
  },
  destroyAll: function() {
    this.charts.forEach(function(chart) {
      try { chart.destroy(); } catch (error) {}
    });
    this.charts.clear();
  }
};
```

**Troubleshooting charts that appear as blank white spaces:**
- Verify Chart.js CDN is included before `</head>`
- Verify `Chart.defaults.animation = false;` is immediately after CDN
- Verify chart initialization is in DOMContentLoaded event listener
- Verify no module import/export syntax anywhere in the file
- Verify `ChartManager.safeInit()` is used correctly
- Verify canvas has `role="img"` and `aria-label` attributes

---

## buildCharts Pattern

Alternative function-based pattern for simpler files. Uses `chartsBuilt` guard flag.

```javascript
// STEP 1: Global variables - MUST use var, never let/const
var chartsBuilt = false;

// STEP 2: Theme-aware color helper
function getChartColors() {
  var s = getComputedStyle(document.documentElement);
  return {
    text: s.getPropertyValue('--text').trim(),
    textSecondary: s.getPropertyValue('--text-secondary').trim(),
    border: s.getPropertyValue('--border').trim(),
    surface: s.getPropertyValue('--surface').trim(),
    accent: s.getPropertyValue('--accent').trim(),
  };
}

// STEP 3: Canvas reset helper (prevents "Canvas already in use" errors)
function resetCanvas(id) {
  var old = document.getElementById(id);
  if (!old) return null;
  var parent = old.parentNode;
  var canvas = document.createElement('canvas');
  canvas.id = id;
  parent.replaceChild(canvas, old);
  return canvas;
}

// STEP 4: Chart building function
function buildCharts() {
  if (chartsBuilt || typeof Chart === 'undefined') return;

  var colors = getChartColors();
  var isDark = document.documentElement.className.includes('theme-dark');

  // Destroy existing + rebuild
  if (window.myChart) {
    try { window.myChart.destroy(); } catch(e) {}
  }
  var ctx = resetCanvas('myChart');
  if (!ctx) return;

  try {
    window.myChart = new Chart(ctx, {
      type: 'bar',
      data: { /* your data */ },
      options: {
        responsive: true,
        maintainAspectRatio: false,     // REQUIRED
        animation: false,
        plugins: {
          tooltip: {
            enabled: true,              // NEVER disable
            padding: 12,
            cornerRadius: 8,
            titleFont: { size: 14 },
            bodyFont: { size: 13 }
          },
          legend: {
            labels: { color: colors.text, font: { family: 'Inter' } }
          }
        },
        layout: { padding: 20 },
        scales: {
          x: {
            ticks: { color: colors.textSecondary, maxRotation: 0 },
            grid: { color: colors.border }
          },
          y: {
            ticks: { color: colors.textSecondary },
            grid: { color: colors.border }
          }
        }
      }
    });
    chartsBuilt = true;
  } catch (error) {
    console.error('Chart creation failed:', error);
  }
}

// STEP 5: Theme change handler
function onThemeChange() {
  chartsBuilt = false;
  setTimeout(buildCharts, 100); // Short delay for CSS variable updates
}

// STEP 6: Wire up
// CRITICAL: Disable animations IMMEDIATELY after Chart.js CDN loads (in <head>):
//   Chart.defaults.animation = false;
document.addEventListener('DOMContentLoaded', buildCharts);
```

---

## Container Structure

**MANDATORY PATTERN FOR EVERY CHART:**

```html
<div role="img" aria-label="Detailed description of chart data and insights">
  <div class="chart-container" style="height: 360px; padding: 40px; border-radius: 12px; background: var(--surface);">
    <canvas id="uniqueChartId"></canvas>
  </div>
</div>
```

- Container minimum height: **360px for dashboards**, 300px for other types
- Canvas element needs no sizing — Chart.js handles it when `maintainAspectRatio: false`
- Container padding: 40px for professional spacing
- Container border-radius: 12px

**Slide deck chart containers:**
```html
<div class="chart-slide-container">
  <h2>Chart Title</h2>
  <div class="chart-container" style="height: 400px; padding: 40px; border-radius: 12px; background: var(--surface);">
    <canvas id="slideChart" role="img" aria-label="Description"></canvas>
  </div>
</div>
```
Minimum height **400px** for slide charts — larger for presentation readability.

---

## Initialization Details

**CDN (before `</head>`):**
```html
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js"></script>
<script>Chart.defaults.animation = false;</script>
```
⚠️ The `Chart.defaults.animation = false;` line MUST be immediately after the CDN script. Evaluation system checks for this.

**NEVER use import/export syntax with Chart.js CDN** — use standard `var` declarations only.

**Every chart initialization guard:**
```javascript
if (typeof Chart === 'undefined') { console.error('Chart.js not loaded'); return; }
```

---

## Theme-Aware Colors

Read CSS vars at render time; rebuild charts on theme change (never just swap colors in-place).

```javascript
function getChartColors() {
  var s = getComputedStyle(document.documentElement);
  return {
    text:          s.getPropertyValue('--text').trim(),
    textSecondary: s.getPropertyValue('--text-secondary').trim(),
    border:        s.getPropertyValue('--border').trim(),
    surface:       s.getPropertyValue('--surface').trim(),
    accent:        s.getPropertyValue('--accent').trim(),
  };
}
```

Apply to chart defaults:
```javascript
Chart.defaults.color = getComputedStyle(document.documentElement)
  .getPropertyValue('--text-secondary').trim();
```

Grid line colors:
- Dark: `rgba(255,255,255,0.04)`
- Light: `rgba(0,0,0,0.06)`

---

## Configuration Options

**Mandatory on every chart:**
```javascript
options: {
  responsive: true,
  maintainAspectRatio: false,   // REQUIRED — size via CSS container
  animation: false,
  plugins: {
    tooltip: { enabled: true }  // NEVER disable — evaluation checks this
  }
}
```

**Professional styling defaults:**
```javascript
options: {
  layout: { padding: { top: 20, right: 20, bottom: 20, left: 20 } },
  scales: {
    x: {
      ticks: { maxRotation: 0, font: { size: 13 } },
      grid: { color: 'rgba(0,0,0,0.06)' }
    },
    y: {
      ticks: { font: { size: 13 } },
      grid: { color: 'rgba(0,0,0,0.06)' }
    }
  },
  plugins: {
    tooltip: {
      enabled: true,
      mode: 'index',
      intersect: false,
      padding: 12,
      cornerRadius: 8,
      titleFont: { size: 14 },
      bodyFont: { size: 13 }
    },
    legend: { position: 'top' }  // 'right' for vertical charts with space
  }
}
```

**Additional guidelines:**
- `borderRadius: 4` for rounded bar corners
- Point radius: 0 by default, 6 on hover (cleaner line charts)
- Donut/pie: always include percentage labels on segments
- Font size minimums: axis ticks 13px, axis titles 14px, chart titles 16px
- High contrast colors between data series for accessibility
- **Stat value colors:** use semantic meaning only — `var(--positive)` for good, `var(--negative)` for bad. Never randomly colorize.
