#!/usr/bin/env python3
"""Interactive menu system for bash functions"""

import sys
import json
from typing import List, Optional
from rich.console import Console
from rich.prompt import Prompt
from rich.table import Table

console = Console()

def show_menu(title: str, options: List[str], allow_cancel: bool = True) -> Optional[int]:
    """
    Display an interactive menu and return selected index
    
    Args:
        title: Menu title
        options: List of option strings
        allow_cancel: Whether to show cancel option
        
    Returns:
        Selected index (0-based) or None if cancelled
    """
    console.print(f"\n[bold blue]{title}[/bold blue]\n")

    table = Table(show_header=False, box=None, padding=(0, 2))
    table.add_column("Index", style="cyan", justify="right")
    table.add_column("Option", style="white")

    for i, option in enumerate(options, 1):
        table.add_row(str(i), option)

    if allow_cancel:
        table.add_row("0", "[dim]Cancel[/dim]")

    console.print(table)

    while True:
        try:
            choice = Prompt.ask(
                "\n[yellow]Select an option[/yellow]",
                choices=[str(i) for i in range(len(options) + 1)],
                show_choices=False
            )

            choice_num = int(choice)
            if choice_num == 0 and allow_cancel:
                return None
            elif 1 <= choice_num <= len(options):
                return choice_num - 1
        except (ValueError, KeyboardInterrupt):
            console.print("[red]Invalid selection or cancelled[/red]")
            return None # Return None on invalid input or Ctrl+C
        except EOFError:
            # Handle case where input stream is closed (e.g. piped input issue)
            return None

if __name__ == "__main__":
    stderr_console = Console(stderr=True)
    
    # Check for command line argument
    if len(sys.argv) < 2:
        stderr_console.print("[red]Error: JSON configuration required as first argument[/red]")
        sys.exit(2)
        
    try:
        config_json = sys.argv[1]
        config = json.loads(config_json)

        result = show_menu(
            title=config["title"],
            options=config["options"],
            allow_cancel=config.get("allow_cancel", True)
        )

        if result is not None:
            print(result)
            sys.exit(0)
        else:
            sys.exit(1) # Indicate cancellation or invalid input
    except json.JSONDecodeError:
        stderr_console.print("[red]Error: Invalid JSON input argument[/red]")
        sys.exit(2)
    except Exception as e:
        stderr_console.print(f"[red]An unexpected error occurred: {e}[/red]")
        sys.exit(3)
