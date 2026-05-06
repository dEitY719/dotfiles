#!/usr/bin/env python3
"""Read-only adapter for `jira get-ticket-detail` from the jiravis CLI."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from typing import Any

TICKET_ID_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9]*-\d+$")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Read a Jira ticket through the jiravis CLI.")
    parser.add_argument("--ticket-id", required=True, help="Jira ticket key, for example JIRAVIS-123")
    parser.add_argument("--raw", action="store_true", help="Print raw jiravis JSON output")
    parser.add_argument("--text", action="store_true", help="Print jiravis text output instead of normalized JSON")
    parser.add_argument("--verbose", action="store_true", help="Pass --verbose when using text output")
    return parser.parse_args(argv)


def normalize_ticket_id(ticket_id: str) -> str:
    normalized = ticket_id.strip().upper()
    if not TICKET_ID_PATTERN.fullmatch(normalized):
        raise ValueError(f"invalid Jira ticket id: {ticket_id!r}; expected PROJECT-123")
    return normalized


def build_jira_command(ticket_id: str, *, text_output: bool = False, verbose: bool = False) -> list[str]:
    command = [
        "jira",
        "get-ticket-detail",
        "--ticket-id",
        ticket_id,
        "--output",
        "text" if text_output else "json",
        "--no-confirm",
    ]
    if text_output and verbose:
        command.append("--verbose")
    return command


def parse_jira_json(stdout: str) -> dict[str, Any]:
    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError as exc:
        raise ValueError(f"jiravis returned non-JSON output: {exc}") from exc
    if not isinstance(payload, dict):
        raise ValueError("jiravis returned JSON, but the top-level value is not an object")
    return payload


def _person_name(value: Any) -> str | None:
    if isinstance(value, dict):
        return value.get("display_name") or value.get("account_id")
    if isinstance(value, str):
        return value
    return None


def normalize_detail(payload: dict[str, Any]) -> dict[str, Any]:
    data = payload.get("data") if payload.get("status") == "success" else payload
    if not isinstance(data, dict):
        data = {}

    subtasks = data.get("subtasks") if isinstance(data.get("subtasks"), list) else []
    normalized_subtasks = []
    for subtask in subtasks:
        if isinstance(subtask, dict):
            normalized_subtasks.append(
                {
                    "ticket_id": subtask.get("ticket_id"),
                    "ticket_url": subtask.get("ticket_url"),
                    "summary": subtask.get("summary"),
                    "status": subtask.get("status"),
                    "priority": subtask.get("priority"),
                    "assignee": subtask.get("assignee"),
                }
            )

    return {
        "status": "success",
        "data": {
            "ticket_id": data.get("ticket_id"),
            "ticket_url": data.get("ticket_url"),
            "summary": data.get("summary"),
            "description": data.get("description"),
            "issue_type": data.get("issue_type"),
            "status": data.get("status"),
            "priority": data.get("priority"),
            "assignee": _person_name(data.get("assignee")) or "Unassigned",
            "reporter": _person_name(data.get("reporter")) or "Unknown",
            "due_date": data.get("due_date"),
            "labels": data.get("labels") if isinstance(data.get("labels"), list) else [],
            "components": data.get("components") if isinstance(data.get("components"), list) else [],
            "created_at": data.get("created_at"),
            "updated_at": data.get("updated_at"),
            "subtasks": normalized_subtasks,
        },
    }


def run(args: argparse.Namespace) -> int:
    ticket_id = normalize_ticket_id(args.ticket_id)
    command = build_jira_command(ticket_id, text_output=args.text, verbose=args.verbose)

    if not shutil.which("jira"):
        raise RuntimeError("jiravis CLI not found: `jira` is not on PATH")

    completed = subprocess.run(command, capture_output=True, check=False, text=True)
    if args.raw or args.text:
        print(completed.stdout, end="")
        if completed.stderr:
            print(completed.stderr, end="", file=sys.stderr)
        return completed.returncode

    if completed.returncode != 0:
        error = {
            "status": "error",
            "exit_code": completed.returncode,
            "stderr": completed.stderr.strip(),
            "stdout": completed.stdout.strip(),
        }
        print(json.dumps(error, indent=2, ensure_ascii=False), file=sys.stderr)
        return completed.returncode

    normalized = normalize_detail(parse_jira_json(completed.stdout))
    print(json.dumps(normalized, indent=2, ensure_ascii=False))
    return 0


def main(argv: list[str] | None = None) -> int:
    try:
        return run(parse_args(argv))
    except Exception as exc:
        print(json.dumps({"status": "error", "message": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
