import { expect, mock, test } from 'claude-code/testing'

const LIST = {
  skills: [
    { name: 'commit', state: 'on', source: 'user', uses: 3, last_used: null, tokens: 40, pinned_by: [], description: 'd' },
    { name: 'gh:pr', state: 'on', source: 'plugin', uses: 0, last_used: null, tokens: 20, pinned_by: [], description: 'd' },
  ],
  tokens: { current: 60, recommended: 40 },
}
const PANE = {
  plugin: 'skills-map',
  component: 'Pane',
  requestId: 'skills-map',
  props: { title: 'Skills map', isFocused: false, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const

// Wires the engine beneath the plugin: command registry, panes, and a fake
// bin/skills_map.py answering by verb. Every argv and stdin is recorded.
function world(on: any, placed: boolean) {
  const runs: { argv: readonly string[]; stdin?: string }[] = []
  on('command.register', () => ({ value: { command: 'skills-map' } }))
  on('ui.open', () => ({ value: placed ? { isPlaced: true } : { isPlaced: false, reason: 'no-surface' } }))
  on('ui.close', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('session.start', (_$: any, e: any) => ({ cwd: e.cwd }))
  on('skill.prompt', (_$: any, e: any) => ({ text: e.text }))
  on('process.run', (_$: any, e: any) => {
    runs.push({ argv: e.argv, stdin: e.init?.stdin })
    const verb = e.argv[3]
    const stdout = verb === 'list' ? JSON.stringify(LIST) : verb === 'recommend' ? '# per-turn listing ~60 -> ~40 tokens' : 'commit: off (takes effect in a new session)'
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
  await ui.press({ key: 'commit:off' })
  expect(runs.some(x => x.argv.slice(3).join(' ') === 'set commit off')).toBe(true)
  await ui.unmount()
})
