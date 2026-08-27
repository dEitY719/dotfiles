#!/usr/bin/env python3
"""Claude Code PreToolUse hook: block self-terminating-never wait loops (issue #1521).

A subagent hand-wrote this to wait on a sibling subagent and it spun for
49 minutes without ever exiting::

    until [ -s .../tasks/a7ab696cc6e841cc7.output ] \\
          && ! pgrep -f a7ab696cc6e841cc7 >/dev/null 2>&1
    do sleep 5; done

`pgrep -f` matches the FULL command line of every process, including the
very shell that is running the loop -- and that shell's command line
contains `a7ab696cc6e841cc7` literally (twice: once in the `.output`
path, once as the pgrep pattern). So `pgrep` always finds itself, `!
pgrep` is permanently false, and the exit condition can never become
true. The `[ -s ... ]` half had been true since minute one.

Prompt rules only lower the frequency of this; the harness has to refuse
the command mechanically. This hook does exactly that, for two narrow
shapes and nothing else.

Blocked shape 1 -- self-matching `pgrep -f`
    A `pgrep` invocation whose flags include `f` (`-f`, `-af`, `--full`)
    where the *literal* search pattern also occurs somewhere else in the
    same command string. That second occurrence is the proof: the token
    is baked into the invoking shell's command line, so the match is
    guaranteed and self-referential.

    The remedy the reason recommends is the character class
    (`[a]7ab696...`), NOT plain `| grep -vx "$$"`. Measured under the
    Claude Code Bash tool, `pgrep -f` returns TWO self-matches: the inner
    shell (`$$`) *and* the outer `zsh -c <snapshot> && eval '<command>'`
    wrapper, whose own command line embeds the command verbatim. #1521
    saw the same pair (pids 179954 + 1226029). So excluding `$$` removes
    only one of the two and the loop still never exits. The character
    class removes both, because nothing on either command line matches
    the *pattern* any more.

Blocked shape 2 -- polling a subagent's `tasks/*.output`
    An `until`/`while` loop with a `sleep` in it that watches a
    `tasks/<id>.output` path. Subagent completion is already pushed to
    the parent by the harness, so this loop is redundant even when it
    *does* terminate. Remedy in the reason: don't wait, end the turn.

Deliberately NOT blocked (false-positive guard -- read before widening)
    The Monitor tool's own documentation *recommends* the generic
    poll-with-sleep shape for one-shot waits::

        until grep -q "Ready in" dev.log; do sleep 0.5; done

    The loop form is harness-sanctioned; only the predicate was wrong in
    #1521. So shape 2 requires a `tasks/*.output` target, never bare
    `until ... sleep ...`, and there is a regression test pinning that
    exact `dev.log` command as ALLOWED. Widening rule 2 to "no polling
    loops" would put this hook in direct conflict with harness guidance.

    Likewise rule 1 stays provably-safe-only. It never fires when:
      - the pattern is not a literal (`pgrep -f "$PAT"`) -- its runtime
        value is unknowable statically, so self-match cannot be proven;
      - the command mentions `$$` anywhere -- the author is demonstrably
        PID-aware, so this is treated as an opt-out rather than an
        accident. (Note it is a weak fix, per the two-match measurement
        above; the hook allows it but the reason text steers people to
        the character class instead.);
      - the pattern carries a `[...]` character class -- the classic
        regex trick that makes the literal fail to match itself;
      - the pattern occurs exactly once, i.e. only as pgrep's own
        argument. That is the overwhelmingly common, safe case.

Safety rails (fail open, always -- never trap the user):
    - empty / unreadable / malformed stdin -> exit 0, no output
    - `tool_name != "Bash"` or no `tool_input.command` -> exit 0
    - `BASH_WAIT_LOOP_GUARD_BYPASS=1` -> exit 0 (manual escape hatch)
    - any unexpected exception -> exit 0

The hook only ever does two things: emit nothing (allow, normal
permission flow applies), or emit one PreToolUse deny object on stdout
and exit 0.

Output schema is the current documented PreToolUse form
(https://code.claude.com/docs/en/hooks) -- exit 0 plus::

    {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                            "permissionDecision": "deny",
                            "permissionDecisionReason": "..."}}

not the legacy `{"decision":"block","reason":...}` used by this repo's
Stop hooks. Stop and PreToolUse have different contracts; sending the
Stop shape here would make the hook silently never block anything.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import sys

# Manual escape hatch.
_BYPASS_ENABLED: bool = os.environ.get("BASH_WAIT_LOOP_GUARD_BYPASS") == "1"

# Opt-in stderr trace, mirroring the other hooks in this directory.
_TRACE_ENABLED: bool = os.environ.get("BASH_WAIT_LOOP_GUARD_TRACE") == "1"

# Split a command into pipeline-level segments. `|` is intentionally NOT a
# separator: `pgrep -f "$PAT" | grep -vx "$$"` must stay one segment so the
# self-exclusion is visible next to the pgrep it protects.
_SEGMENT_SPLIT_RE: re.Pattern[str] = re.compile(r"\|\||&&|;|\n")

# `pgrep`, optionally path-qualified, as a whole word.
_PGREP_TOKEN_RE: re.Pattern[str] = re.compile(r"(?:^|/)pgrep$")

# Short pgrep options that consume the following argument as their value.
_PGREP_VALUE_OPTS: frozenset[str] = frozenset("dgGPstuUFjMN")

# Long pgrep options that consume the following argument as their value.
_PGREP_LONG_VALUE_OPTS: frozenset[str] = frozenset(
    {
        "--delimiter",
        "--pgroup",
        "--group",
        "--parent",
        "--session",
        "--terminal",
        "--euid",
        "--uid",
        "--pidfile",
        "--ns",
        "--nslist",
    }
)

# A `tasks/<something>.output` path -- the subagent completion file of #1521.
_TASKS_OUTPUT_RE: re.Pattern[str] = re.compile(r"tasks/[^\s'\"`;|&)]*\.output")

_LOOP_KEYWORD_RE: re.Pattern[str] = re.compile(r"(?:^|[\s;&|({])(?:until|while)\s")
_SLEEP_RE: re.Pattern[str] = re.compile(r"(?:^|[\s;&|({])sleep(?:\s|$)")

_PGREP_REASON = (
    "차단: 자기매칭이 확정된 `pgrep -f` 입니다 (issue #1521).\n"
    "`pgrep -f` 는 전체 커맨드라인을 매치하므로, 검색 패턴 {pattern!r} 이 이 명령 문자열 "
    "안에 다시 등장하는 순간 pgrep 은 자기 자신(이 명령을 실행하는 셸)을 매치합니다. "
    "따라서 `pgrep` 은 항상 성공하고 `! pgrep` 은 항상 거짓 — 이걸 종료 조건으로 쓰는 "
    "루프는 영원히 끝나지 않습니다 (실측 49분).\n"
    "권장 회피: 첫 글자를 문자클래스로 감싸세요 — pgrep -f '[{first}]{rest}'\n"
    '(`| grep -vx "$$"` 만으로는 부족합니다: Claude Code 의 Bash 도구는 명령을 '
    "`zsh -c ... eval '<command>'` 래퍼로 감싸 실행하므로 자기매칭이 안쪽 셸과 바깥 "
    "래퍼 2개로 잡힙니다. `$$` 배제는 그중 하나만 지웁니다 — #1521 의 pid 179954 + "
    "1226029 가 정확히 이 쌍입니다.)\n"
    "그리고 서브에이전트를 기다리는 중이라면 애초에 폴링이 불필요합니다 — "
    "하네스가 완료 시 자동으로 알려줍니다."
)

_TASKS_POLL_REASON = (
    "차단: 서브에이전트 출력 파일을 도는 무한 폴링 루프입니다 (issue #1521).\n"
    "감시 대상: {path}\n"
    "서브에이전트는 완료 시 하네스가 부모에게 자동으로 알림을 보냅니다. 기다리는 "
    "루프는 그 메커니즘과 중복이고, #1521 처럼 종료 조건이 틀리면 49분씩 낭비됩니다. "
    "기다리지 말고 그냥 턴을 넘기세요 — 완료되면 알림이 옵니다.\n"
    '(참고: `until grep -q "Ready in" dev.log; do sleep 0.5; done` 같은 일반 폴링은 '
    "하네스 권장 형태이며 차단하지 않습니다. 막는 것은 tasks/*.output 폴링뿐입니다.)"
)


def _trace(message: str) -> None:
    """Emit a `[wait-loop-guard]` trace line on stderr when trace mode is on."""
    if _TRACE_ENABLED:
        print(f"[wait-loop-guard] {message}", file=sys.stderr)


def _tokenize(segment: str) -> list[str]:
    """Best-effort shell tokenization; falls back to whitespace split."""
    try:
        return shlex.split(segment, posix=True)
    except ValueError:
        _trace("shlex failed; falling back to whitespace split")
        return [t.strip("\"'") for t in segment.split()]


_REDIRECT_RE: re.Pattern[str] = re.compile(r"\d*(?:>>|>|<<|<)")


def _is_redirect(token: str) -> bool:
    """True for redirect-ish tokens (`>/dev/null`, `2>&1`, `<`, `>>out`)."""
    return bool(_REDIRECT_RE.match(token))


def _pgrep_pattern(tokens: list[str], start: int) -> str | None:
    """Extract the search pattern of the `pgrep` starting at `tokens[start]`.

    Returns None when this pgrep does not do full-command-line matching
    (no `f` in its flags) or when no operand can be identified.
    """
    full_match = False
    operands: list[str] = []
    i = start + 1
    while i < len(tokens):
        tok = tokens[i]
        if _is_redirect(tok):
            # Skip a bare redirect operator plus its target.
            if _REDIRECT_RE.fullmatch(tok):
                i += 2
            else:
                i += 1
            continue
        if tok == "--":
            operands.extend(t for t in tokens[i + 1 :] if not _is_redirect(t))
            break
        if tok.startswith("--"):
            name, sep, _value = tok.partition("=")
            if name == "--full":
                full_match = True
            if not sep and name in _PGREP_LONG_VALUE_OPTS:
                i += 2
                continue
            i += 1
            continue
        if tok.startswith("-") and len(tok) > 1:
            flags = tok[1:]
            if "f" in flags:
                full_match = True
            if flags and flags[-1] in _PGREP_VALUE_OPTS:
                i += 2
                continue
            i += 1
            continue
        operands.append(tok)
        i += 1

    if not full_match:
        _trace("pgrep without -f/--full; ignoring")
        return None
    if not operands:
        return None
    return operands[0]


def _check_pgrep_self_match(command: str) -> str | None:
    """Return a deny reason when `command` contains a provably self-matching pgrep."""
    if "pgrep" not in command:
        return None

    # The author is PID-aware somewhere in this command (`| grep -vx "$$"`,
    # `MYPID=$$`, ...). That is the documented remedy -- never block it.
    if "$$" in command:
        _trace("command references $$; assuming deliberate self-exclusion")
        return None

    for segment in _SEGMENT_SPLIT_RE.split(command):
        if "pgrep" not in segment:
            continue
        tokens = _tokenize(segment)
        for idx, tok in enumerate(tokens):
            if not _PGREP_TOKEN_RE.search(tok):
                continue
            pattern = _pgrep_pattern(tokens, idx)
            if not pattern:
                continue
            # Not a literal -- runtime value unknowable, self-match unprovable.
            if "$" in pattern or "`" in pattern:
                _trace(f"pgrep pattern {pattern!r} is not a literal; allowing")
                continue
            # Character class breaks the literal self-match on purpose.
            if "[" in pattern:
                _trace(f"pgrep pattern {pattern!r} uses a character class; allowing")
                continue
            # The pattern occurs once as pgrep's own argument. A second
            # occurrence means it is also baked into this shell's command
            # line -> the match is guaranteed and self-referential.
            if command.count(pattern) < 2:
                _trace(f"pgrep pattern {pattern!r} occurs once; allowing")
                continue
            _trace(f"pgrep pattern {pattern!r} recurs in the command; denying")
            return _PGREP_REASON.format(
                pattern=pattern,
                first=pattern[0],
                rest=pattern[1:],
            )
    return None


def _check_tasks_output_poll(command: str) -> str | None:
    """Return a deny reason for an infinite `tasks/*.output` polling loop."""
    hit = _TASKS_OUTPUT_RE.search(command)
    if not hit:
        return None
    if not _LOOP_KEYWORD_RE.search(command):
        return None
    if not _SLEEP_RE.search(command):
        return None
    _trace(f"tasks output poll loop on {hit.group(0)!r}; denying")
    return _TASKS_POLL_REASON.format(path=hit.group(0))


def _deny(reason: str) -> None:
    """Emit the current PreToolUse deny object on stdout and exit 0."""
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
        ensure_ascii=False,
    )
    sys.stdout.write("\n")


def main() -> int:
    if _BYPASS_ENABLED:
        _trace("bypass enabled; allowing")
        return 0

    try:
        raw = sys.stdin.read()
    except Exception:  # pragma: no cover -- defensive
        return 0
    if not raw.strip():
        return 0

    try:
        event = json.loads(raw)
    except (ValueError, TypeError):
        _trace("stdin is not valid JSON; allowing")
        return 0
    if not isinstance(event, dict):
        return 0

    if event.get("tool_name") != "Bash":
        return 0

    tool_input = event.get("tool_input")
    if not isinstance(tool_input, dict):
        return 0
    command = tool_input.get("command")
    if not isinstance(command, str) or not command.strip():
        return 0

    reason = _check_pgrep_self_match(command) or _check_tasks_output_poll(command)
    if reason:
        _deny(reason)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # pragma: no cover -- fail open, always
        _trace(f"unexpected error, failing open: {exc!r}")
        sys.exit(0)
