#!/usr/bin/env python3
"""Thin adapter for `jira create-ticket` from the jiravis CLI."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

ISSUE_TYPES = ("Task", "Bug", "Story")
PRIORITIES = ("Critical", "High", "Medium", "Low")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a Jira ticket through the jiravis CLI.")
    parser.add_argument("--project-key", required=True, help="Jira project key, for example JIRAVIS")
    parser.add_argument("--summary", required=True, help="Jira issue summary")
    desc_group = parser.add_mutually_exclusive_group(required=True)
    desc_group.add_argument("--description", help="Issue description text")
    desc_group.add_argument("--description-file", type=Path, help="Path to a file containing the description")
    parser.add_argument("--issue-type", default="Task", choices=ISSUE_TYPES, help="Jira issue type")
    parser.add_argument("--priority", default="Medium", choices=PRIORITIES, help="Jira priority")
    parser.add_argument("--assignee", help="Assignee value accepted by jiravis")
    parser.add_argument("--labels", help="Comma-separated labels")
    parser.add_argument("--components", help="Comma-separated components")
    parser.add_argument("--due-date", help="Due date in YYYY-MM-DD format")
    parser.add_argument("--dry-run", action="store_true", help="Print the planned jiravis command without running it")
    parser.add_argument("--raw", action="store_true", help="Print raw jiravis output")
    parser.add_argument("--text", action="store_true", help="Print a concise text summary instead of JSON")
    return parser.parse_args(argv)


def _require_text(value: str, field: str) -> None:
    if not value.strip():
        raise ValueError(f"{field} must not be empty")


def _description_file_for_args(args: argparse.Namespace) -> tuple[str, bool]:
    if args.description_file:
        path = args.description_file
        if not path.is_file():
            raise ValueError(f"description file not found: {path}")
        return str(path), False

    temp = tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".md", delete=False)
    with temp:
        temp.write(args.description or "")
    return temp.name, True


def build_jira_command(args: argparse.Namespace, description_file: str) -> list[str]:
    command = [
        "jira",
        "create-ticket",
        "--project-key",
        args.project_key,
        "--summary",
        args.summary,
        "--description-file",
        description_file,
        "--issue-type",
        args.issue_type,
        "--priority",
        args.priority,
        "--output",
        "json",
        "--no-confirm",
    ]
    optional_pairs = [
        ("--assignee", args.assignee),
        ("--labels", args.labels),
        ("--components", args.components),
        ("--due-date", args.due_date),
    ]
    for flag, value in optional_pairs:
        if value:
            command.extend([flag, value])
    return command


def _planned_payload(args: argparse.Namespace, command: list[str]) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "project_key": args.project_key,
        "summary": args.summary,
        "issue_type": args.issue_type,
        "priority": args.priority,
        "command": command,
    }
    for field in ("assignee", "labels", "components", "due_date"):
        value = getattr(args, field)
        if value:
            payload[field] = value
    return payload


def parse_jira_json(stdout: str) -> dict[str, Any]:
    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError as exc:
        raise ValueError(f"jiravis returned non-JSON output: {exc}") from exc
    if not isinstance(payload, dict):
        raise ValueError("jiravis returned JSON, but the top-level value is not an object")
    return payload


def normalize_success(payload: dict[str, Any]) -> dict[str, Any]:
    data = payload.get("data") if payload.get("status") == "success" else payload
    if not isinstance(data, dict):
        data = {}
    return {
        "status": "success",
        "data": {
            "ticket_id": data.get("ticket_id"),
            "ticket_url": data.get("ticket_url"),
            "summary": data.get("summary"),
            "issue_type": data.get("issue_type"),
            "priority": data.get("priority"),
            "assignee": data.get("assignee"),
            "due_date": data.get("due_date"),
            "parent": data.get("parent"),
        },
    }


def render_text(payload: dict[str, Any]) -> str:
    data = payload.get("data", {})
    return "\n".join(
        [
            f"Created Jira ticket: {data.get('ticket_id') or ''}",
            f"URL: {data.get('ticket_url') or ''}",
            f"Summary: {data.get('summary') or ''}",
            f"Type: {data.get('issue_type') or ''}",
            f"Priority: {data.get('priority') or ''}",
        ]
    )


def run(args: argparse.Namespace) -> int:
    _require_text(args.project_key, "project key")
    _require_text(args.summary, "summary")
    if args.description is not None:
        _require_text(args.description, "description")

    if args.dry_run:
        description_file = str(args.description_file) if args.description_file else "<temporary-description-file>"
        command = build_jira_command(args, description_file)
        dry_run = {"status": "dry-run", "data": _planned_payload(args, command)}
        print(render_text(dry_run) if args.text else json.dumps(dry_run, indent=2, ensure_ascii=False))
        return 0

    temp_path: str | None = None
    try:
        description_file, is_temp = _description_file_for_args(args)
        temp_path = description_file if is_temp else None
        command = build_jira_command(args, description_file)

        if not shutil.which("jira"):
            raise RuntimeError("jiravis CLI not found: `jira` is not on PATH")

        completed = subprocess.run(command, capture_output=True, check=False, text=True)
        if args.raw:
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

        normalized = normalize_success(parse_jira_json(completed.stdout))
        print(render_text(normalized) if args.text else json.dumps(normalized, indent=2, ensure_ascii=False))
        return 0
    finally:
        if temp_path:
            Path(temp_path).unlink(missing_ok=True)


def main(argv: list[str] | None = None) -> int:
    try:
        return run(parse_args(argv))
    except Exception as exc:
        print(json.dumps({"status": "error", "message": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
