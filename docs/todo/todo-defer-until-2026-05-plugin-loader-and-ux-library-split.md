# Phase 2 Refactoring Review Plan

**Status:** ⏳ Scheduled for Q2 2026 (May)
**Baseline:** Phase 1 completed (ebe8e8d)
**Reference:** docs/review/abc-review-C.md (Section 4 & 6)

---

## 📋 Overview

Evaluate two Phase 2 refactoring candidates based on actual project growth metrics. These are architectural improvements that should only be implemented when genuine needs emerge.

---

## 🎯 Review Criteria

### Trigger 1: File Count Threshold ✅
```
Current state (2026-02-09):
├── shell-common/aliases/*.sh        ~3 files
├── shell-common/functions/*.sh      ~8 files
├── shell-common/tools/integrations/ ~26 files
└── shell-common/tools/custom/       ~50+ files (executables, not auto-loaded)
────────────────────────────────
TOTAL AUTO-LOADED: ~37 files
```

**Action trigger:** When auto-loaded categories exceed **50 files**

### Trigger 2: Developer Friction 🤔
- [ ] Team requests conditional loading based on environment/context
- [ ] Setup time noticeably increases (baseline: ~100ms)
- [ ] New contributors confused by flat structure
- [ ] Maintenance burden of specific category documented

### Trigger 3: Code Smell 👃
- [ ] UX library file exceeds 300 lines
- [ ] Circular dependencies detected in UX modules
- [ ] Multiple functions share complex state management

---

## 📅 Schedule

| Date | Task | Owner |
|------|------|-------|
| 2026-05-01 | **Phase 2 Review Meeting** | Team |
| | Audit current file counts | DevX |
| | Assess growth trajectory | Architect |
| 2026-05-07 | Decision: Proceed with Phase 2? | Team |
| 2026-05-15 | (If YES) Begin implementation | TBD |
| 2026-08-01 | Quarterly check-in (if Phase 2 deferred) | DevX |

---

## 🔧 Phase 2A: Plugin Loader (`load_category` abstraction)

**Status:** 🔄 DEFERRED (Re-evaluate May 2026)

**Current Implementation:**
```bash
# bash/main.bash (lines 153-173)
source "${SHELL_COMMON}/util/loader.sh"
load_category "env"
load_category "aliases"
load_category "functions"
```

**What changes:**
- Create `loader_skip.conf` for conditional loading
- Support environment-based loading: `load_category "aliases" --if=work`
- Enable/disable categories dynamically

**Implementation effort:** 4-6 hours (once decided)

**Re-evaluation checklist:**
- [ ] File count in any category > 50?
- [ ] "We need different settings for home vs work" request received?
- [ ] Load time becomes noticeable issue?
- [ ] Team consensus: "This would help us"?

**Decision point:**
```
IF (file_count > 50 OR friction > 2 OR team_consensus = YES):
  → PROCEED with Phase 2A
ELSE:
  → DEFER 3 months, re-evaluate Aug 2026
```

---

## 📚 Phase 2B: UX Library Interface Split

**Status:** 🔄 DEFERRED (Re-evaluate May 2026)

**Current Implementation:**
```bash
# shell-common/tools/ux_lib/ux_lib.sh (~150 lines)
- ux_output.sh functions (headers, sections, colors)
- ux_progress.sh functions (spinners, progress bars)
- ux_error.sh functions (error handling, traps)
```

**What changes:**
```bash
# Split into 3 files
source "${SHELL_COMMON}/tools/ux_lib/ux_output.sh"      # 40 lines
source "${SHELL_COMMON}/tools/ux_lib/ux_progress.sh"    # 50 lines
source "${SHELL_COMMON}/tools/ux_lib/ux_error.sh"       # 40 lines
# + connection/dependency logic
```

**Implementation effort:** 8-12 hours (higher risk)

**Re-evaluation checklist:**
- [ ] File size > 300 lines?
- [ ] Clear separation of concerns (no function overlap)?
- [ ] No circular dependencies between modules?
- [ ] Team reports: "Too much UI cruft in lightweight scripts"?
- [ ] Load time degradation measurable?

**Decision point:**
```
IF (file_size > 300 AND complexity_score > 3 AND team_consensus = YES):
  → PROCEED with Phase 2B
ELSE:
  → KEEP UNIFIED, re-evaluate Aug 2026
```

---

## 📊 Metrics to Track

Create monthly snapshots (save to git):

```bash
# Run quarterly:
find shell-common/aliases -name "*.sh" | wc -l  # Record
find shell-common/functions -name "*.sh" | wc -l # Record
find shell-common/tools/integrations -name "*.sh" | wc -l # Record

# Performance baseline (optional):
time source bash/main.bash  # Record load time
```

**Q2 2026 Baseline (May 1):**
```
Aliases:      _____ (update on review date)
Functions:    _____ (update on review date)
Integrations: _____ (update on review date)
Load time:    _____ ms (update on review date)
```

---

## ✅ Pre-Implementation Checklist (If Phase 2 Approved)

### Phase 2A: Plugin Loader
- [ ] Write `loader_skip.conf` format spec
- [ ] Add conditional loading logic to `shell-common/util/loader.sh`
- [ ] Create tests for conditional loading
- [ ] Update `docs/AGENTS.md` with plugin loader docs
- [ ] Pre-commit hook: validate loader_skip.conf format
- [ ] Team training: "How to add environment-specific plugins"

### Phase 2B: UX Library Split
- [ ] Identify exact split points (avoid circular deps)
- [ ] Create 3 new files with clear responsibilities
- [ ] Add inter-module tests (src_a.sh → src_b.sh)
- [ ] Update all sourcing locations (6+ files)
- [ ] Performance regression test (verify load time)
- [ ] Update `shell-common/tools/ux_lib/README.md`

---

## 📝 Decision Record

**Date Decided:** 2026-02-09
**Decision:** DEFER Phase 2 until Q2 2026 review
**Rationale:** YAGNI principle - current scale doesn't justify overhead

**Who approved:**
- [ ] Architecture review
- [ ] Team lead
- [ ] Code owner (dotfiles)

**Review meeting date:** ___________
**Outcome:** ___________
**Next review:** ___________

---

## 🔗 Related Documents

- `docs/review/abc-review-C.md` – Initial Phase 2 analysis
- `docs/review/abc-review-CM.md` – CM's original SOLID review
- `docs/review/abc-review-R.md` – R's practical recommendations
- `shell-common/util/loader.sh` – Current auto-loader
- `shell-common/tools/ux_lib/ux_lib.sh` – Current UX library

---

## 📌 Notes

### Why not now?

> "The cost of adding these features now (complexity + maintenance overhead) exceeds the cost of adding them later when they're actually needed. By that time, we'll have clearer requirements and real pain points to guide design decisions."

### What if we never need it?

> "That's okay! We'll have made the right trade-off: kept the system simple and maintainable for 80% of the project's lifetime. Premature optimization is the root of all evil."

### How to know it's time?

> When team members spontaneously say:
> - "I wish I could load just the work aliases..."
> - "That UX library is getting unwieldy..."
> - "Can we make certain tools only load in specific environments?"

Then you'll know Phase 2 isn't just nice-to-have, it's necessary. ✨
