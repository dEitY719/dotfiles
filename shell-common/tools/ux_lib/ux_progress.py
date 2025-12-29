#!/usr/bin/env python3
"""Progress bar for long-running operations"""

import subprocess
import sys
import time

from rich.console import Console
from rich.progress import BarColumn, Progress, SpinnerColumn, TaskProgressColumn, TextColumn

console = Console()


def run_with_progress(command: str, description: str, total_steps: int = 100):
    """Run a command with a progress bar"""
    with Progress(
        SpinnerColumn(),
        TextColumn("[bold blue]{task.description}"),
        BarColumn(),
        TaskProgressColumn(),
        console=console,
        transient=True,
    ) as progress:
        task = progress.add_task(description, total=total_steps)

        process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        stdout_lines = []
        stderr_lines = []

        # Read stdout/stderr line by line to keep track of progress and capture output
        # This is a simplified progress; a more advanced one would parse progress from command output
        # For now, we just advance the bar periodically
        start_time = time.time()
        while process.poll() is None:
            # Try to read output without blocking forever
            try:
                line = process.stdout.readline()
                if line:
                    stdout_lines.append(line)
            except Exception:
                pass

            try:
                err_line = process.stderr.readline()
                if err_line:
                    stderr_lines.append(err_line)
            except Exception:
                pass

            if (time.time() - start_time) * 10 < total_steps:  # Advance roughly for up to 10 seconds of process
                progress.update(task, advance=1)
            time.sleep(0.1)

        # Ensure all remaining output is read
        for line in process.stdout.readlines():
            stdout_lines.append(line)
        for line in process.stderr.readlines():
            stderr_lines.append(line)

        progress.update(task, completed=total_steps)  # Mark as complete

        # Print captured output if any, especially stderr
        if stdout_lines:
            console.print(f"[dim]Command stdout:[/dim]\n{''.join(stdout_lines).strip()}")
        if stderr_lines:
            console.print(f"[dim red]Command stderr:[/dim red]\n{''.join(stderr_lines).strip()}")

        return process.returncode


if __name__ == "__main__":
    if len(sys.argv) < 3:
        console.print("[red]Usage: ux_progress.py <description> <command> [total_steps][/red]", file=sys.stderr)
        sys.exit(1)

    description = sys.argv[1]
    command = sys.argv[2]
    total_steps = int(sys.argv[3]) if len(sys.argv) > 3 else 100

    try:
        exit_code = run_with_progress(command, description, total_steps)
        sys.exit(exit_code)
    except Exception as e:
        console.print(f"[red]An unexpected error occurred: {e}[/red]", file=sys.stderr)
        sys.exit(1)
