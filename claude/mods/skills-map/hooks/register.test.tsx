import { expect, mock, test } from 'claude-code/testing'

import { STATE_HELP, pack, trend } from './register'

const MARK = '\u2714'

const LIST = {
  skills: [
    { name: 'commit', state: 'on', source: 'skill', uses: 3, last_used: null, tokens: 40, pinned_by: [], description: 'd' },
    { name: 'gh:pr', state: 'on', source: 'plugin:gh', uses: 0, last_used: null, tokens: 20, pinned_by: [], description: 'd' },
  ],
  tokens: { current: 60, recommended: 40 },
}
// #2471 pane fixture: two flat skills tied on uses (name breaks the tie), one plugin.
const MANY = {
  skills: [
    { name: 'review', state: 'off', source: 'skill', uses: 3, last_used: null, tokens: 30, pinned_by: [], description: 'd' },
    { name: 'gh:issue', state: 'on', source: 'plugin:gh', uses: 5, last_used: null, tokens: 25, pinned_by: ['x'], description: 'd' },
    ...LIST.skills,
    { name: 'tidy', state: 'name-only', source: 'skill', uses: 0, last_used: null, tokens: 10, pinned_by: [], description: 'd' },
  ],
  tokens: { current: 125, recommended: 40 },
}
const PANE = {
  plugin: 'skills-map',
  component: 'Pane',
  requestId: 'skills-map',
  props: { title: 'Skills map', isFocused: false, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const

// Wires the engine beneath the plugin: command registry, panes, and a fake
// bin/skills_map.py answering by verb. Every argv and stdin is recorded.
function world(on: any, placed: boolean, list: { skills: any[]; tokens: typeof LIST.tokens } = LIST) {
  const runs: { argv: readonly string[]; stdin?: string }[] & { toasts: unknown[] } = Object.assign([], { toasts: [] })
  const skills = list.skills.map(s => ({ ...s }))
  on('command.register', () => ({ value: { command: 'skills-map' } }))
  on('ui.open', () => ({ value: placed ? { isPlaced: true } : { isPlaced: false, reason: 'no-surface' } }))
  on('ui.close', () => ({ value: undefined }))
  on('ui.toast', (_$: any, e: any) => {
    runs.toasts.push(e)
    return { value: undefined }
  })
  on('session.start', (_$: any, e: any) => ({ cwd: e.cwd }))
  on('skill.prompt', (_$: any, e: any) => ({ text: e.text }))
  on('process.run', (_$: any, e: any) => {
    runs.push({ argv: e.argv, stdin: e.init?.stdin })
    const verb = e.argv[3]
    // set flips the fake engine's state, so the next list reflects the toggle.
    // and bumps its uses, as a skill run elsewhere would between two loads.
    if (verb === 'set') Object.assign(skills.find(s => s.name === e.argv[4])!, { state: e.argv[5], uses: 99 })
    const stdout = verb === 'list' ? JSON.stringify({ ...list, skills }) : verb === 'recommend' ? "# per-turn listing ~60 -> ~40 tokens\n# plugins with 0 uses in 30d ('skills-map plugin <name> off'): gh" : 'commit: off (takes effect in a new session)'
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  return runs
}

const run = ($: any, args = '') =>
  $.command.run({ command: 'skills-map', args, presentation: { isFullscreen: false, columns: 80 } } as any)

test('headless /skills-map prints a text report, display-only', async ($, on) => {
  const runs = world(on, false)
  mock.store(on)
  const r = await run($)
  expect(r.isTextDisplayOnly).toBe(true)
  expect(r.text).toContain('commit')
  expect(r.text).toContain('tokens ~60 now, ~40 recommended')
  expect(runs[0]?.argv.slice(0, 2)).toEqual(['python3', '-I'])
  expect(runs[0]?.argv[2]).toMatch(/\/bin\/skills_map\.py$/)
})

test('skill.prompt records reach the engine through --with-store /dev/stdin', async ($, on) => {
  const runs = world(on, false)
  mock.store(on)
  mock.clock(on, { now: 1_700_000_000_000 })
  await $.skill.prompt({ skill: 'pr', pluginName: 'gh', text: 't', frontmatter: {}, source: 'plugin' } as any)
  await run($)
  const list = runs.find(r => r.argv[3] === 'list')!
  expect(list.argv.slice(-2)).toEqual(['--with-store', '/dev/stdin'])
  expect(JSON.parse(list.stdin!)).toEqual([{ skill: 'gh:pr', source: 'plugin', ts: '2023-11-14T22:13:20.000Z' }])
})

test('two concurrent skill.prompt records both land', async ($, on) => {
  const runs = world(on, false)
  mock.store(on)
  mock.clock(on, { now: 1_700_000_000_000 })
  const p = (skill: string) => $.skill.prompt({ skill, text: 't', frontmatter: {}, source: 'userSettings' } as any)
  await Promise.all([p('a'), p('b')])
  await run($)
  const list = runs.find(r => r.argv[3] === 'list')!
  expect(JSON.parse(list.stdin!).map((r: any) => r.skill).sort()).toEqual(['a', 'b'])
})

test('a failing store leaves transcript counts only', async ($, on) => {
  const runs = world(on, false)
  on('store.get', () => ({ deny: 'EIO' }))
  const r = await run($)
  expect(r.text).toContain('commit')
  expect(runs.every(x => !x.argv.includes('--with-store'))).toBe(true)
})

test('/skills-map set passes through to the engine, display-only', async ($, on) => {
  const runs = world(on, false)
  mock.store(on)
  const r = await run($, 'set commit off')
  expect(runs.map(x => x.argv.slice(3))).toEqual([['set', 'commit', 'off']])
  expect(runs[0]?.stdin).toBe('') // never an inherited TTY for confirm()
  expect(r).toEqual({ text: 'commit: off (takes effect in a new session)', isTextDisplayOnly: true })
})

test('an unknown verb is refused without running the engine', async ($, on) => {
  const runs = world(on, false)
  const r = await run($, 'rm -rf')
  expect(r.text).toContain('usage:')
  expect(runs).toEqual([])
})

test('the pane lists skills and a toggle runs the engine set', async ($, on) => {
  const runs = world(on, true)
  mock.store(on)
  const r = await run($)
  expect(r.text).toBe('skills-map pane opened.')
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /Skill list per turn {3}~60 -> ~40/ })).toBeDefined()
  expect(await ui.find({ key: 'gh:pr:off' })).toBeUndefined()
  expect((await ui.find({ key: 'commit:on' }))?.text).toBe(`${MARK} on`)
  await ui.press({ key: 'commit:off' })
  expect(runs.some(x => x.argv.slice(3).join(' ') === 'set commit off')).toBe(true)
  await ui.unmount()
})

async function pane($: any, on: any, list: { skills: any[]; tokens: typeof LIST.tokens } = MANY) {
  const runs = world(on, true, list)
  mock.store(on)
  await run($)
  return { runs, ui: await $.ui.mount({ ...PANE, surface: 'terminal' }) }
}
// R-1/R-2: the selected button reads MARK + label in a bold Text and is not dim; the others are plain and dim.
async function style(ui: any, key: string) {
  const b = await ui.find({ key })
  return {
    marked: b.text.includes(MARK) && b.children.some((c: any) => c?.props?.weight === 'bold'),
    dim: b.props.dimColor === true,
    arrows: /[<>]/.test(b.text),
  }
}
const SEL = { marked: true, dim: false, arrows: false }
const OFF = { marked: false, dim: true, arrows: false }
const texts = async (ui: any) => (await ui.findAll({ type: 'Text' })).map((t: any) => t.text)
const order = async (ui: any) => (await ui.findAll({ type: 'Box' })).map((b: any) => b.key).filter((k: any) => k?.startsWith('row:'))

test('the current state gets a colored badge and the marked bold button', async ($, on) => {
  const { ui } = await pane($, on)
  expect(await style(ui, 'commit:on')).toEqual(SEL)
  expect(await style(ui, 'commit:off')).toEqual(OFF)
  const badges = async (t: string) => (await ui.findAll({ type: 'Text', text: new RegExp(`^\\[${t}\\]$`) })).map((x: any) => x.props.color)
  expect(await badges('off')).toEqual(['error'])
  expect(await badges('name-only')).toEqual([undefined])
  expect(await badges('on')).toEqual(['success', 'success', 'success'])
  await ui.unmount()
})

test('the search Input filters by skill or plugin name, terms ANDed', async ($, on) => {
  const { ui } = await pane($, on)
  expect(await order(ui)).toEqual(['row:gh:issue', 'row:commit', 'row:review', 'row:gh:pr', 'row:tidy'])
  await ui.input({ key: 'q', text: 'REV', kind: 'change' })
  expect(await order(ui)).toEqual(['row:review'])
  await ui.input({ key: 'q', text: 'gh is', kind: 'change' })
  expect(await order(ui)).toEqual(['row:gh:issue'])
  await ui.input({ key: 'q', text: 'zzz', kind: 'change' })
  expect(await order(ui)).toEqual([])
  expect(await ui.find({ type: 'Text', text: /no match: zzz/ })).toBeDefined()
  await ui.input({ key: 'q', text: '', kind: 'change' })
  expect((await order(ui)).length).toBe(5)
  await ui.unmount()
})

test('plugins mode lists one row per plugin and drills down behind a chip', async ($, on) => {
  const { ui } = await pane($, on)
  expect(await style(ui, 'mode:skills')).toEqual(SEL)
  await ui.press({ key: 'mode:plugins' })
  const rows = (await ui.findAll({ type: 'Button' })).filter((b: any) => b.key?.startsWith('group:'))
  expect(rows.map((b: any) => b.key)).toEqual(['group:(flat skills)', 'group:gh'])
  expect(rows[1].text).toContain('gh  2 skills  5 uses  ~45 tokens  1 pinned')
  await ui.press({ key: 'group:gh' })
  expect(await order(ui)).toEqual(['row:gh:issue', 'row:gh:pr'])
  expect(await ui.find({ type: 'Text', text: /plugin: gh/ })).toBeDefined()
  await ui.input({ key: 'q', text: 'pr', kind: 'change' })
  expect(await order(ui)).toEqual(['row:gh:pr'])
  await ui.press({ key: 'chip:x' })
  expect(await ui.find({ key: 'chip:x' })).toBeUndefined()
  expect(await order(ui)).toEqual(['row:gh:pr'])
  await ui.press({ key: 'mode:plugins' })
  await ui.press({ key: 'group:gh' })
  await ui.press({ key: 'mode:plugins' })
  await ui.press({ key: 'mode:skills' })
  expect(await ui.find({ key: 'chip:all' })).toBeUndefined()
  await ui.unmount()
})

test('flat skills drill down as one group; plugin sums follow the search', async ($, on) => {
  const { ui } = await pane($, on)
  await ui.press({ key: 'mode:plugins' })
  await ui.press({ key: 'group:(flat skills)' })
  expect(await order(ui)).toEqual(['row:commit', 'row:review', 'row:tidy'])
  await ui.press({ key: 'mode:plugins' })
  await ui.input({ key: 'q', text: 'gh pr', kind: 'change' })
  expect(await ui.find({ type: 'Text', text: /totals over skills matching: gh pr/ })).toBeDefined()
  const gh = await ui.find({ key: 'group:gh' })
  expect(gh?.text).toContain('gh  1 skill  0 uses  ~20 tokens  0 pinned')
  expect(await ui.find({ key: 'group:(flat skills)' })).toBeUndefined()
  await ui.unmount()
})

test('a toggle keeps the row order and the search text', async ($, on) => {
  const { runs, ui } = await pane($, on)
  const before = await order(ui)
  await ui.press({ key: 'commit:off' })
  expect(runs.some(x => x.argv.slice(3).join(' ') === 'set commit off')).toBe(true)
  expect(await style(ui, 'commit:off')).toEqual(SEL)
  expect(await order(ui)).toEqual(before)
  await ui.input({ key: 'q', text: 'review', kind: 'change' })
  await ui.press({ key: 'review:on' })
  expect(await order(ui)).toEqual(['row:review'])
  expect((await ui.find({ key: 'q' }))?.props.value).toBe('review')
  await ui.unmount()
})

test('R-1 mode buttons: the selected one is marked and bold, the other dim; re-pressing keeps it', async ($, on) => {
  const { ui } = await pane($, on)
  expect(await style(ui, 'mode:skills')).toEqual(SEL)
  expect(await style(ui, 'mode:plugins')).toEqual(OFF)
  await ui.press({ key: 'mode:skills' })
  expect(await style(ui, 'mode:skills')).toEqual(SEL)
  await ui.press({ key: 'mode:plugins' })
  expect(await style(ui, 'mode:plugins')).toEqual(SEL)
  expect(await style(ui, 'mode:skills')).toEqual(OFF)
  await ui.unmount()
})

test('R-2 state toggles: only the current state of the four is marked, for each state', async ($, on) => {
  const { ui } = await pane($, on)
  for (const cur of ['on', 'name-only', 'user-only', 'off']) {
    await ui.press({ key: `commit:${cur}` })
    for (const st of ['on', 'name-only', 'user-only', 'off']) expect(await style(ui, `commit:${st}`)).toEqual(st === cur ? SEL : OFF)
  }
  await ui.unmount()
})

test('R-3 the search box wraps the Input and counts visible over total', async ($, on) => {
  const { ui } = await pane($, on)
  const input = await ui.find({ key: 'q' })
  expect(input?.props.submitLabel).toBe('done')
  expect(input?.props.label).toBe('Search')
  expect(input?.props.placeholder).toBe('type a skill or plugin name')
  const box = (await ui.findAll({ type: 'Box' })).find((b: any) => b.props.borderStyle === 'round')
  expect(box.children.some((c: any) => c?.type === 'Input')).toBe(true)
  const counter = async () => (await ui.find({ type: 'Text', text: /^\d+ \/ \d+$/ }))?.text
  expect(await counter()).toBe('5 / 5')
  await ui.input({ key: 'q', text: 'gh', kind: 'change' })
  expect(await counter()).toBe('2 / 5')
  await ui.input({ key: 'q', text: 'zzz', kind: 'change' })
  expect(await counter()).toBe('0 / 5')
  await ui.input({ key: 'q', text: 'zzz', kind: 'submit' })
  expect((await ui.find({ key: 'q' }))?.props.value).toBe('zzz')
  await ui.input({ key: 'q', text: '', kind: 'change' })
  await ui.press({ key: 'mode:plugins' })
  expect(await counter()).toBe('2 / 2')
  await ui.press({ key: 'group:gh' })
  await ui.input({ key: 'q', text: 'pr', kind: 'change' })
  expect(await counter()).toBe('1 / 2')
  await ui.unmount()
})

test('R-4 trend: down, up, equal and zero; commas and one decimal', () => {
  expect(trend(18010, 17564)).toEqual({
    head: 'Skill list per turn   ~18,010 -> ~17,564',
    change: '\u25bc 446 (-2.5%)  saves context every turn',
    color: 'suggestion',
    filled: 19,
    ofNow: '97.5% of now',
    changed: true,
  })
  expect(trend(1000, 500)).toMatchObject({ filled: 10, ofNow: '50.0% of now' })
  expect(trend(1000, 1500)).toEqual({
    head: 'Skill list per turn   ~1,000 -> ~1,500',
    change: '\u25b2 500 (+50.0%)  adds context every turn',
    color: 'error',
    filled: 20,
    ofNow: '150.0% of now',
    changed: true,
  })
  expect(trend(40, 40)).toMatchObject({ change: 'no change', color: undefined, filled: 0, changed: false })
  expect(trend(0, 0)).toMatchObject({ change: 'no change', filled: 0, ofNow: '', changed: false })
})

test('R-4 the pane draws the summary, the bar and the yellow note only on a change', async ($, on) => {
  const { ui } = await pane($, on)
  expect(await ui.find({ type: 'Text', text: /^\u25bc 85 \(-68\.0%\) {2}saves context every turn$/ })).toMatchObject({ props: { color: 'suggestion' } })
  expect((await ui.find({ type: 'Text', text: /^\u2588+$/ }))?.text.length).toBe(7)
  expect((await ui.find({ type: 'Text', text: /^\u2591+$/ }))?.text.length).toBe(13)
  expect(await ui.find({ type: 'Text', text: 'Applies from the next new session.' })).toMatchObject({ props: { color: 'warning' } })
  expect(await texts(ui)).not.toContainEqual(expect.stringContaining('tokens ~'))
  await ui.unmount()
})

test('R-4 no change: dim, no arrow, no yellow note', async ($, on) => {
  const { ui } = await pane($, on, { ...MANY, tokens: { current: 40, recommended: 40 } })
  expect(await ui.find({ type: 'Text', text: /^no change$/ })).toMatchObject({ props: { dimColor: true } })
  expect(await ui.find({ type: 'Text', text: /Applies from/ })).toBeUndefined()
  expect((await ui.find({ type: 'Text', text: /^\u2591+$/ }))?.text.length).toBe(20)
  await ui.unmount()
})

test('R-5 one ? on the summary line toggles the state help; a pane open folds it', async ($, on) => {
  const { ui } = await pane($, on)
  const before = await order(ui)
  expect((await ui.findAll({ type: 'Button' })).filter((b: any) => b.key === 'help')).toHaveLength(1)
  expect(await ui.find({ key: 'help-box' })).toBeUndefined()
  await ui.press({ key: 'help' })
  const box = await ui.find({ key: 'help-box' })
  expect(box?.props.borderStyle).toBe('round')
  const shown = await texts(ui)
  expect(shown).toContain('What do the states mean?')
  for (const h of STATE_HELP) expect(shown).toContain(h)
  expect(STATE_HELP.map(h => h.split(' ')[0])).toEqual(['on', 'name-only', 'user-only', 'off'])
  expect(await order(ui)).toEqual(before)
  expect(await style(ui, 'mode:skills')).toEqual(SEL)
  await ui.press({ key: 'help' })
  expect(await ui.find({ key: 'help-box' })).toBeUndefined()
  await ui.press({ key: 'help' })
  await run($)
  expect(await ui.find({ key: 'help-box' })).toBeUndefined()
  await ui.unmount()
})

// R-6: 35 enabled plugins, one never-called skill each, beside MANY (gh is used).
const IDLE = {
  ...MANY,
  skills: [
    ...MANY.skills,
    ...Array.from({ length: 35 }, (_, i) => {
      const p = `plugin-${String(i + 1).padStart(2, '0')}`
      return { name: `${p}:s`, state: 'on', source: `plugin:${p}`, uses: 0, last_used: null, tokens: 1, pinned_by: [], description: 'd' }
    }),
  ],
}

test('R-6 pack fills lines up to the width', () => {
  const names = IDLE.skills.slice(5).map(s => s.source.slice(7))
  const lines = pack(names, 80)
  expect(lines.every(l => `${l.join(', ')},`.length <= 80)).toBe(true)
  expect(lines.flat()).toEqual(names)
  expect(lines).toHaveLength(5)
  expect(pack(['a', 'b'], 80)).toEqual([['a', 'b']])
  expect(pack(['aaaa', 'bbbb'], 8)).toEqual([['aaaa'], ['bbbb']])
})

test('R-6 idle plugins fold to three lines behind ... +N, and less folds them back', async ($, on) => {
  const { ui } = await pane($, on, IDLE)
  const shown = await texts(ui)
  expect(shown).toContain('35 plugins with no skill calls in 30d')
  expect(shown.some((t: string) => t.includes('hooks, statusline or MCP'))).toBe(true)
  expect(shown.some((t: string) => t.includes('# plugins with 0 uses'))).toBe(false)
  const lines = async () => (await texts(ui)).filter((t: string) => /^plugin-\d\d, /.test(t))
  expect(await lines()).toHaveLength(3)
  expect((await ui.find({ key: 'idle:more' }))?.text).toBe('... +14')
  await ui.press({ key: 'idle:more' })
  expect(await lines()).toHaveLength(5)
  expect((await ui.find({ key: 'idle:more' }))?.text).toBe('less')
  await ui.press({ key: 'idle:more' })
  expect(await lines()).toHaveLength(3)
  await ui.unmount()
})

test('R-6 a short idle list has no expand button', async ($, on) => {
  const { ui } = await pane($, on, { ...IDLE, skills: IDLE.skills.slice(0, 8) })
  expect(await texts(ui)).toContain('3 plugins with no skill calls in 30d')
  expect(await ui.find({ key: 'idle:more' })).toBeUndefined()
  await ui.unmount()
})

const PINS = {
  skills: [
    { name: 'alpha', state: 'on', source: 'skill', uses: 1, last_used: null, tokens: 10, pinned_by: ['p1', 'p2', 'p3'], description: 'd' },
    { name: 'beta', state: 'on', source: 'skill', uses: 0, last_used: null, tokens: 12, pinned_by: ['q'], description: 'd' },
    { name: 'gamma', state: 'on', source: 'skill', uses: 2, last_used: null, tokens: 1, pinned_by: [], description: 'd' },
  ],
  tokens: { current: 23, recommended: 23 },
}

test('R-7 rows spell out uses and tokens; only pinned rows get pinned xN [?]', async ($, on) => {
  const { ui } = await pane($, on, PINS)
  const shown = await texts(ui)
  expect(shown).toContain('1 use  ~10 tokens  pinned x3 ')
  expect(shown).toContain('2 uses  ~1 token')
  expect(shown.some((t: string) => /\d+[ut]\b/.test(t))).toBe(false)
  expect((await ui.find({ key: 'pin:alpha' }))?.text).toBe('?')
  expect(await ui.find({ key: 'pin:gamma' })).toBeUndefined()
  await ui.unmount()
})

test('R-7 [?] is an accordion that a filter change or a pane open folds', async ($, on) => {
  const { ui } = await pane($, on, PINS)
  await ui.press({ key: 'pin:alpha' })
  const shown = await texts(ui)
  expect(shown).toContain('Pinned: other skills call this one, so it is kept visible to Claude.')
  expect(shown).toContain('Referenced by (3): p1, p2, p3')
  await ui.press({ key: 'pin:beta' })
  expect(await ui.find({ key: 'pinned:alpha' })).toBeUndefined()
  expect(await texts(ui)).toContain('Referenced by (1): q')
  await ui.press({ key: 'pin:beta' })
  expect(await ui.find({ key: 'pinned:beta' })).toBeUndefined()
  await ui.press({ key: 'pin:alpha' })
  await ui.input({ key: 'q', text: 'beta', kind: 'change' })
  await ui.input({ key: 'q', text: '', kind: 'change' })
  expect(await ui.find({ key: 'pinned:alpha' })).toBeUndefined()
  await ui.press({ key: 'pin:alpha' })
  await run($)
  expect(await ui.find({ key: 'pinned:alpha' })).toBeUndefined()
  await ui.unmount()
})

const sk = (name: string, source: string, extra: object = {}) =>
  ({ name, state: 'on', source, uses: 0, last_used: null, tokens: 20, pinned_by: [] as string[], description: 'd', ...extra })
const PLUGS = {
  skills: [
    sk('gh:issue', 'plugin:gh', { uses: 5, pinned_by: ['x'] }),
    sk('tools:a', 'plugin:tools'),
    sk('more:a', 'plugin:more'),
    sk('more:b', 'plugin:more', { uses: 1 }),
    sk('old:a', 'plugin:old', { state: 'off' }),
    sk('commit', 'skill'),
    sk('review', 'skill', { pinned_by: ['z'] }),
    sk('tidy', 'skill'),
  ],
  tokens: { current: 160, recommended: 160 },
}
const plugRuns = (runs: any[]) => runs.filter(r => r.argv[3] === 'plugin').map(r => r.argv.slice(3))

test('R-8 plugin rows spell out counts and carry on/off with the current one marked', async ($, on) => {
  const { ui } = await pane($, on, PLUGS)
  await ui.press({ key: 'mode:plugins' })
  expect((await ui.find({ key: 'group:tools' }))?.text).toBe('tools  1 skill  0 uses  ~20 tokens  0 pinned')
  expect((await ui.find({ key: 'group:more' }))?.text).toBe('more  2 skills  1 use  ~40 tokens  0 pinned')
  const row = (await ui.findAll({ type: 'Box' })).find((b: any) => b.key === 'prow:tools')
  expect(row.children.filter((c: any) => c?.type === 'Button').map((c: any) => c.props.key)).toEqual(['group:tools', 'on:tools', 'off:tools'])
  expect(await style(ui, 'on:tools')).toEqual(SEL)
  expect(await style(ui, 'off:tools')).toEqual(OFF)
  expect(await style(ui, 'off:old')).toEqual(SEL)
  expect(await style(ui, 'on:old')).toEqual(OFF)
  await ui.unmount()
})

test('R-8 off asks inline first; Confirm runs plugin off --yes, Cancel runs nothing; on runs at once', async ($, on) => {
  const { runs, ui } = await pane($, on, PLUGS)
  await ui.press({ key: 'mode:plugins' })
  await ui.press({ key: 'off:tools' })
  expect(await texts(ui)).toContain('Turn off "tools"? 1 skill leaves the / menu. 0 uses in 30d.')
  expect(plugRuns(runs)).toEqual([])
  await ui.press({ key: 'cancel:tools' })
  expect(await ui.find({ key: 'confirm:tools' })).toBeUndefined()
  expect(plugRuns(runs)).toEqual([])
  await ui.press({ key: 'off:tools' })
  await ui.press({ key: 'off:more' })
  expect(await ui.find({ key: 'confirm:tools' })).toBeUndefined()
  expect(await texts(ui)).toContain('Turn off "more"? 2 skills leave the / menu. 1 use in 30d.')
  await ui.press({ key: 'confirm-off:more' })
  expect(plugRuns(runs)).toEqual([['plugin', 'more', 'off', '--yes']])
  expect(await ui.find({ key: 'confirm:more' })).toBeUndefined()
  await ui.press({ key: 'on:old' })
  expect(plugRuns(runs)).toEqual([['plugin', 'more', 'off', '--yes'], ['plugin', 'old', 'on']])
  await ui.unmount()
})

test('R-8 a pinned plugin shows off (locked) and no off button', async ($, on) => {
  const { ui } = await pane($, on, PLUGS)
  await ui.press({ key: 'mode:plugins' })
  expect(await ui.find({ key: 'off:gh' })).toBeUndefined()
  const shown = await texts(ui)
  expect(shown).toContain(' off (locked)')
  expect(shown).toContain('  Pinned by other skills. Use the CLI with --force. ')
  // The row's [?] lists who pins it (R-8 -> R-7).
  await ui.press({ key: 'pin:gh' })
  expect(await texts(ui)).toContain('    Referenced by: x')
  await ui.press({ key: 'pin:gh' })
  expect(await texts(ui)).not.toContain('    Referenced by: x')
  await ui.unmount()
})

test('R-8 (flat skills) sets every flat skill, skipping pinned ones for user-only', async ($, on) => {
  const { runs, ui } = await pane($, on, PLUGS)
  await ui.press({ key: 'mode:plugins' })
  const row = (await ui.findAll({ type: 'Box' })).find((b: any) => b.key === 'prow:(flat skills)')
  expect(row.children.filter((c: any) => c?.type === 'Button').map((c: any) => c.props.key)).toEqual([
    'group:(flat skills)', 'flat:on', 'flat:name-only', 'flat:user-only', 'flat:off',
  ])
  expect(await style(ui, 'flat:on')).toEqual(SEL)
  await ui.press({ key: 'flat:user-only' })
  expect(runs.filter(r => r.argv[3] === 'set').map(r => r.argv.slice(4))).toEqual([['commit', 'user-only'], ['tidy', 'user-only']])
  expect(JSON.stringify(runs.toasts.at(-1))).toContain('2 set, 1 skipped (pinned)')
  for (const st of ['on', 'name-only', 'user-only', 'off']) expect(await style(ui, `flat:${st}`)).toEqual(OFF)
  await ui.unmount()
})
