#!/usr/bin/env bats
# tests/bats/tools/script_help_delegation.bats
# aws/claude/git scripts delegate -h/--help to a help function: exit 0, help
# text unchanged (golden), no side effects (#1915, follow-up of #1880).
# aws/setup.sh, aws/install-otel-managed-settings.sh and claude/setup.sh take no
# arguments and are N/A under the #1880 rule, so they are not covered here.

load '../test_helper'

setup() {
    setup_isolated_home
    # Any external tool a script would reach for after the help branch logs
    # itself here instead of running.
    STUB_BIN="$(mktemp -d)"
    STUB_LOG="$STUB_BIN/calls.log"
    local tool
    for tool in gh aws sudo curl claude jq; do
        printf '#!/bin/sh\necho "%s $*" >>"%s"\nexit 1\n' "$tool" "$STUB_LOG" >"$STUB_BIN/$tool"
        chmod +x "$STUB_BIN/$tool"
    done
    export PATH="$STUB_BIN:$PATH"
    HOME_BEFORE="$(cd "$HOME" && find . | sort)"
}

teardown() {
    rm -rf "$STUB_BIN"
    teardown_isolated_home
}

# Run "$1" with -h and --help from inside $HOME; assert exit 0, exact golden
# output (when given), no stub calls and an untouched $HOME.
_assert_help() {
    local script="$DOTFILES_ROOT/$1" golden="${2-}" flag
    for flag in -h --help; do
        run bash -c 'cd "$HOME" && bash "$1" "$2"' _ "$script" "$flag"
        assert_success
        if [ -n "$golden" ]; then
            assert_output "$golden"
        else
            assert_output --partial "$(basename "$1")"
        fi
    done
    [ ! -e "$STUB_LOG" ]
    [ "$(cd "$HOME" && find . | sort)" = "$HOME_BEFORE" ]
}

@test "aws/diagnose.sh -h|--help: diagnose_help golden, no checks run" {
    _assert_help aws/diagnose.sh "Usage: ./aws/diagnose.sh [-h|--help]

Read-only 진단. ./aws/setup.sh 와 ./aws/install-otel-managed-settings.sh
부트스트랩이 정상 완료되었는지 PASS / FAIL / WARN 으로 보고한다.

체크 항목 (가이드 절 번호):
  1-1) 프록시 인증서 (NODE_EXTRA_CA_CERTS, 사내 프록시 CA 포함 여부)
  1-2) Claude Code 설치 & PATH
  2-2) AWS CLI 설치
  2-3) AWS 인증서/Bedrock env (AWS_CA_BUNDLE, CLAUDE_CODE_USE_BEDROCK,
       ANTHROPIC_BEDROCK_BASE_URL, http(s)_proxy, no_proxy)
  2-4) ~/.aws/config (sso_start_url, sso_role_name, region)
  2-6) ~/.claude/settings.json — JSON 유효성 + dotfiles 소유 필드(.hooks/
       .statusLine)만 SSOT 와 일치하는지 (auth/env/모델은 gateway-cli 영역)
  2-7) /etc/claude-code/managed-settings.json (OTel telemetry)
  2-8) AWS SSO 세션 상태 (aws sts get-caller-identity)

본 스크립트는 read-only — 환경을 수정하지 않는다."
}

@test "claude/plugin/publish-sync.sh -h|--help: publish_sync_help golden, no gh/push" {
    _assert_help claude/plugin/publish-sync.sh "usage: publish-sync.sh [--dry-run]
  Publishes claude/plugin manifest changes to origin (and the
  internal company/ repo when present) via branch + PR + admin-merge.
  --dry-run  show the diff that would be published; no push/PR/merge."
}

@test "git/hooks/install-hooks.sh -h|--help: install_hooks_help, exit 0, no hooks installed" {
    _assert_help git/hooks/install-hooks.sh "Usage: install-hooks.sh <project-path> [--force]

Examples:
  install-hooks.sh ~/workspace/project-a
  install-hooks.sh . --force"
}

@test "git/hooks/install-hooks.sh without args: same usage, still exit 1" {
    run bash "$DOTFILES_ROOT/git/hooks/install-hooks.sh"
    assert_failure 1
    assert_line --index 0 "Usage: install-hooks.sh <project-path> [--force]"
}

@test "already-delegated _usage scripts -h|--help: exit 0, no side effects" {
    local s
    for s in claude/plugin/git-clone-skills.sh claude/plugin/git-pull-skills.sh \
        claude/plugin/reconcile.sh claude/plugin/restore.sh \
        claude/tools/hook-perf-report.sh; do
        _assert_help "$s"
    done
}
