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
// #2474: help/more/open (the one expanded [?] or off-confirm row) live here too, so a pane open folds them.
const FILTER0: PaneFilter = { q: '', mode: 'skills', plugin: '', help: false, more: false, open: '' }
const filter = atom({ plugin: 'skills-map', key: 'filter' } as const, FILTER0, { shape: 'filter-2' })
const FLAT = '(flat skills)'
// F-1: state badge colors (ThemeKey); name-only stays neutral, not dim.
const BADGE: Record<string, 'success' | 'warning' | 'error' | undefined> = { on: 'success', 'user-only': 'warning', off: 'error' }
// #2474 R-1: the one selection marker (U+2714) for mode, state and plugin buttons.
const MARK = '\u2714'
// R-5: one entry per STATES item, same order.
export const STATE_HELP = [
  "on         Claude reads this skill's name and description every turn and can call it by itself. Costs tokens.",
  'name-only  Only the name is listed. Claude can still call it; cheaper than on.',
  'user-only  Hidden from Claude. You can still run it with /name. Saves tokens.',
  'off        Disabled. Neither you nor Claude can run it.',
] as const
const PIN_HELP = [
  '* Pinned: other skills call this one, so it is kept visible to Claude.',
  '* Hiding it (user-only) would break them.',
  '* Use --force in the CLI to override.',
]
const IDLE_NOTE =
  'Plugins that work through hooks, statusline or MCP (caveman, ponytail, claude-hud, playwright ...) show 0 even when in use. Check before turning one off.'
const FOLD = '접기'
const BAR = 20

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

const commas = (n: number) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',')
const count = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`
const stats = (uses: number, tokens: number) => `${count(uses, 'use')}  ~${count(tokens, 'token')}`

// R-4: the pane's per-turn summary; report() keeps tokensLine. Colors: blue down, red up (KR stock style).
export function trend(now: number, rec: number) {
  const head = `Skill list per turn   ~${commas(now)} -> ~${commas(rec)}`
  const pctOf = (n: number) => (Math.round((n / now) * 1000) / 10).toFixed(1)
  const ofNow = now ? `${pctOf(rec)}% of now` : ''
  if (now === rec) return { head, change: 'no change', color: undefined, filled: 0, ofNow, changed: false }
  // now 0: no percentage to take, but a growth from nothing is still an increase.
  const pct = now ? ` (${rec < now ? '-' : '+'}${pctOf(Math.abs(now - rec))}%)` : ''
  const diff = commas(Math.abs(now - rec))
  return rec < now
    ? { head, change: `\u25bc ${diff}${pct}  saves context every turn`, color: 'suggestion' as const, filled: Math.min(BAR - 1, Math.ceil((rec / now) * BAR)), ofNow, changed: true }
    : { head, change: `\u25b2 ${diff}${pct}  adds context every turn`, color: 'error' as const, filled: BAR, ofNow, changed: true }
}

// R-6: names greedily packed into lines that, drawn as 'a, b,', fit width columns.
export function pack(names: string[], width: number): string[][] {
  const lines: string[][] = []
  for (const n of names) {
    const last = lines.at(-1)
    // +3: the ', ' joiner and the ',' a wrapped line ends with.
    if (last && last.join(', ').length + n.length + 3 <= width) last.push(n)
    else lines.push([n])
  }
  return lines
}

const show = (s: string) => (s === 'user-invocable-only' ? 'user-only' : s)
const group = (s: SkillRow) => (s.source.startsWith('plugin:') ? s.source.slice(7) : FLAT)
// F-4: pane order is (uses desc, name), never STATE, taken once at pane open; a toggle's
// reload keeps that order, so a row stays in place even if its use count moved meanwhile.
const byUse = (a: { name: string; uses: number }, b: { name: string; uses: number }) =>
  b.uses - a.uses || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0)

// F-2/F-3: case-insensitive fuzzy match per whitespace-separated term (AND) over
// the skill name and its plugin name, then the plugin drill-down (AND).
// fzf-style: a term matches as a substring (rank = its offset) or, failing that, as an
// in-order subsequence (rank = 1000 + span), so "grl" finds grill-me. -1 = no match.
function fuzzy(hay: string, t: string): number {
  const at = hay.indexOf(t)
  if (at >= 0) return at
  let first = -1
  let i = 0
  for (let j = 0; j < hay.length && i < t.length; j++) {
    if (hay[j] !== t[i]) continue
    if (first < 0) first = j
    i++
  }
  return i < t.length ? -1 : 1000 + (hay.lastIndexOf(t[t.length - 1]) >= 0 ? hay.length - first : 0)
}

function visible(skills: SkillRow[], f: PaneFilter): SkillRow[] {
  const terms = f.q.toLowerCase().split(/\s+/).filter(Boolean)
  const scored: [number, SkillRow][] = []
  for (const s of skills) {
    // The FLAT label is display-only: matching it would make "skills"/"flat" hit every flat skill.
    const g = group(s)
    if (f.plugin && g !== f.plugin) continue
    const hay = `${s.name} ${g === FLAT ? '' : g}`.toLowerCase()
    let score = 0
    for (const t of terms) {
      const r = fuzzy(hay, t)
      if (r < 0) { score = -1; break }
      score += r
    }
    if (score >= 0) scored.push([score, s])
  }
  // Array.sort is stable: with no query every score is 0 and the F-4 pane order stays.
  return scored.sort((a, b) => a[0] - b[0]).map(x => x[1])
}

type Group = { name: string; skills: number; uses: number; tokens: number; pinned: number }
// F-3: one row per plugin (flat skills as one), summed over the skills passing the search.
function groups(skills: SkillRow[]): Group[] {
  const m = new Map<string, Group>()
  for (const s of skills) {
    const name = group(s)
    const g = m.get(name) ?? { name, skills: 0, uses: 0, tokens: 0, pinned: 0 }
    g.skills += 1
    g.uses += s.uses
    g.tokens += s.tokens
    g.pinned += s.pinned_by.length ? 1 : 0
    m.set(g.name, g)
  }
  return [...m.values()].sort(byUse)
}

// R-6: enabled plugins (skills on) whose skills were never called; recommend's own line is dropped for this.
function idle(skills: SkillRow[]): string[] {
  return groups(skills)
    .filter(g => g.name !== FLAT && g.uses === 0 && skills.every(s => group(s) !== g.name || s.state === 'on'))
    .map(g => g.name)
    .sort()
}
const common = (xs: SkillRow[]) => (new Set(xs.map(x => show(x.state))).size === 1 ? show(xs[0]?.state ?? '') : '')

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
    await update($, view, () => ({ ...v, skills: [...v.skills].sort(byUse) }))
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
    // A filter change folds the open [?]/confirm row (R-7/R-8): it may no longer be listed.
    const set = (patch: Partial<PaneFilter>) => () => update($, filter, x => ({ ...x, open: '', ...patch }))
    const search = (q: string) => update($, filter, x => ({ ...x, q, open: x.q === q ? x.open : '' }))
    const flip = (open: string) => () => update($, filter, x => ({ ...x, open: x.open === open ? '' : open }))
    const reload = async () => {
      const next = await load($)
      const at = new Map(v.skills.map((x, i) => [x.name, i]))
      // Rows known before keep their slot; a new one (NaN gap) falls back to byUse.
      next.skills.sort((a, b) => (at.get(a.name) ?? Infinity) - (at.get(b.name) ?? Infinity) || byUse(a, b))
      await update($, view, () => next)
    }
    const act = (args: string[]) => async () => {
      await $.ui.toast(output(await engine($, args)))
      await update($, filter, x => ({ ...x, open: '' }))
      await reload()
    }
    // R-8 (flat skills): one set per listed flat skill (the search narrows it, as it does the row); a pinned one is skipped for user-only/off, as the engine refuses it.
    const setFlat = (state: string) => async () => {
      let done = 0
      let skipped = 0
      let failed = 0
      const hide = state === 'user-only' || state === 'off'
      for (const s of rows.filter(x => group(x) === FLAT)) {
        if (hide && s.pinned_by.length) skipped += 1
        else if ((await engine($, ['set', s.name, state])).exitCode !== 0) failed += 1
        else done += 1
      }
      // No engine bulk verb: a failure leaves the others applied; the toast names it and the reload shows the truth.
      await $.ui.toast(`${done} set, ${skipped} skipped (pinned)${failed ? `, ${failed} failed` : ''}`)
      await reload()
    }
    // R-1/R-2/R-8: the selected choice gets MARK + bold, the others dim.
    const choice = (key: string, cur: boolean, label: string, onPress: () => unknown) =>
      cur ? (
        <Button key={key} label={label} onPress={onPress}>
          <Text weight="bold">{`${MARK} ${label}`}</Text>
        </Button>
      ) : (
        <Button key={key} label={label} dimColor onPress={onPress} />
      )
    const noop = () => undefined
    if (v.error) return <Text color="error">skills-map: {v.error}</Text>
    const rows = visible(v.skills, f.mode === 'plugins' ? { ...f, plugin: '' } : f)
    const all = f.mode === 'skills' && f.plugin ? v.skills.filter(s => group(s) === f.plugin) : v.skills
    const full = new Map(groups(v.skills).map(g => [g.name, g]))
    const counter = f.mode === 'plugins' ? `${groups(rows).length} / ${full.size}` : `${rows.length} / ${all.length}`
    const tr = trend(v.tokens.current, v.tokens.recommended)
    const zero = idle(v.skills)
    const width = e.props.bodyColumns || 80
    // Folded: one line, narrowed so the "... +N" button fits beside it; the rest is N plugins.
    const head = pack(zero, width - 10)
    const more = head.length > 1 && !f.more
    const packed = more ? head.slice(0, 1) : pack(zero, width)
    const hidden = zero.length - head[0]?.length
    const recommend = v.recommend
      .split('\n')
      .filter(l => !l.startsWith('# plugins with 0 uses'))
      .join('\n')
    // Totals and the recommendation sit above the rows so a long list never pushes them out of view.
    return (
      <Box flexDirection="column">
        <Box borderStyle="round" flexDirection="row" justifyContent="space-between">
          <Input key="q" label="Search" placeholder="type a skill or plugin name" submitLabel="done" autoFocus value={f.q} onInput={search} onSubmit={search} />
          {f.q ? <Button key="q:clear" label="clear" onPress={set({ q: '' })} /> : null}
          <Text dimColor>{counter}</Text>
        </Box>
        <Box flexDirection="row">
          {(['skills', 'plugins'] as const).map(m => choice(`mode:${m}`, f.mode === m, m, set(m === 'plugins' ? { mode: m, plugin: '' } : { mode: m })))}
        </Box>
        {f.mode === 'skills' && f.plugin ? (
          <Box flexDirection="row">
            <Text>plugin: {f.plugin} </Text>
            <Button key="chip:x" label="x" onPress={set({ plugin: '' })} />
            <Button key="chip:all" label="all" dimColor onPress={set({ plugin: '' })} />
          </Box>
        ) : null}
        <Box flexDirection="row">
          <Text>
            {tr.head}   <Text color={tr.color} dimColor={!tr.changed}>{tr.change}</Text>{' '}
          </Text>
          <Button key="help" label={f.help ? FOLD : '?'} onPress={() => update($, filter, x => ({ ...x, help: !x.help }))} />
        </Box>
        <Text>
          <Text color={tr.color}>{'\u2588'.repeat(tr.filled)}</Text>
          <Text dimColor>{'\u2591'.repeat(BAR - tr.filled)}</Text>
          {tr.ofNow ? `   ${tr.ofNow}` : ''}
        </Text>
        {tr.changed ? <Text color="warning">Applies from the next new session.</Text> : null}
        {f.help ? (
          <Box key="help-box" borderStyle="round" flexDirection="column">
            <Text weight="bold">What do the states mean?</Text>
            {STATE_HELP.map(line => (
              <Text key={`help:${line.split(' ')[0]}`}>{line}</Text>
            ))}
            <Text weight="bold">Recommended</Text>
            <Text dimColor>{recommend || '(none)'}</Text>
          </Box>
        ) : null}
        {zero.length ? (
          <Box flexDirection="column">
            <Text>{count(zero.length, 'plugin')} with no skill calls in 30d</Text>
            <Text dimColor>{IDLE_NOTE}</Text>
            {more ? (
              <Box flexDirection="row">
                <Text>{packed[0].join(', ') + ','} </Text>
                <Button key="idle:more" label={`... +${hidden}`} dimColor onPress={() => update($, filter, x => ({ ...x, more: !x.more }))} />
              </Box>
            ) : (
              packed.map((l, i) => (
                <Text key={`idle:${i}`}>{l.join(', ') + (i < packed.length - 1 ? ',' : '')}</Text>
              ))
            )}
            {!more && head.length > 1 ? (
              <Button key="idle:more" label="less" dimColor onPress={() => update($, filter, x => ({ ...x, more: !x.more }))} />
            ) : null}
          </Box>
        ) : null}
        <Text weight="bold">{f.mode === 'plugins' ? 'Plugins' : 'Skills'}</Text>
        {f.mode === 'plugins' && f.q.trim() ? <Text dimColor>totals over skills matching: {f.q}</Text> : null}
        {rows.length === 0 && f.q.trim() ? <Text dimColor>no match: {f.q}</Text> : null}
        {f.mode === 'plugins'
          ? groups(rows).flatMap(g => {
              const mine = v.skills.filter(s => group(s) === g.name)
              const cur = common(mine)
              const whole = full.get(g.name) ?? g
              // Engine plugin_pins: only referrers outside the plugin lock it.
              const outside = [...new Set(mine.flatMap(s => s.pinned_by).filter(who => !who.startsWith(`${g.name}:`)))].sort()
              const locked = g.name !== FLAT && outside.length > 0 && cur !== 'off'
              return [
                <Box flexDirection="row" key={`prow:${g.name}`}>
                  <Button key={`group:${g.name}`} onPress={set({ mode: 'skills', plugin: g.name })}>
                    {g.name}{'  '}<Text dimColor>{`${count(g.skills, 'skill')}  ${stats(g.uses, g.tokens)}  ${g.pinned} pinned`}</Text>
                  </Button>
                  {g.name === FLAT
                    ? STATES.map(st => choice(`flat:${st}`, cur === st, st, setFlat(st)))
                    : [
                        choice(`on:${g.name}`, cur === 'on', 'on', cur === 'on' ? noop : act(['plugin', g.name, 'on'])),
                        locked ? (
                          <Text key={`locked:${g.name}`} dimColor> off (locked)</Text>
                        ) : (
                          choice(`off:${g.name}`, cur === 'off', 'off', cur === 'off' ? noop : flip(`off:${g.name}`))
                        ),
                      ]}
                </Box>,
                locked ? (
                  <Box key={`lock:${g.name}`} flexDirection="row">
                    <Text dimColor>  Pinned by other skills. Use the CLI with --force. </Text>
                    <Button key={`pin:${g.name}`} label={f.open === `pin:${g.name}` ? FOLD : '?'} onPress={flip(`pin:${g.name}`)} />
                  </Box>
                ) : null,
                locked && f.open === `pin:${g.name}` ? (
                  <Text key={`pinned:${g.name}`}>{`    Referenced by: ${outside.join(', ')}`}</Text>
                ) : null,
                f.open === `off:${g.name}` ? (
                  <Box key={`confirm:${g.name}`} flexDirection="column" paddingLeft={2}>
                    <Text>{`Turn off "${g.name}"? ${count(whole.skills, 'skill')} ${whole.skills === 1 ? 'leaves' : 'leave'} the / menu. ${count(whole.uses, 'use')} in 30d.`}</Text>
                    <Box flexDirection="row">
                      <Button key={`confirm-off:${g.name}`} label="Confirm off" onPress={act(['plugin', g.name, 'off', '--yes'])} />
                      <Button key={`cancel:${g.name}`} label="Cancel" dimColor onPress={flip(`off:${g.name}`)} />
                    </Box>
                  </Box>
                ) : null,
              ]
            })
          : rows.flatMap(s => [
              <Box flexDirection="row" key={`row:${s.name}`}>
                <Text>
                  {s.name}  <Text color={BADGE[show(s.state)]}>[{show(s.state)}]</Text>{'  '}
                  <Text dimColor>{stats(s.uses, s.tokens) + (s.pinned_by.length ? `  pinned x${s.pinned_by.length} ` : '')}</Text>
                </Text>
                {s.pinned_by.length ? <Button key={`pin:${s.name}`} label={f.open === `pin:${s.name}` ? FOLD : '?'} onPress={flip(`pin:${s.name}`)} /> : null}
                {s.source.startsWith('plugin:')
                  ? <Text dimColor>  plugin</Text>
                  : STATES.map(st => choice(`${s.name}:${st}`, st === show(s.state), st, act(['set', s.name, st])))}
              </Box>,
              f.open === `pin:${s.name}` ? (
                <Box key={`pinned:${s.name}`} flexDirection="column" paddingLeft={2}>
                  {PIN_HELP.map((line, i) => (
                    <Text key={`pinhelp:${i}`}>{line}</Text>
                  ))}
                  <Text>{`* Referenced by (${s.pinned_by.length}):`}</Text>
                  <Text>{`    ${s.pinned_by.join(', ')}`}</Text>
                </Box>
              ) : null,
            ])}
      </Box>
    )
  })
}
