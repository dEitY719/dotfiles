"""Trigger-detection guards for `skill-create`'s eval harness (issue #1412).

`scripts/run_eval.py` registers a uuid-named probe command and watches a
`claude -p` stream for it. The stream decision logic used to stop at the
first tool block, so a run where a real installed skill answered first
scored 0 even though the probe was invoked right after. These tests pin
the decision logic as a pure function over stream lines.
"""

import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent
SKILL_DIR = REPO_ROOT / "claude" / "skills" / "skill-create"

# `run_eval.py` does `from scripts.utils import ...`. The repo root also has a
# `scripts/` directory, which pytest's `pythonpath = ["."]` would otherwise
# bind as an empty namespace package — drop that binding and let the skill's
# own package win.
if str(SKILL_DIR) not in sys.path:
    sys.path.insert(0, str(SKILL_DIR))
sys.modules.pop("scripts", None)

from scripts.run_eval import (  # noqa: E402
    detect_trigger,
    find_shadowing_skills,
    main,
    run_eval,
    run_single_query,
)

PROBE = "write-release-note-skill-deadbeef"


def _start(tool_name: str) -> str:
    return json.dumps(
        {
            "type": "stream_event",
            "event": {
                "type": "content_block_start",
                "content_block": {"type": "tool_use", "name": tool_name},
            },
        }
    )


def _delta(payload: str) -> str:
    return json.dumps(
        {
            "type": "stream_event",
            "event": {
                "type": "content_block_delta",
                "delta": {"type": "input_json_delta", "partial_json": payload},
            },
        }
    )


def _stop() -> str:
    return json.dumps({"type": "stream_event", "event": {"type": "content_block_stop"}})


def _message_stop() -> str:
    return json.dumps({"type": "stream_event", "event": {"type": "message_stop"}})


def test_probe_after_a_real_skill_call_still_counts_as_triggered() -> None:
    """The defect from #1412: an installed skill with the same description
    answers first, and the probe follows in a later tool block."""
    lines = [
        _start("Skill"),
        _delta('{"skill": "write-release-note"}'),
        _stop(),
        _start("Skill"),
        _delta(f'{{"skill": "{PROBE}"}}'),
        _stop(),
        _message_stop(),
    ]

    assert detect_trigger(lines, PROBE) is True


def test_unrelated_tool_call_before_the_probe_does_not_abort_the_query() -> None:
    """Upstream returned False on the first non-Skill/Read block, so a model
    that ran Bash or Grep first scored 0 no matter what it did next."""
    lines = [
        _start("Bash"),
        _delta('{"command": "ls"}'),
        _stop(),
        _start("Skill"),
        _delta(f'{{"skill": "{PROBE}"}}'),
        _stop(),
        _message_stop(),
    ]

    assert detect_trigger(lines, PROBE) is True


def test_assistant_fallback_scans_every_tool_use_in_the_message() -> None:
    """The non-streaming fallback returned inside its own content loop, so
    only the first tool block of an assistant message was ever examined."""
    lines = [
        json.dumps(
            {
                "type": "assistant",
                "message": {
                    "content": [
                        {"type": "tool_use", "name": "Skill", "input": {"skill": "write-release-note"}},
                        {"type": "tool_use", "name": "Skill", "input": {"skill": PROBE}},
                    ]
                },
            }
        ),
        json.dumps({"type": "result"}),
    ]

    assert detect_trigger(lines, PROBE) is True


def test_a_stream_that_never_names_the_probe_is_not_triggered() -> None:
    """Complement to the cases above: scanning every block must not degrade
    into 'any Skill call counts'."""
    lines = [
        _start("Skill"),
        _delta('{"skill": "write-release-note"}'),
        _stop(),
        _start("Skill"),
        _delta('{"skill": "some-other-skill"}'),
        _stop(),
        _message_stop(),
    ]

    assert detect_trigger(lines, PROBE) is False


def test_reading_the_probe_command_file_counts_as_a_trigger() -> None:
    """A model may consult the skill by reading its file instead of invoking
    it; upstream accepted that and the rewrite must keep doing so."""
    lines = [
        _start("Skill"),
        _delta('{"skill": "write-release-note"}'),
        _stop(),
        _start("Read"),
        _delta(f'{{"file_path": "/repo/.claude/commands/{PROBE}.md"}}'),
        _stop(),
        _message_stop(),
    ]

    assert detect_trigger(lines, PROBE) is True


def _install_fake_claude(bin_dir: Path, script: str) -> None:
    bin_dir.mkdir(parents=True, exist_ok=True)
    exe = bin_dir / "claude"
    exe.write_text(script)
    exe.chmod(0o755)


def test_a_failed_claude_invocation_is_reported_as_an_error(tmp_path, monkeypatch) -> None:
    """`stderr=DEVNULL` made auth expiry, the nesting guard and timeouts look
    exactly like a description that simply never triggers (#1412 F-2)."""
    _install_fake_claude(
        tmp_path / "bin",
        "#!/bin/sh\necho 'Invalid API key - please run /login' >&2\nexit 1\n",
    )
    monkeypatch.setenv("PATH", f"{tmp_path / 'bin'}{os.pathsep}{os.environ['PATH']}")

    outcome = run_single_query("summarise the release", "demo-skill", "demo description", 30, str(tmp_path))

    assert outcome["triggered"] is False
    assert outcome["error"] is not None
    assert "Invalid API key" in outcome["error"]


def test_a_query_whose_every_run_failed_cannot_be_reported_as_a_pass(tmp_path, monkeypatch) -> None:
    """A should-not-trigger query used to 'pass' when the harness was dead:
    zero triggers is below the threshold either way."""
    _install_fake_claude(tmp_path / "bin", "#!/bin/sh\necho 'nested session guard' >&2\nexit 1\n")
    monkeypatch.setenv("PATH", f"{tmp_path / 'bin'}{os.pathsep}{os.environ['PATH']}")

    output = run_eval(
        eval_set=[{"query": "what is the weather", "should_trigger": False}],
        skill_name="demo-skill",
        description="demo description",
        num_workers=1,
        timeout=10,
        project_root=tmp_path,
        runs_per_query=2,
    )

    result = output["results"][0]
    assert result["errors"] == 2
    assert result["pass"] is False
    assert output["summary"]["errors"] == 2


# A `claude` stand-in that reproduces the #1412 environment: an installed skill
# sharing the evaluated description answers first, and the uuid probe follows.
# It discovers the probe name from the command file run_single_query wrote.
FAKE_CLAUDE_SHADOWED = """#!/usr/bin/env python3
import json
from pathlib import Path

probe = sorted(Path(".claude/commands").glob("*.md"))[0].stem


def emit(**event):
    print(json.dumps({"type": "stream_event", "event": event}))


for skill in ("demo-skill", probe):
    emit(type="content_block_start", content_block={"type": "tool_use", "name": "Skill"})
    payload = json.dumps({"skill": skill})
    emit(type="content_block_delta", delta={"type": "input_json_delta", "partial_json": payload})
    emit(type="content_block_stop")
emit(type="message_stop")
print(json.dumps({"type": "result"}))
"""


def test_end_to_end_trigger_survives_a_skill_shadowing_the_description(tmp_path, monkeypatch) -> None:
    """Acceptance criterion #1: with the real skill visible alongside the probe,
    the eval must still score the query as triggered."""
    _install_fake_claude(tmp_path / "bin", FAKE_CLAUDE_SHADOWED)
    monkeypatch.setenv("PATH", f"{tmp_path / 'bin'}{os.pathsep}{os.environ['PATH']}")

    output = run_eval(
        eval_set=[{"query": "write the release notes for v2", "should_trigger": True}],
        skill_name="demo-skill",
        description="demo description",
        num_workers=1,
        timeout=20,
        project_root=tmp_path,
        runs_per_query=2,
    )

    result = output["results"][0]
    assert result["errors"] == 0
    assert result["trigger_rate"] == 1.0
    assert result["pass"] is True


def test_an_installed_skill_of_the_same_name_is_reported_as_shadowing(tmp_path, monkeypatch) -> None:
    """#1412 F-3: the isolation workaround is easy to forget, and forgetting it
    used to produce a silently wrong zero. Say so out loud instead."""
    config_dir = tmp_path / "claude-config"
    installed = config_dir / "skills" / "write-release-note"
    installed.mkdir(parents=True)
    (installed / "SKILL.md").write_text("---\nname: write:release-note\n---\n")
    monkeypatch.setenv("CLAUDE_CONFIG_DIR", str(config_dir))
    monkeypatch.setenv("HOME", str(tmp_path / "home"))

    found = find_shadowing_skills("write:release-note", tmp_path / "project")

    assert installed in found


def test_the_skill_under_evaluation_is_not_its_own_shadow(tmp_path, monkeypatch) -> None:
    """Evaluating an already-installed skill in place is the normal case — that
    directory is the subject, not a competitor."""
    config_dir = tmp_path / "claude-config"
    installed = config_dir / "skills" / "demo-skill"
    installed.mkdir(parents=True)
    (installed / "SKILL.md").write_text("---\nname: demo-skill\n---\n")
    monkeypatch.setenv("CLAUDE_CONFIG_DIR", str(config_dir))
    monkeypatch.setenv("HOME", str(tmp_path / "home"))

    found = find_shadowing_skills("demo-skill", tmp_path / "project", skill_path=installed)

    assert found == []


def _prepare_main_fixture(tmp_path, monkeypatch, claude_script: str) -> Path:
    """Lay out a project root, a skill to evaluate, a same-named installed
    skill that shadows it, and a `claude` stand-in. Returns the eval-set path."""
    project = tmp_path / "project"
    (project / ".claude").mkdir(parents=True)

    skill = tmp_path / "work" / "demo-skill"
    skill.mkdir(parents=True)
    (skill / "SKILL.md").write_text("---\nname: demo-skill\ndescription: demo description for eval\n---\n\n# Demo\n")

    shadow = tmp_path / "claude-config" / "skills" / "demo-skill"
    shadow.mkdir(parents=True)
    (shadow / "SKILL.md").write_text("---\nname: demo-skill\ndescription: demo description for eval\n---\n")

    eval_set = tmp_path / "eval.json"
    eval_set.write_text(json.dumps([{"query": "write the release notes for v2", "should_trigger": True}]))

    _install_fake_claude(tmp_path / "bin", claude_script)
    monkeypatch.setenv("PATH", f"{tmp_path / 'bin'}{os.pathsep}{os.environ['PATH']}")
    monkeypatch.setenv("CLAUDE_CONFIG_DIR", str(tmp_path / "claude-config"))
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    monkeypatch.chdir(project)
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "run_eval.py",
            "--eval-set",
            str(eval_set),
            "--skill-path",
            str(skill),
            "--num-workers",
            "1",
            "--runs-per-query",
            "1",
            "--timeout",
            "20",
            "--verbose",
        ],
    )
    return eval_set


def test_main_warns_when_an_installed_skill_shadows_the_one_being_evaluated(tmp_path, monkeypatch, capsys) -> None:
    _prepare_main_fixture(tmp_path, monkeypatch, FAKE_CLAUDE_SHADOWED)

    main()

    stderr = capsys.readouterr().err
    assert "shadow" in stderr.lower()
    assert "demo-skill" in stderr


def test_main_reports_harness_failures_separately_from_non_triggering(tmp_path, monkeypatch, capsys) -> None:
    """Acceptance criterion #2: a dead `claude -p` must not read as a tidy 0/1."""
    _prepare_main_fixture(tmp_path, monkeypatch, "#!/bin/sh\necho 'Invalid API key' >&2\nexit 1\n")

    main()

    captured = capsys.readouterr()
    assert "Invalid API key" in captured.err
    assert "ERROR" in captured.err

    output = json.loads(captured.out)
    assert output["summary"]["errors"] == 1
    assert output["results"][0]["pass"] is False
