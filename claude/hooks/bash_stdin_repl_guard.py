#!/usr/bin/env python3
"""Claude Code PreToolUse hook: deny a bare interpreter call (issue #1815).

An interpreter started with no arguments reads its program from stdin. The
Bash tool leaves stdin open (a pipe, not /dev/null), so EOF never comes and
the call waits forever -- as a REPL on a tty-less pipe. A `/simplify` review
subagent ran this during brokerdesk PR #78::

    (.venv/bin/python 2>/dev/null || true; P=.venv/bin/python; ...)

The first `.venv/bin/python` has no arguments: it sat waiting for 64
minutes, the subagent's completion arrived 65 minutes late, and because it
was a background command the Bash tool's 2-minute timeout never applied.

Prompt rules only lower the frequency of this (same conclusion as #1521,
`bash_wait_loop_guard.py`); the harness refuses the shape mechanically.

Denied shape -- all of:
    - an interpreter word (`python`, `python3`, `python3.X`, any path whose
      basename is one of those, `node`, `ruby`, `irb`, `lua`) in command
      position: command start, or after `;` `&&` `||` `\\n` `(` `{` `$(`
      `then` `do` `else` ...;
    - followed by nothing but output redirects (`2>/dev/null`, `>out`,
      `2>&1`) up to the end of its simple command;
    - no stdin redirect (`<`, `<<`, `<<<`, `0<`);
    - not on the right of a pipe (`... | python` reads the pipe).
    A trailing `&` does not help: bash hands an async job /dev/null, but
    zsh -- which the Bash tool may run -- keeps the open stdin (measured:
    `zsh -c 'python3 & wait'` hangs).

`bun`/`deno` are deliberately left out of v1 -- bare, they print help or
start a REPL depending on version. The list stays narrow on purpose: a
false positive is the fastest way to get a guard switched off. A new
false-positive report narrows the rule; it never widens it.

Quoted strings, comments and heredoc bodies never count as commands.

Fail-open (NF-2): unparsable JSON, a non-Bash tool, unbalanced quotes or
any unexpected exception -> exit 0 with no output (allow). Escape hatch
`BASH_STDIN_REPL_GUARD_BYPASS=1`, stderr trace `BASH_STDIN_REPL_GUARD_TRACE=1`.

Output schema is the same current PreToolUse form as
`bash_wait_loop_guard.py`: exit 0 plus
`{"hookSpecificOutput": {"hookEventName": "PreToolUse",
"permissionDecision": "deny", "permissionDecisionReason": "..."}}`.
Deny, not an `updatedInput` rewrite: a rewrite has to come with
`permissionDecision: "allow"`, which would skip the permission prompt for
every Bash command.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import sys

_BYPASS_ENABLED: bool = os.environ.get("BASH_STDIN_REPL_GUARD_BYPASS") == "1"
_TRACE_ENABLED: bool = os.environ.get("BASH_STDIN_REPL_GUARD_TRACE") == "1"

_INTERPRETER_RE: re.Pattern[str] = re.compile(r"(?:^|/)(?:python(?:\d+(?:\.\d+)?)?|node|ruby|irb|lua)$")

# `<<WORD`, `<<-'WORD'`, `<< "WORD"` -- but not the `<<<` here-string.
_HEREDOC_RE: re.Pattern[str] = re.compile(r"(?<!<)<<-?\s*(['\"]?)([A-Za-z_]\w*)\1")

_PUNCT_CHARS = "();<>|&\n"
# Longest first: shlex returns a run of punctuation (`);`, `2>&1)`) as one token.
_OPERATORS = ("<<<", "&>>", "&&", "||", "|&", "<<", ">>", ">&", "<&", "&>", ">|", "<>")

# After one of these operators, the next word is a command.
_COMMAND_STARTERS = frozenset({";", "&&", "||", "|", "|&", "&", "(", "\n"})
# Words that, in command position, keep the next word in command position.
_COMMAND_PREFIXES = frozenset({"{", "!", "then", "do", "else", "elif", "if", "while", "until"})
_ASSIGNMENT_RE: re.Pattern[str] = re.compile(r"^[A-Za-z_]\w*=")
# These end a simple command.
_COMMAND_ENDERS = frozenset({";", "&&", "||", "|", "|&", "&", ")", "\n", "}"})
_STDIN_REDIRECTS = frozenset({"<", "<<", "<<<", "<&", "<>"})
_OUTPUT_REDIRECTS = frozenset({">", ">>", ">&", "&>", "&>>", ">|"})

_REASON = (
    "차단: 인자 없는 인터프리터 호출 `{word}` 입니다 (issue #1815).\n"
    "인자 없이 뜬 인터프리터는 stdin 에서 프로그램을 읽는데, Bash 도구는 stdin 을 열어 둔 채"
    "(`/dev/null` 이 아님) 실행하므로 EOF 가 오지 않아 영원히 대기합니다 — 백그라운드 명령이면 "
    "2분 timeout 도 걸리지 않습니다 (brokerdesk PR #78 실측 64분).\n"
    "고치는 법 (하나를 고르세요):\n"
    "  - 스크립트 본문을 heredoc 으로: {word} - <<'EOF' ... EOF\n"
    "  - 파일 실행: {word} script.py\n"
    "  - 한 줄 실행: {word} -c '...' (node 는 -e)\n"
    "  - 존재/버전 확인이 목적이면: {word} --version, 또는 command -v {word}\n"
    "  - 정말 인자 없이 띄워야 하면 stdin 을 닫으세요: {word} </dev/null"
)


def _trace(message: str) -> None:
    if _TRACE_ENABLED:
        print(f"[stdin-repl-guard] {message}", file=sys.stderr)


def _strip_heredoc_bodies(command: str) -> str:
    """Drop heredoc body lines so their content is never read as commands."""
    kept: list[str] = []
    pending: list[str] = []
    for line in command.split("\n"):
        if pending:
            if line.lstrip("\t") == pending[0]:
                pending.pop(0)
            continue
        kept.append(line)
        pending = [m.group(2) for m in _HEREDOC_RE.finditer(line)]
    return "\n".join(kept)


def _split_punct(token: str) -> list[str]:
    """Split a shlex punctuation run into shell operators."""
    ops: list[str] = []
    while token:
        op = next((o for o in _OPERATORS if token.startswith(o)), token[0])
        ops.append(op)
        token = token[len(op) :]
    return ops


def _tokens(command: str) -> list[str]:
    """Words and operators of `command`, quotes removed, comments dropped.

    Raises ValueError on unbalanced quotes.
    """
    text = _strip_heredoc_bodies(command).replace("\\\n", " ")
    lexer = shlex.shlex(text, posix=True, punctuation_chars=_PUNCT_CHARS)
    lexer.whitespace = " \t\r"  # `\n` is a separator here, not whitespace
    lexer.whitespace_split = True
    # shlex's own comment handling swallows the newline that ends the comment,
    # gluing the next line onto this command. Comments are dropped below instead.
    lexer.commenters = ""

    raw = list(lexer)
    tokens: list[str] = []
    in_comment = False
    for tok in raw:
        is_punct = bool(tok) and all(c in _PUNCT_CHARS for c in tok)
        if in_comment:
            in_comment = tok != "\n"
            if not in_comment:
                tokens.append(tok)
            continue
        if not is_punct and tok.startswith("#"):
            in_comment = True
            continue
        tokens.extend(_split_punct(tok) if is_punct else [tok])
    return tokens


def _find_bare_interpreter(command: str) -> str | None:
    """Return the first interpreter word that would wait on stdin, else None."""
    tokens = _tokens(command)
    at_command = True
    for i, word in enumerate(tokens):
        was_command = at_command
        at_command = word in _COMMAND_STARTERS or (
            was_command and (word in _COMMAND_PREFIXES or bool(_ASSIGNMENT_RE.match(word)))
        )
        if not was_command or not _INTERPRETER_RE.search(word):
            continue
        if i > 0 and tokens[i - 1] in ("|", "|&"):
            continue  # reads the pipe
        j = i + 1
        bare = True
        while j < len(tokens) and tokens[j] not in _COMMAND_ENDERS:
            tok = tokens[j]
            if tok in _STDIN_REDIRECTS:
                bare = False
                break
            if tok in _OUTPUT_REDIRECTS:
                j += 2  # the redirect and its target
                continue
            if tok.isdigit() and j + 1 < len(tokens) and tokens[j + 1] in _OUTPUT_REDIRECTS:
                j += 1  # fd number of `2>...`
                continue
            bare = False  # a real argument
            break
        if bare:
            return word
    return None


def _deny(reason: str) -> None:
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
        return 0
    try:
        event = json.loads(sys.stdin.read())
    except (ValueError, TypeError):
        _trace("stdin is not valid JSON; allowing")
        return 0
    if not isinstance(event, dict) or event.get("tool_name") != "Bash":
        return 0
    tool_input = event.get("tool_input")
    if not isinstance(tool_input, dict):
        return 0
    command = tool_input.get("command")
    if not isinstance(command, str) or not command.strip():
        return 0

    try:
        word = _find_bare_interpreter(command)
    except ValueError as exc:
        _trace(f"cannot tokenize ({exc}); allowing")
        return 0
    if word:
        _deny(_REASON.format(word=word))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # pragma: no cover -- fail open, always
        _trace(f"unexpected error, failing open: {exc!r}")
        sys.exit(0)
