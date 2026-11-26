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

declare module 'claude-code' {
  interface PluginState {
    'skills-map': { view: Shaped<SkillsView> }
  }
}
