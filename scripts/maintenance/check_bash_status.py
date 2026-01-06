#!/usr/bin/env python3
#
# check_bash_status.py
# Inspect .bash files one by one in clean shells with tracing.
#
# Usage:
#   ./check_bash_status.py [ROOT_DIR(default: ./bash)] [--mode isolated|chain] [--timeout 30]
#
# Options:
#   ROOT_DIR        Directory to search for .bash files (default: ./bash)
#   --mode MODE     Run mode: isolated (default) or chain
#   --logdir DIR    Directory to store logs (default: ./bash_check_logs)
#   --timeout SEC   Per-file timeout in seconds for isolated mode (default: 30)
#   --help          Show this help message
#
# Examples:
#   ./check_bash_status.py
#   ./check_bash_status.py ./bash --mode isolated
#   ./check_bash_status.py ./bash --mode chain --logdir ./logs
#   ./check_bash_status.py ./bash --timeout 20
#
# Requires:
#   pip install rich

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from rich.console import Console
from rich.progress import BarColumn, Progress, TextColumn, TimeElapsedColumn

console = Console()

# 공통 헤더 스니펫:
# - fd3를 먼저 열고(exec 3> "__LOG__") -> BASH_XTRACEFD=3 -> set -x -> trap
SNIPPET_HEADER = r"""set -Eeuo pipefail
PS4='+ ${BASH_SOURCE##*/}:${LINENO}:${FUNCNAME[0]:-main}() '
exec 3> "__LOG__"
export BASH_XTRACEFD=3
set -x
trap 'code=$?; echo "ERR($code) at ${BASH_SOURCE[0]}:${LINENO} -> ${BASH_COMMAND}" >&2' ERR
"""

# 개별 파일 검사(구문 검사 + source + 성공 메시지 fd3 기록)
SNIPPET_ISOLATED_BODY = r"""bash -n "__FILE__"
source "__FILE__"
echo '>>> LOAD OK: __FILE__'
echo '체크한 결과, 정상입니다. (__FILE__)' >&3
"""


def find_bash_files(root: Path) -> list[Path]:
    return sorted([p for p in root.rglob("*.bash") if p.is_file()])


def write_script(content: str) -> Path:
    tf = tempfile.NamedTemporaryFile("w", delete=False, prefix="bash_check_", suffix=".sh")
    tf.write(content)
    tf.flush()
    tf.close()
    os.chmod(tf.name, 0o755)
    return Path(tf.name)


def run_bash_script(script_path: Path, timeout: int) -> subprocess.CompletedProcess[str]:
    # 비대화 프롬프트/대기 방지 환경
    env = os.environ.copy()
    env.update(
        {
            "CHECK_NONINTERACTIVE": "1",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_ASKPASS": "/bin/false",
            "SSH_ASKPASS": "/bin/false",
            "SUDO_ASKPASS": "/bin/false",
            "DEBIAN_FRONTEND": "noninteractive",
        }
    )
    return subprocess.run(
        ["bash", "--noprofile", "--norc", str(script_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        stdin=subprocess.DEVNULL,  # 입력 차단
        env=env,
        timeout=timeout,
    )


def tail_lines(path: Path, n: int = 30) -> list[str]:
    try:
        return path.read_text(errors="replace").splitlines()[-n:]
    except Exception:
        return []


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Check .bash files in clean shells with tracing.", formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "root", nargs="?", default="./bash", help="Root directory containing .bash files (default: ./bash)"
    )
    parser.add_argument(
        "--mode", choices=["isolated", "chain"], default="isolated", help="Run mode: isolated (default) or chain"
    )
    parser.add_argument(
        "--logdir", default="./bash_check_logs", help="Directory to store logs (default: ./bash_check_logs)"
    )
    parser.add_argument(
        "--timeout", type=int, default=30, help="Per-file timeout seconds in isolated mode (default: 30)"
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    logdir = Path(args.logdir).resolve()
    logdir.mkdir(parents=True, exist_ok=True)

    files = find_bash_files(root)
    if not files:
        console.print(f"[yellow]No .bash files under {root}[/yellow]")
        sys.exit(0)

    console.print(f"[bold]Checking .bash files under:[/bold] {root}")
    console.print(f"Mode: [bold]{args.mode}[/bold]")
    console.print(f"Log dir: [bold]{logdir}[/bold]")
    if args.mode == "isolated":
        console.print(f"Timeout (per file): [bold]{args.timeout}s[/bold]\n")
    else:
        console.print("")

    if args.mode == "isolated":
        with Progress(
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            TextColumn("{task.completed}/{task.total}"),
            TimeElapsedColumn(),
            console=console,
        ) as progress:
            task = progress.add_task("Isolated check", total=len(files))
            for f in files:
                rel = f.resolve().relative_to(root)
                log = logdir / f"isolated_{str(rel).replace('/', '_')}.log"
                snippet = SNIPPET_HEADER.replace("__LOG__", str(log)) + SNIPPET_ISOLATED_BODY.replace(
                    "__FILE__", str(f)
                )
                tmp_script = write_script(snippet)
                try:
                    proc = run_bash_script(tmp_script, timeout=args.timeout)
                except subprocess.TimeoutExpired:
                    console.print(f"[yellow][HANG][/yellow] {rel}  (>{args.timeout}s)  trace: {log}")
                    for line in tail_lines(log, 30):
                        console.print(f"    {line}")
                    try:
                        tmp_script.unlink(missing_ok=True)
                    except TypeError:
                        try:
                            tmp_script.unlink()
                        except Exception:
                            pass
                    sys.exit(1)

                if proc.returncode != 0:
                    console.print(f"[red][FAIL][/red] {rel}  trace: {log}")
                    for line in tail_lines(log, 30):
                        console.print(f"    {line}")
                    try:
                        tmp_script.unlink(missing_ok=True)
                    except TypeError:
                        try:
                            tmp_script.unlink()
                        except Exception:
                            pass
                    sys.exit(1)

                progress.update(task, description=f"[cyan]{rel}[/cyan]")
                progress.advance(task)
                console.print(f"[green][OK][/green] {rel}  (trace: {log})")

                try:
                    tmp_script.unlink(missing_ok=True)
                except TypeError:
                    try:
                        tmp_script.unlink()
                    except Exception:
                        pass

        console.print("\n[bold][green]All good![/green][/bold]")
        return

    # --- chain mode ---
    # 전체 체인을 하나의 셸에서 실행. chain 전체의 xtrace는 chain.log로 기록.
    chain_log = logdir / "chain.log"
    lines = [SNIPPET_HEADER.replace("__LOG__", str(chain_log))]
    for f in files:
        lines.append(f'echo "--- SOURCE: {f}"')
        lines.append(f'bash -n "{f}"')
        lines.append(f'source "{f}"')
    lines.append(f'echo ">>> LOAD OK: chained {len(files)} files"')
    lines.append(f'echo "체크한 결과, 정상입니다. (chain, {len(files)} files)" >&3')

    chain_script = write_script("\n".join(lines))

    # 체인 모드는 파일 수에 비례한 넉넉한 타임아웃을 권장
    chain_timeout = max(args.timeout * len(files), args.timeout)
    try:
        proc = run_bash_script(chain_script, timeout=chain_timeout)
    except subprocess.TimeoutExpired:
        console.print(f"[yellow][HANG][/yellow] chain mode  (>{chain_timeout}s)  trace: {chain_log}")
        for line in tail_lines(chain_log, 80):
            console.print(f"    {line}")
        try:
            chain_script.unlink(missing_ok=True)
        except TypeError:
            try:
                chain_script.unlink()
            except Exception:
                pass
        sys.exit(1)

    # stdout/stderr도 참고용으로 chain.log에 덧붙임
    try:
        with chain_log.open("a", encoding="utf-8", errors="replace") as lf:
            if proc.stdout:
                lf.write("\n# ---- stdout/stderr ----\n")
                lf.write(proc.stdout)
    except Exception:
        pass

    if proc.returncode != 0:
        console.print(f"[red][FAIL][/red] chain mode  trace: {chain_log}")
        for line in tail_lines(chain_log, 80):
            console.print(f"    {line}")
        try:
            chain_script.unlink(missing_ok=True)
        except TypeError:
            try:
                chain_script.unlink()
            except Exception:
                pass
        sys.exit(1)

    console.print(f"[green][OK][/green] chain mode (trace: {chain_log})")
    console.print("\n[bold][green]All good![/green][/bold]")

    try:
        chain_script.unlink(missing_ok=True)
    except TypeError:
        try:
            chain_script.unlink()
        except Exception:
            pass


if __name__ == "__main__":
    main()
