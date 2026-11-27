// One engine row, as 'skills-map list --json' prints it (#2461 Decisions).
export type SkillRow = {
  name: string
  state: string
  source: string
  uses: number
  last_used: string | null
  tokens: number
  pinned_by: string[]
  description: string
}

// What the pane draws: the last list/recommend run, or the error that replaced it.
export type SkillsView = {
  skills: SkillRow[]
  tokens: { current: number; recommended: number }
  recommend: string
  error: string
}

// The pane's search text, view mode and plugin drill-down (#2471); never saved.
// #2474: help box (R-5), idle list expanded (R-6), the one open [?] or off-confirm row (R-7/R-8).
export type PaneFilter = { q: string; mode: 'skills' | 'plugins'; plugin: string; help: boolean; more: boolean; open: string }

declare module 'claude-code' {
  interface PluginState {
    'skills-map': { view: Shaped<SkillsView>; filter: Shaped<PaneFilter> }
  }
}
