import { test, expect, mock } from 'claude-code/testing'

const FILE = '/home/u/.cache/claude-cache-watch/sid-1'
const STEP = { turnId: 't1', index: 0, model: 'm', messageCount: 1 }

const usage = (read: number, created: number) => ({
  model: 'm', input_tokens: 1, output_tokens: 1,
  cache_read_input_tokens: read, cache_creation_input_tokens: created,
})

// Wires the world beneath the plugin: env, clock, session id, fs.write capture,
// and a bottom turn.step that streams one stop chunk carrying `u`.
function world(on: any, env: Record<string, string>, u: any, failWrite = false) {
  const writes: { path: string; text: string }[] = []
  mock.env(on, { HOME: '/home/u', ...env })
  mock.clock(on, { now: 1_700_000_123_456 })
  on('session.id', () => ({ value: 'sid-1' }))
  on('fs.write', (_$: any, e: any) => {
    if (failWrite) return { deny: 'EACCES' }
    writes.push(e)
    return { value: undefined }
  })
  on('session.start', (_$: any, e: any) => ({ cwd: e.cwd }))
  on('turn.step', async function* () {
    yield { kind: 'stop', stopReason: 'end_turn', usage: u } as any
    return { turnId: 't1', index: 0, answer: 'hi', toolUses: [], stopReason: 'end_turn', usage: u } as any
  })
  return writes
}

async function step($: any, e: any = STEP) {
  const chunks: any[] = []
  const s = $.turn.step(e)
  let n = await s.next()
  for (; !n.done; n = await s.next()) chunks.push(n.value)
  return { chunks, result: n.value }
}

test('cache tokens > 0 in 1h mode writes "<epoch> 3600"', async ($, on) => {
  const writes = world(on, { ENABLE_PROMPT_CACHING_1H: '1' }, usage(10, 0))
  await $.session.start({ cwd: '/', surface: null, isInteractive: true } as any)
  const { chunks } = await step($)
  expect(chunks.length).toBe(1)
  expect(writes).toEqual([{ path: FILE, text: '1700000123 3600\n' }])
})

test('5m mode writes ttl 300', async ($, on) => {
  const writes = world(on, {}, usage(0, 5))
  await $.session.start({ cwd: '/', surface: null, isInteractive: true } as any)
  await step($)
  expect(writes).toEqual([{ path: FILE, text: '1700000123 300\n' }])
})

test('zero cache tokens leave the file alone', async ($, on) => {
  const writes = world(on, { ENABLE_PROMPT_CACHING_1H: '1' }, usage(0, 0))
  await step($)
  expect(writes).toEqual([])
})

test('subagent steps are ignored', async ($, on) => {
  const writes = world(on, {}, usage(10, 0))
  await step($, { ...STEP, agentId: 'a1' })
  expect(writes).toEqual([])
})

test('fs.write failure never blocks the turn', async ($, on) => {
  world(on, {}, usage(10, 0), true)
  const { chunks, result } = await step($)
  expect(chunks.length).toBe(1)
  expect(result.answer).toBe('hi')
})
