import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { SkillRow, SkillsView } from '../types'

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
    return await $.process.run(argv, { timeoutMs: 120_000 })
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

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'skills-map', description: 'Skill exposure map: usage, token cost, on/off toggles' })
    return next(e)
  })

  on('skill.prompt', async ($, e, next) => {
    try {
      const skill = e.pluginName && !e.skill.includes(':') ? `${e.pluginName}:${e.skill}` : e.skill
      const ts = new Date(await $.clock.now()).toISOString()
      const recs = (await records($)) ?? []
      await $.store.set('records', [...recs, { skill, source: String(e.source), ts }].slice(-MAX_RECORDS))
    } catch {
      // never block a skill on usage bookkeeping
    }
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
    const { Box, Text, Button } = $.ui.resolve(e)
    const v = await read($, view)
    const toggle = (s: SkillRow, state: string) => async () => {
      const r = await engine($, ['set', s.name, state])
      await $.ui.toast(output(r))
      const next = await load($)
      await update($, view, () => next)
    }
    if (v.error) return <Text color="error">skills-map: {v.error}</Text>
    return (
      <Box flexDirection="column">
        {v.skills.map(s => (
          <Box flexDirection="row" key={`row:${s.name}`}>
            <Text>
              {s.name} <Text dimColor>[{show(s.state)}] {s.uses}u ~{s.tokens}t{s.pinned_by.length ? ' pinned' : ''}</Text>
            </Text>
            {s.name.includes(':')
              ? <Text dimColor> plugin</Text>
              : STATES.map(st => <Button key={`${s.name}:${st}`} label={st} onPress={toggle(s, st)} />)}
          </Box>
        ))}
        <Text bold>Recommended</Text>
        <Text dimColor>{v.recommend || '(none)'}</Text>
        <Text>{tokensLine(v)}</Text>
        <Text dimColor>{NOTE}</Text>
      </Box>
    )
  })
}
