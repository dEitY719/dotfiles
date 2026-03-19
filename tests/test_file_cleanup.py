"""
Tests for del_file() interactive cleanup function.

These tests cover only non-interactive invariants so they remain hermetic.
"""

import pytest


class TestFileCleanupFunction:
    """Basic loading checks for file cleanup helpers."""

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_del_file_function_exists(self, shell_runner, shell):
        result = shell_runner(shell, "declare -f del_file | head -1")
        assert result.exit_code == 0, f"{shell}: del_file not defined"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_del_file_alias_exists(self, shell_runner, shell):
        result = shell_runner(shell, "alias del-file")
        assert result.exit_code == 0, f"{shell}: del-file alias not defined"

    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_default_patterns_are_stable(self, shell_runner, shell):
        result = shell_runner(
            shell,
            '_cleanup_set_default_patterns; for p in "${CLEANUP_DEFAULT_PATTERNS[@]}"; do echo "$p"; done',
        )
        assert result.exit_code == 0, f"{shell}: _cleanup_set_default_patterns failed"
        assert result.stdout.splitlines() == [
            ".*backup*",
            ".*.bak*",
            ".*-original",
        ]
