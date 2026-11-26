import { expect, mock, test } from 'claude-code/testing'

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
function world(on: any, placed: boolean, list: typeof MANY = LIST) {
  const runs: { argv: readonly string[]; stdin?: string }[] = []
  const skills = list.skills.map(s => ({ ...s }))
  on('command.register', () => ({ value: { command: 'skills-map' } }))
  on('ui.open', () => ({ value: placed ? { isPlaced: true } : { isPlaced: false, reason: 'no-surface' } }))
  on('ui.close', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('session.start', (_$: any, e: any) => ({ cwd: e.cwd }))
  on('skill.prompt', (_$: any, e: any) => ({ text: e.text }))
  on('process.run', (_$: any, e: any) => {
    runs.push({ argv: e.argv, stdin: e.init?.stdin })
    const verb = e.argv[3]
    // set flips the fake engine's state, so the next list reflects the toggle.
    if (verb === 'set') skills.find(s => s.name === e.argv[4])!.state = e.argv[5]
    const stdout = verb === 'list' ? JSON.stringify({ ...list, skills }) : verb === 'recommend' ? '# per-turn listing ~60 -> ~40 tokens' : 'commit: off (takes effect in a new session)'
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
  expect(await ui.find({ type: 'Text', text: /tokens ~60 now/ })).toBeDefined()
  expect(await ui.find({ key: 'gh:pr:off' })).toBeUndefined()
  expect((await ui.find({ key: 'commit:on' }))?.text).toContain('>on<')
  await ui.press({ key: 'commit:off' })
  expect(runs.some(x => x.argv.slice(3).join(' ') === 'set commit off')).toBe(true)
  await ui.unmount()
})

async function pane($: any, on: any) {
  const runs = world(on, true, MANY)
  mock.store(on)
  await run($)
  return { runs, ui: await $.ui.mount({ ...PANE, surface: 'terminal' }) }
}
const order = async (ui: any) => (await ui.findAll({ type: 'Box' })).map((b: any) => b.key).filter((k: any) => k?.startsWith('row:'))

test('the current state gets a colored badge and the primary marked button', async ($, on) => {
  const { ui } = await pane($, on)
  const cur = await ui.find({ key: 'commit:on' })
  expect(cur?.text).toContain('>on<')
  expect(cur?.props.variant).toBe('primary')
  const other = await ui.find({ key: 'commit:off' })
  expect(other?.text).not.toContain('>')
  expect(other?.props.variant).toBeUndefined()
  expect(other?.props.dimColor).toBe(true)
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
  expect((await ui.find({ key: 'mode:skills' }))?.props.variant).toBe('primary')
  await ui.press({ key: 'mode:plugins' })
  const rows = (await ui.findAll({ type: 'Button' })).filter((b: any) => b.key?.startsWith('group:'))
  expect(rows.map((b: any) => b.key)).toEqual(['group:(flat skills)', 'group:gh'])
  expect(rows[1].text).toContain('2 skills 5u ~45t 1 pinned')
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

test('a toggle keeps the row order and the search text', async ($, on) => {
  const { runs, ui } = await pane($, on)
  const before = await order(ui)
  await ui.press({ key: 'commit:off' })
  expect(runs.some(x => x.argv.slice(3).join(' ') === 'set commit off')).toBe(true)
  expect(await ui.find({ key: 'commit:off' })).toMatchObject({ props: { variant: 'primary' } })
  expect(await order(ui)).toEqual(before)
  await ui.input({ key: 'q', text: 'review', kind: 'change' })
  await ui.press({ key: 'review:on' })
  expect(await order(ui)).toEqual(['row:review'])
  expect((await ui.find({ key: 'q' }))?.props.value).toBe('review')
  await ui.unmount()
})
