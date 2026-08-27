#!/usr/bin/env python3
"""Claude Code PreToolUse hook: block self-terminating-never wait loops (issue #1521).

A subagent hand-wrote this to wait on a sibling subagent and it spun for
49 minutes without ever exiting::

    until [ -s .../tasks/a7ab696cc6e841cc7.output ] \\
          && ! pgrep -f a7ab696cc6e841cc7 >/dev/null 2>&1
    do sleep 5; done

`pgrep -f` matches the FULL command line of every process, including the
very shell that is running the loop -- and that command line contains
`a7ab696cc6e841cc7` literally, if only as pgrep's own argument. So
`pgrep` always finds itself, `! pgrep` is permanently false, and the
exit condition can never become true. The `[ -s ... ]` half had been
true since minute one.

Prompt rules only lower the frequency of this; the harness has to refuse
the command mechanically. This hook does exactly that, for two narrow
shapes and nothing else.

Blocked shape 1 -- a self-matching `pgrep -f` used as a loop's exit test
    Detection is **loop-context based, not occurrence-count based.** An
    earlier draft of this hook gated on "the literal pattern appears
    twice in the command string"; both halves of that were wrong.

    Wrong as a *sufficient* condition (false positives): the count was a
    raw substring count with no word boundaries, so `pgrep -f ep` denied
    itself -- `ep` occurs once inside the literal word `pgrep` and once
    as the operand.

    Wrong as a *necessary* condition (the dangerous false negative): a
    pattern occurring only once is not safe inside a loop. The Claude
    Code Bash tool runs every command as `zsh -c <snapshot> && eval
    '<command>'`, so the wrapper process's own command line *is* the
    command text -- which trivially contains the pattern, because
    pgrep's own argument is part of it. `until ! pgrep -f gunicorn; do
    sleep 1; done` therefore spins forever even though `gunicorn`
    appears exactly once.

    So the real danger signal is not "how often does the token appear",
    it is "is this `pgrep -f <literal>` the thing deciding whether a
    loop keeps spinning". A one-shot `pgrep -f <literal>` cannot hang --
    nothing re-checks it -- and is always allowed. The hook denies only
    when all of these hold:

      - the pgrep does full-command-line matching (`-f`, `-af`,
        `--full`), and
      - its search pattern is a literal (see the escapes below), and
      - the invocation sits inside an `until`/`while` construct's *test*
        (between the keyword and its `do`), not merely somewhere in the
        same command string, and
      - that loop's body contains a `sleep`, and
      - a successful pgrep keeps the loop spinning rather than ending
        it: `until ! pgrep ...` or `while pgrep ...`. The mirrored forms
        (`until pgrep ...`, `while ! pgrep ...`) exit on the very first
        iteration -- still wrong, but not a hang, so out of mandate.

    The one sanctioned remedy is the character class (`[a]7ab696...`),
    NOT `| grep -vx "$$"`. Measured under the Claude Code Bash tool,
    `pgrep -f` returns TWO self-matches: the inner shell (`$$`) *and*
    the outer `zsh -c <snapshot> && eval '<command>'` wrapper, whose own
    command line embeds the command verbatim. #1521 saw the same pair
    (pids 179954 + 1226029). So excluding `$$` removes only one of the
    two and the loop still never exits. The character class removes
    both, because nothing on either command line matches the *pattern*
    any more.

    Consequently `$$` is **not** an allow signal anywhere in this hook.
    An earlier draft skipped the whole check whenever `$$` appeared
    anywhere in the command, which (a) contradicted the measurement just
    above -- it treated a fix the hook itself documents as insufficient
    as proof of safety -- and (b) was trivially defeated by an unrelated
    `$$`, e.g. `echo $$; until ! pgrep -f token; do sleep 1; done`. With
    detection now gated on loop context, dropping the bypass costs
    nothing: every one-shot `pgrep -f ... | grep -vx "$$"` is already
    allowed for being one-shot.

Blocked shape 2 -- polling a subagent's `tasks/*.output`
    An `until`/`while` loop whose *test* watches a `tasks/<id>.output`
    path and whose body contains a `sleep`. Subagent completion is
    already pushed to the parent by the harness, so this loop is
    redundant even when it *does* terminate. Remedy in the reason: don't
    wait, end the turn.

    The three ingredients must be structurally connected, i.e. the path
    reference has to be inside the same loop construct as the sleep.
    Checking them independently anywhere in the string denied
    `ls tasks/test.output && while ! pg_isready; do sleep 1; done`,
    where the `tasks/*.output` mention is an unrelated one-shot `ls` and
    the loop polls something else entirely.

    Not attempted: proving a loop is *bounded*. A retry loop with a
    counter or a timeout can terminate, and this hook will still deny it
    when it polls `tasks/*.output` with a sleep. Deciding boundedness of
    arbitrary shell statically is not a regex-tractable problem, and
    #1521's stated philosophy is that "완전 근절은 목표가 아니다" --
    close the observed shape, keep the escape hatch
    (`BASH_WAIT_LOOP_GUARD_BYPASS=1`) for the rest.

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
      - the pgrep is not in a loop's exit test -- a one-shot call cannot
        hang, whatever it matches. This is the overwhelmingly common,
        safe case;
      - the pattern is not a literal (`pgrep -f "$PAT"`) -- its runtime
        value is unknowable statically, so self-match cannot be proven;
      - the pattern carries a `[...]` character class -- the classic
        regex trick that makes the literal fail to match itself, and the
        only remedy this hook actually endorses.

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

# `until` / `while` and their `do` / `done` bookends, as whole words. Used to
# carve a command into loop constructs so the checks below can require that
# the dangerous ingredients sit inside the *same* loop, not merely in the same
# command string.
_LOOP_START_RE: re.Pattern[str] = re.compile(r"(?:^|[\s;&|(){}])(until|while)(?=\s)")
_DO_KEYWORD_RE: re.Pattern[str] = re.compile(r"(?:^|[\s;&|(){}])(do)(?=[\s;]|$)")
_DONE_KEYWORD_RE: re.Pattern[str] = re.compile(r"(?:^|[\s;&|(){}])(done)(?=[\s;)&|]|$)")

_SLEEP_RE: re.Pattern[str] = re.compile(r"(?:^|[\s;&|({])sleep(?:\s|$)")

_PGREP_REASON = (
    "차단: 루프의 종료 조건으로 쓰인 자기매칭 `pgrep -f` 입니다 (issue #1521).\n"
    "`pgrep -f` 는 전체 커맨드라인을 매치합니다. 그리고 Claude Code 의 Bash 도구는 명령을 "
    "`zsh -c <snapshot> && eval '<command>'` 래퍼로 감싸 실행하므로, 이 루프를 돌리고 있는 "
    "셸/래퍼의 커맨드라인 자체가 이 명령 문자열이고 그 안에는 검색 패턴 {pattern!r} 이 "
    "(다름 아닌 pgrep 자신의 인자로) 들어 있습니다. 따라서 pgrep 은 매 반복마다 자기 자신을 "
    "찾아내고, 이 루프의 종료 조건은 영원히 성립하지 않습니다 (실측 49분).\n"
    "패턴이 명령 안에 한 번만 나와도 마찬가지입니다 — 래퍼가 명령 전체를 품고 있기 때문입니다.\n"
    "권장 회피: 첫 글자를 문자클래스로 감싸세요 — pgrep -f '[{first}]{rest}'\n"
    '(`| grep -vx "$$"` 는 해법이 아닙니다: 자기매칭은 안쪽 셸과 바깥 래퍼 2개로 잡히는데 '
    "`$$` 배제는 그중 하나만 지웁니다 — #1521 의 pid 179954 + 1226029 가 정확히 이 쌍입니다. "
    "문자클래스는 두 커맨드라인 모두에서 패턴 자체를 매치되지 않게 만드는 유일한 확실한 "
    "회피입니다.)\n"
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


def _loop_constructs(command: str) -> list[tuple[str, str, str]]:
    """Carve `command` into `(keyword, test, body)` triples, one per loop.

    `test` is the text between the `until`/`while` keyword and its `do`;
    `body` is the text between that `do` and the matching `done` (or the
    end of the command when the loop is unterminated). A loop with no
    `do` at all is not a loop construct and is skipped.
    """
    loops: list[tuple[str, str, str]] = []
    for match in _LOOP_START_RE.finditer(command):
        keyword = match.group(1)
        test_start = match.end(1)
        do_match = _DO_KEYWORD_RE.search(command, test_start)
        if not do_match:
            continue
        body_start = do_match.end(1)
        done_match = _DONE_KEYWORD_RE.search(command, body_start)
        body_end = done_match.start(1) if done_match else len(command)
        loops.append((keyword, command[test_start : do_match.start(1)], command[body_start:body_end]))
    return loops


def _spinning_pgrep_pattern(keyword: str, test: str) -> str | None:
    """Return the literal pattern of a `pgrep -f` that keeps this loop spinning.

    `test` is a loop's exit condition. A `pgrep -f <literal>` in there
    always matches the very wrapper running the loop, so its result is a
    constant. Which constant keeps the loop alive depends on the keyword
    and on negation: `until ! pgrep ...` never becomes true, and
    `while pgrep ...` never becomes false. The mirror images exit on the
    first iteration -- wrong, but not a hang, so not this hook's business.
    """
    for segment in _SEGMENT_SPLIT_RE.split(test):
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
            negated = idx > 0 and tokens[idx - 1] == "!"
            spins = negated if keyword == "until" else not negated
            if not spins:
                _trace(f"`{keyword}` + negated={negated} exits on match; allowing")
                continue
            return pattern
    return None


def _check_pgrep_self_match(command: str) -> str | None:
    """Return a deny reason when a self-matching `pgrep -f` gates a sleep loop."""
    if "pgrep" not in command:
        return None

    for keyword, test, body in _loop_constructs(command):
        if "pgrep" not in test:
            continue
        if not _SLEEP_RE.search(body):
            _trace("loop body has no sleep; allowing")
            continue
        pattern = _spinning_pgrep_pattern(keyword, test)
        if not pattern:
            continue
        _trace(f"pgrep pattern {pattern!r} gates a `{keyword}` sleep loop; denying")
        return _PGREP_REASON.format(
            pattern=pattern,
            first=pattern[0],
            rest=pattern[1:],
        )
    return None


def _check_tasks_output_poll(command: str) -> str | None:
    """Return a deny reason for an infinite `tasks/*.output` polling loop.

    The path reference must sit in the loop's own exit condition and the
    `sleep` in that same loop's body. Merely finding both somewhere in
    the command string denied unrelated pairs such as
    `ls tasks/test.output && while ! pg_isready; do sleep 1; done`.
    """
    if ".output" not in command:
        return None
    for _keyword, test, body in _loop_constructs(command):
        hit = _TASKS_OUTPUT_RE.search(test)
        if not hit:
            continue
        if not _SLEEP_RE.search(body):
            continue
        _trace(f"tasks output poll loop on {hit.group(0)!r}; denying")
        return _TASKS_POLL_REASON.format(path=hit.group(0))
    return None


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
