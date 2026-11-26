import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { PaneFilter, SkillRow, SkillsView } from '../types'

// F-12 (#2465): /skills-map pane over the engine bin/skills_map.py. Every read
// and write is an engine JSON/CLI call through $.process.run (the plugin bin/
// PATH reaches only the Bash tool's shell); settings are never written here.
const PANE = 'skills-map'
const STATES = ['on', 'name-only', 'user-only', 'off'] as const
const VERBS = new Set(['list', 'set', 'plugin', 'recommend', 'apply', 'status', 'sync'])
const NOTE = 'Changes take effect in a new session.'
const MAX_RECORDS = 500
const EMPTY: SkillsView = { skills: [], tokens: { current: 0, recommended: 0 }, recommend: '', error: '' }
const view = atom({ plugin: 'skills-map', key: 'view' } as const, EMPTY, { shape: 'view-1' })
// #2471: search text, view mode and plugin drill-down; reset on every pane open, never saved.
const FILTER0: PaneFilter = { q: '', mode: 'skills', plugin: '' }
const filter = atom({ plugin: 'skills-map', key: 'filter' } as const, FILTER0, { shape: 'filter-1' })
const FLAT = '(flat skills)'
// F-1: state badge colors (ThemeKey); name-only stays neutral, not dim.
const BADGE: Record<string, 'success' | 'warning' | 'error' | undefined> = { on: 'success', 'user-only': 'warning', off: 'error' }

type Rec = { skill: string; source: string; ts: string }
type Run = { exitCode: number; stdout: string; stderr: string }

// F-4: live skill.prompt records, merged by the engine via --with-store. The
// store is read on every call; a store failure leaves transcript counts only.
async function records($: any): Promise<Rec[] | undefined> {
  try {
    const v = await $.store.get('records')
    return Array.isArray(v) ? (v as Rec[]) : []
  } catch {
    return undefined
  }
}

async function engine($: any, args: string[], withStore = false): Promise<Run> {
  const argv = ['python3', '-I', `${$.plugin.root}/bin/skills_map.py`, ...args]
  const recs = withStore ? await records($) : undefined
  try {
    // /dev/stdin keeps the records off disk: no temp file to write or prune.
    if (recs && recs.length) {
      return await $.process.run([...argv, '--with-store', '/dev/stdin'], { stdin: JSON.stringify(recs), timeoutMs: 120_000 })
    }
    // stdin '' keeps the engine off any inherited TTY: confirm() refuses instead of hanging.
    return await $.process.run(argv, { stdin: '', timeoutMs: 120_000 })
  } catch (err) {
    return { exitCode: 1, stdout: '', stderr: String(err) }
  }
}

// stdout on success, else the engine's error text.
const output = (r: Run) =>
  r.exitCode === 0 ? r.stdout.trim() : (r.stderr || r.stdout).trim() || `exit ${r.exitCode}`
const tokensLine = (v: SkillsView) => `tokens ~${v.tokens.current} now, ~${v.tokens.recommended} recommended`

async function load($: any): Promise<SkillsView> {
  const [list, rec] = await Promise.all([engine($, ['list', '--json'], true), engine($, ['recommend'], true)])
  if (list.exitCode !== 0) return { ...EMPTY, error: output(list) }
  try {
    const j = JSON.parse(list.stdout)
    return { skills: j.skills, tokens: j.tokens, recommend: output(rec), error: '' }
  } catch {
    return { ...EMPTY, error: 'engine printed no JSON' }
  }
}

const show = (s: string) => (s === 'user-invocable-only' ? 'user-only' : s)
const group = (s: SkillRow) => (s.source.startsWith('plugin:') ? s.source.slice(7) : FLAT)
// F-4: pane order is (uses desc, name), never STATE, so a toggle leaves the row in place.
const byUse = (a: { name: string; uses: number }, b: { name: string; uses: number }) =>
  b.uses - a.uses || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0)

// F-2/F-3: case-insensitive substring per whitespace-separated term (AND) over
// the skill name and its plugin name, then the plugin drill-down (AND).
export function visible(skills: SkillRow[], f: PaneFilter): SkillRow[] {
  const terms = f.q.toLowerCase().split(/\s+/).filter(Boolean)
  return skills
    .filter(s => {
      // The FLAT label is display-only: matching it would make "skills"/"flat" hit every flat skill.
      const hay = `${s.name} ${group(s) === FLAT ? '' : group(s)}`.toLowerCase()
      return terms.every(t => hay.includes(t)) && (!f.plugin || group(s) === f.plugin)
    })
    .sort(byUse)
}

type Group = { name: string; skills: number; uses: number; tokens: number; pinned: number }
// F-3: one row per plugin (flat skills as one), summed over the skills passing the search.
export function groups(skills: SkillRow[]): Group[] {
  const m = new Map<string, Group>()
  for (const s of skills) {
    const g = m.get(group(s)) ?? { name: group(s), skills: 0, uses: 0, tokens: 0, pinned: 0 }
    g.skills += 1
    g.uses += s.uses
    g.tokens += s.tokens
    g.pinned += s.pinned_by.length ? 1 : 0
    m.set(g.name, g)
  }
  return [...m.values()].sort(byUse)
}

const cut = (s: string, n: number) => (s.length > n ? s.slice(0, Math.max(1, n - 1)) + '~' : s.padEnd(n))

// Text fallback where no pane is drawn (claude -p, Desktop over WSL/SSH):
// columns cut to fit the terminal width.
export function report(v: SkillsView, columns: number): string {
  if (v.error) return `skills-map: ${v.error}`
  const w = Math.max(12, Math.min(40, columns - 30))
  const head = `${cut('SKILL', w)} ${cut('STATE', 9)} ${'USES'.padStart(5)} ${'TOKENS'.padStart(7)}`
  const rows = v.skills.map(
    s => `${cut(s.name, w)} ${cut(show(s.state), 9)} ${String(s.uses).padStart(5)} ${String(s.tokens).padStart(7)}`,
  )
  return [head, ...rows, '', tokensLine(v), NOTE].join('\n')
}

// skill.prompt does a read-modify-write on the store; chaining keeps two
// near-simultaneous prompts (subagents) from dropping a record.
let pending: Promise<unknown> = Promise.resolve()

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'skills-map', description: 'Skill exposure map: usage, token cost, on/off toggles' })
    return next(e)
  })

  on('skill.prompt', async ($, e, next) => {
    const skill = e.pluginName && !e.skill.includes(':') ? `${e.pluginName}:${e.skill}` : e.skill
    pending = pending
      .then(async () => {
        const ts = new Date(await $.clock.now()).toISOString()
        const recs = (await records($)) ?? []
        await $.store.set('records', [...recs, { skill, source: String(e.source), ts }].slice(-MAX_RECORDS))
      })
      .catch(() => undefined) // never block a skill on usage bookkeeping
    await pending
    return next(e)
  })

  on('command.run', { command: 'skills-map' }, async ($, e) => {
    const args = e.args.trim().split(/\s+/).filter(Boolean)
    const verb = args[0]
    if (verb !== undefined) {
      if (!VERBS.has(verb)) return { text: `usage: /skills-map [${[...VERBS].join('|')} ...]`, isTextDisplayOnly: true }
      const r = await engine($, args, ['list', 'recommend', 'apply'].includes(verb))
      return { text: output(r), isTextDisplayOnly: true }
    }
    const v = await load($)
    await update($, view, () => v)
    await update($, filter, () => FILTER0)
    let placed = false
    try {
      placed = (await $.ui.open({ id: PANE, title: 'Skills map' })).isPlaced
    } catch {
      // no surface (claude -p): text report below
    }
    if (placed) return { text: 'skills-map pane opened.', isTextDisplayOnly: true }
    await $.ui.close({ id: PANE }).catch(() => undefined)
    return { text: report(v, e.presentation.columns), isTextDisplayOnly: true }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button, Input } = $.ui.resolve(e)
    const v = await read($, view)
    const f = await read($, filter)
    const set = (patch: Partial<PaneFilter>) => () => update($, filter, x => ({ ...x, ...patch }))
    const search = (q: string) => update($, filter, x => ({ ...x, q }))
    const toggle = (s: SkillRow, state: string) => async () => {
      const r = await engine($, ['set', s.name, state])
      await $.ui.toast(output(r))
      const next = await load($)
      await update($, view, () => next)
    }
    if (v.error) return <Text color="error">skills-map: {v.error}</Text>
    const rows = visible(v.skills, f.mode === 'plugins' ? { ...f, plugin: '' } : f)
    // Current state/mode: primary + ASCII marker; the others dim (no emoji or shape glyphs).
    const pick = (cur: boolean, label: string) => (cur ? { variant: 'primary' as const, label: `>${label}<` } : { dimColor: true, label })
    // Totals and the recommendation sit above the rows so a long list never pushes them out of view.
    return (
      <Box flexDirection="column">
        <Input key="q" placeholder="search skills or plugins" autoFocus value={f.q} onInput={search} onSubmit={search} />
        <Box flexDirection="row">
          {(['skills', 'plugins'] as const).map(m => (
            <Button key={`mode:${m}`} {...pick(f.mode === m, m)} onPress={set(m === 'plugins' ? { mode: m, plugin: '' } : { mode: m })} />
          ))}
        </Box>
        {f.mode === 'skills' && f.plugin ? (
          <Box flexDirection="row">
            <Text>plugin: {f.plugin} </Text>
            <Button key="chip:x" label="x" onPress={set({ plugin: '' })} />
            <Button key="chip:all" label="all" dimColor onPress={set({ plugin: '' })} />
          </Box>
        ) : null}
        <Text>{tokensLine(v)}</Text>
        <Text dimColor>{NOTE}</Text>
        <Text bold>Recommended</Text>
        <Text dimColor>{v.recommend || '(none)'}</Text>
        <Text bold>{f.mode === 'plugins' ? 'Plugins' : 'Skills'}</Text>
        {rows.length === 0 && f.q.trim() ? <Text dimColor>no match: {f.q}</Text> : null}
        {f.mode === 'plugins'
          ? groups(rows).map(g => (
              <Button key={`group:${g.name}`} onPress={set({ mode: 'skills', plugin: g.name })}>
                {g.name} <Text dimColor>{g.skills} skills {g.uses}u ~{g.tokens}t {g.pinned} pinned</Text>
              </Button>
            ))
          : rows.map(s => (
              <Box flexDirection="row" key={`row:${s.name}`}>
                <Text>
                  {s.name} <Text color={BADGE[show(s.state)]}>[{show(s.state)}]</Text>{' '}
                  <Text dimColor>{s.uses}u ~{s.tokens}t{s.pinned_by.length ? ' pinned' : ''}</Text>
                </Text>
                {s.source.startsWith('plugin:')
                  ? <Text dimColor> plugin</Text>
                  : STATES.map(st => (
                      <Button key={`${s.name}:${st}`} {...pick(st === show(s.state), st)} onPress={toggle(s, st)} />
                    ))}
              </Box>
            ))}
      </Box>
    )
  })
}
