import type { Register } from 'claude-code'

// Bridge for claude/statusline-command.sh (#2026): on every main-thread
// response that read or wrote the prompt cache, write
// $HOME/.cache/claude-cache-watch/<session_id> = "<lastTouchEpochSec> <ttlSec>".
// ponytail: no pruning of old session files (NF-3) — this build's $.fs has no
// delete; files are ~16 bytes each. Add once $.fs grows a delete.
export const register: Register = on => {
  let ttlSec = 300

  on('session.start', async ($, e, next) => {
    ttlSec = (await $.env.get('ENABLE_PROMPT_CACHING_1H')) === '1' ? 3600 : 300
    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    const r = yield* next(e)
    const u = r.usage
    if (e.agentId === undefined && u && u.cache_read_input_tokens + u.cache_creation_input_tokens > 0) {
      try {
        const home = await $.env.get('HOME')
        const sec = Math.floor((await $.clock.now()) / 1000)
        await $.fs.write(`${home}/.cache/claude-cache-watch/${await $.session.id()}`, `${sec} ${ttlSec}\n`)
      } catch {
        // never block the turn on a cache-file write
      }
    }
    return r
  })
}
