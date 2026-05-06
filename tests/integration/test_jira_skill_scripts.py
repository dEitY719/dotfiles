from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
from pathlib import Path
from types import ModuleType

ROOT = Path(__file__).resolve().parents[2]


def load_module(path: str, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_create_ticket_dry_run_uses_description_file_placeholder(capsys) -> None:
    module = load_module("claude/skills/jira-create/scripts/create_ticket.py", "jira_create_ticket")

    exit_code = module.main(
        [
            "--project-key",
            "JIRAVIS",
            "--summary",
            "Build adapter",
            "--description",
            "Line 1\nLine 2",
            "--labels",
            "skill,jira",
            "--components",
            "Agent Enabler(AX)",
            "--dry-run",
        ]
    )

    assert exit_code == 0
    payload = json.loads(capsys.readouterr().out)
    command = payload["data"]["command"]
    assert payload["status"] == "dry-run"
    assert "--description-file" in command
    assert "Line 1\nLine 2" not in command
    assert "--labels" in command
    assert "--components" in command


def test_create_ticket_dry_run_text_does_not_claim_created(capsys) -> None:
    module = load_module("claude/skills/jira-create/scripts/create_ticket.py", "jira_create_ticket_text")

    exit_code = module.main(
        [
            "--project-key",
            "JIRAVIS",
            "--summary",
            "Build adapter",
            "--description",
            "Line 1",
            "--dry-run",
            "--text",
        ]
    )

    assert exit_code == 0
    output = capsys.readouterr().out
    assert "Dry run: would create Jira ticket in project JIRAVIS" in output
    assert "Created Jira ticket:" not in output


def test_create_ticket_normalizes_jiravis_success(monkeypatch, capsys) -> None:
    module = load_module("claude/skills/jira-create/scripts/create_ticket.py", "jira_create_ticket_success")
    captured_description = {}

    def fake_run(command, capture_output, check, text):
        assert command[:2] == ["jira", "create-ticket"]
        description_path = Path(command[command.index("--description-file") + 1])
        captured_description["text"] = description_path.read_text(encoding="utf-8")
        stdout = json.dumps(
            {
                "status": "success",
                "data": {
                    "ticket_id": "JIRAVIS-123",
                    "ticket_url": "https://jira.example.com/browse/JIRAVIS-123",
                    "summary": "Build adapter",
                    "issue_type": "Task",
                    "priority": "Medium",
                },
            }
        )
        return subprocess.CompletedProcess(command, 0, stdout=stdout, stderr="")

    monkeypatch.setattr(module.shutil, "which", lambda name: "/usr/local/bin/jira")
    monkeypatch.setattr(module.subprocess, "run", fake_run)

    exit_code = module.main(
        [
            "--project-key",
            "JIRAVIS",
            "--summary",
            "Build adapter",
            "--description",
            "Detailed body",
        ]
    )

    assert exit_code == 0
    assert captured_description["text"] == "Detailed body"
    payload = json.loads(capsys.readouterr().out)
    assert payload["data"]["ticket_id"] == "JIRAVIS-123"
    assert payload["data"]["summary"] == "Build adapter"


def test_create_ticket_preserves_jiravis_error_payload(monkeypatch, capsys) -> None:
    module = load_module("claude/skills/jira-create/scripts/create_ticket.py", "jira_create_ticket_error")

    def fake_run(command, capture_output, check, text):
        stdout = json.dumps({"status": "error", "message": "Jira rejected the request"})
        return subprocess.CompletedProcess(command, 0, stdout=stdout, stderr="")

    monkeypatch.setattr(module.shutil, "which", lambda name: "/usr/local/bin/jira")
    monkeypatch.setattr(module.subprocess, "run", fake_run)

    exit_code = module.main(
        [
            "--project-key",
            "JIRAVIS",
            "--summary",
            "Build adapter",
            "--description",
            "Detailed body",
        ]
    )

    assert exit_code == 1
    payload = json.loads(capsys.readouterr().err)
    assert payload["status"] == "error"
    assert payload["message"] == "Jira rejected the request"


def test_create_ticket_temp_file_is_cleaned_when_write_fails(monkeypatch, tmp_path) -> None:
    module = load_module("claude/skills/jira-create/scripts/create_ticket.py", "jira_create_ticket_temp_cleanup")
    temp_path = tmp_path / "description.md"

    class FailingTempFile:
        name = str(temp_path)

        def __enter__(self):
            temp_path.touch()
            return self

        def __exit__(self, exc_type, exc, traceback):
            return False

        def write(self, value):
            raise OSError("disk full")

    monkeypatch.setattr(tempfile, "NamedTemporaryFile", lambda *args, **kwargs: FailingTempFile())
    args = module.parse_args(
        [
            "--project-key",
            "JIRAVIS",
            "--summary",
            "Build adapter",
            "--description",
            "Detailed body",
        ]
    )

    try:
        module._description_file_for_args(args)
    except OSError:
        pass
    else:
        raise AssertionError("expected write failure")

    assert not temp_path.exists()


def test_read_ticket_validates_and_uppercases_ticket_id() -> None:
    module = load_module("claude/skills/jira-read/scripts/read_ticket.py", "jira_read_ticket")

    assert module.normalize_ticket_id("jiravis-123") == "JIRAVIS-123"

    try:
        module.normalize_ticket_id("not-a-ticket")
    except ValueError as exc:
        assert "expected PROJECT-123" in str(exc)
    else:
        raise AssertionError("expected invalid ticket id to raise")


def test_read_ticket_calls_read_only_jiravis_command(monkeypatch, capsys) -> None:
    module = load_module("claude/skills/jira-read/scripts/read_ticket.py", "jira_read_ticket_success")
    captured_command = {}

    def fake_run(command, capture_output, check, text):
        captured_command["command"] = command
        stdout = json.dumps(
            {
                "status": "success",
                "data": {
                    "ticket_id": "JIRAVIS-123",
                    "ticket_url": "https://jira.example.com/browse/JIRAVIS-123",
                    "summary": "Build adapter",
                    "description": "Implementation context",
                    "status": "In Progress",
                    "priority": "High",
                    "assignee": {"display_name": "Ada"},
                    "reporter": {"display_name": "Grace"},
                    "labels": ["skill"],
                    "components": ["CLI"],
                    "subtasks": [{"ticket_id": "JIRAVIS-124", "summary": "Child", "status": "Open"}],
                },
            }
        )
        return subprocess.CompletedProcess(command, 0, stdout=stdout, stderr="")

    monkeypatch.setattr(module.shutil, "which", lambda name: "/usr/local/bin/jira")
    monkeypatch.setattr(module.subprocess, "run", fake_run)

    exit_code = module.main(["--ticket-id", "jiravis-123"])

    assert exit_code == 0
    assert captured_command["command"][:2] == ["jira", "get-ticket-detail"]
    assert "create-ticket" not in captured_command["command"]
    assert "update-ticket" not in captured_command["command"]
    payload = json.loads(capsys.readouterr().out)
    assert payload["data"]["ticket_id"] == "JIRAVIS-123"
    assert payload["data"]["assignee"] == "Ada"
    assert payload["data"]["subtasks"][0]["ticket_id"] == "JIRAVIS-124"


def test_read_ticket_preserves_jiravis_error_payload(monkeypatch, capsys) -> None:
    module = load_module("claude/skills/jira-read/scripts/read_ticket.py", "jira_read_ticket_error")

    def fake_run(command, capture_output, check, text):
        stdout = json.dumps({"status": "error", "message": "Ticket not found"})
        return subprocess.CompletedProcess(command, 0, stdout=stdout, stderr="")

    monkeypatch.setattr(module.shutil, "which", lambda name: "/usr/local/bin/jira")
    monkeypatch.setattr(module.subprocess, "run", fake_run)

    exit_code = module.main(["--ticket-id", "JIRAVIS-123"])

    assert exit_code == 1
    payload = json.loads(capsys.readouterr().err)
    assert payload["status"] == "error"
    assert payload["message"] == "Ticket not found"
