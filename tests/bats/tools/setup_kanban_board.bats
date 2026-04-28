#!/usr/bin/env bats
# tests/bats/tools/setup_kanban_board.bats
# Offline coverage for scripts/setup-kanban-board.sh.

load '../test_helper'

SETUP_KANBAN_SCRIPT="${DOTFILES_ROOT}/scripts/setup-kanban-board.sh"

setup() {
    setup_isolated_home

    MOCK_BIN="${TEST_TEMP_HOME}/mock-bin"
    MOCK_LOG="${TEST_TEMP_HOME}/mock-gh.log"
    mkdir -p "$MOCK_BIN"

    cat >"${MOCK_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${MOCK_GH_LOG}"

if [[ "$1" == "auth" && "$2" == "status" ]]; then
    printf 'unknown flag: --json\n' >&2
    exit 1
fi

if [[ "$1" == "repo" && "$2" == "view" ]]; then
    if [ -n "${MOCK_GH_REPO_VIEW_OUTPUT-}" ]; then
        printf '%s\n' "${MOCK_GH_REPO_VIEW_OUTPUT}"
        exit 0
    fi
    printf 'no git remote found for current directory\n' >&2
    exit 1
fi

if [[ "$1" == "api" && "$2" == "user" && "${3-}" == "-i" ]]; then
    cat "${MOCK_GH_AUTH_HEADERS}"
    exit 0
fi

if [[ "$1" == "api" && "$2" == "graphql" ]]; then
    query=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f)
                if [[ "${2-}" == query=* ]]; then
                    query="${2#query=}"
                fi
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    case "$query" in
        *"query RepoContext"*)
            cat "${MOCK_GH_REPO_CONTEXT_JSON}"
            ;;
        *"query ExistingProjects"*)
            cat "${MOCK_GH_EXISTING_PROJECTS_JSON}"
            ;;
        *"mutation CreateProject"*)
            cat "${MOCK_GH_CREATE_PROJECT_JSON}"
            ;;
        *"mutation LinkProject"*)
            printf '{"data":{"linkProjectV2ToRepository":{"repository":{"id":"R_123"}}}}\n'
            ;;
        *"query StatusField"*)
            cat "${MOCK_GH_STATUS_FIELD_JSON}"
            ;;
        *"mutation UpdateStatusField"*)
            printf '{"data":{"updateProjectV2Field":{"projectV2Field":{"id":"PVTSSF_status"}}}}\n'
            ;;
        *"query PullRequestTemplate"*)
            cat "${MOCK_GH_TEMPLATE_JSON}"
            ;;
        *)
            printf 'Unhandled graphql query:\n%s\n' "$query" >&2
            exit 1
            ;;
    esac
    exit 0
fi

if [[ "$1" == "api" && "$2" == "--method" && "$3" == "PUT" ]]; then
    printf '{"content":{"path":".github/pull_request_template.md"}}\n'
    exit 0
fi

printf 'Unhandled gh invocation: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"

    export MOCK_GH_LOG="$MOCK_LOG"
    export PATH="${MOCK_BIN}:${PATH}"
}

teardown() {
    teardown_isolated_home
}

write_json_fixture() {
    local path="$1"
    shift
    cat >"$path" <<EOF
$*
EOF
}

write_auth_headers() {
    local path="$1"
    local scopes="$2"

    cat >"$path" <<EOF
HTTP/2 200
x-oauth-scopes: ${scopes}
content-type: application/json

{"login":"mock"}
EOF
}

run_setup_kanban() {
    run bash "$SETUP_KANBAN_SCRIPT" "$@"
}

@test "dry-run accepts read-only project scope and prints org workflow checklist" {
    export MOCK_GH_AUTH_HEADERS="${TEST_TEMP_HOME}/auth-headers.txt"
    export MOCK_GH_REPO_CONTEXT_JSON="${TEST_TEMP_HOME}/repo.json"
    export MOCK_GH_EXISTING_PROJECTS_JSON="${TEST_TEMP_HOME}/projects.json"
    export MOCK_GH_CREATE_PROJECT_JSON="${TEST_TEMP_HOME}/create.json"
    export MOCK_GH_STATUS_FIELD_JSON="${TEST_TEMP_HOME}/status.json"
    export MOCK_GH_TEMPLATE_JSON="${TEST_TEMP_HOME}/template.json"

    write_auth_headers "$MOCK_GH_AUTH_HEADERS" "repo, read:project"
    write_json_fixture "$MOCK_GH_REPO_CONTEXT_JSON" \
        '{"data":{"repository":{"id":"R_org","name":"widget","url":"https://github.com/acme/widget","owner":{"__typename":"Organization","login":"acme","id":"O_1"},"defaultBranchRef":{"name":"main"}}}}'
    write_json_fixture "$MOCK_GH_EXISTING_PROJECTS_JSON" \
        '{"data":{"repositoryOwner":{"__typename":"Organization","projectsV2":{"nodes":[]}}}}'
    write_json_fixture "$MOCK_GH_CREATE_PROJECT_JSON" \
        '{"data":{"createProjectV2":{"projectV2":{"id":"PVT_new","number":77,"title":"widget","url":"https://github.com/orgs/acme/projects/77"}}}}'
    write_json_fixture "$MOCK_GH_STATUS_FIELD_JSON" \
        '{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_status","name":"Status"}]}}}}'
    write_json_fixture "$MOCK_GH_TEMPLATE_JSON" \
        '{"data":{"repository":{"object":null}}}'

    run_setup_kanban --owner acme --repo widget --dry-run --hide-columns
    assert_success
    assert_output --partial "[dry-run] Would create project 'widget' under acme"
    assert_output --partial "Workflows: https://github.com/orgs/acme/projects/0/workflows"
    assert_output --partial "hide 'Approved' and 'Ready'"

    grep -q '^api user -i$' "$MOCK_LOG"
    if grep -q '^auth status' "$MOCK_LOG"; then
        echo "auth status should not be used for scope detection"
        return 1
    fi

    if grep -q 'mutation CreateProject' "$MOCK_LOG"; then
        echo "CreateProject mutation should not run in dry-run mode"
        return 1
    fi
}

@test "existing project exits successfully without mutations" {
    export MOCK_GH_AUTH_HEADERS="${TEST_TEMP_HOME}/auth-headers.txt"
    export MOCK_GH_REPO_CONTEXT_JSON="${TEST_TEMP_HOME}/repo.json"
    export MOCK_GH_EXISTING_PROJECTS_JSON="${TEST_TEMP_HOME}/projects.json"
    export MOCK_GH_CREATE_PROJECT_JSON="${TEST_TEMP_HOME}/create.json"
    export MOCK_GH_STATUS_FIELD_JSON="${TEST_TEMP_HOME}/status.json"
    export MOCK_GH_TEMPLATE_JSON="${TEST_TEMP_HOME}/template.json"

    write_auth_headers "$MOCK_GH_AUTH_HEADERS" "repo, project"
    write_json_fixture "$MOCK_GH_REPO_CONTEXT_JSON" \
        '{"data":{"repository":{"id":"R_user","name":"dotfiles","url":"https://github.com/deity/dotfiles","owner":{"__typename":"User","login":"deity","id":"U_1"},"defaultBranchRef":{"name":"main"}}}}'
    write_json_fixture "$MOCK_GH_EXISTING_PROJECTS_JSON" \
        '{"data":{"repositoryOwner":{"__typename":"User","projectsV2":{"nodes":[{"id":"PVT_existing","number":12,"title":"dotfiles","url":"https://github.com/users/deity/projects/12"}]}}}}'
    write_json_fixture "$MOCK_GH_CREATE_PROJECT_JSON" \
        '{"data":{"createProjectV2":{"projectV2":{"id":"PVT_new","number":77,"title":"dotfiles","url":"https://github.com/users/deity/projects/77"}}}}'
    write_json_fixture "$MOCK_GH_STATUS_FIELD_JSON" \
        '{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_status","name":"Status"}]}}}}'
    write_json_fixture "$MOCK_GH_TEMPLATE_JSON" \
        '{"data":{"repository":{"object":null}}}'

    run_setup_kanban --owner deity --repo dotfiles
    assert_success
    assert_output --partial "already exists (#12)"
    assert_output --partial "https://github.com/users/deity/projects/12"

    if grep -q 'mutation CreateProject' "$MOCK_LOG"; then
        echo "CreateProject mutation should not run for an existing board"
        return 1
    fi
}

@test "new project path performs project, field, and template mutations" {
    export MOCK_GH_AUTH_HEADERS="${TEST_TEMP_HOME}/auth-headers.txt"
    export MOCK_GH_REPO_CONTEXT_JSON="${TEST_TEMP_HOME}/repo.json"
    export MOCK_GH_EXISTING_PROJECTS_JSON="${TEST_TEMP_HOME}/projects.json"
    export MOCK_GH_CREATE_PROJECT_JSON="${TEST_TEMP_HOME}/create.json"
    export MOCK_GH_STATUS_FIELD_JSON="${TEST_TEMP_HOME}/status.json"
    export MOCK_GH_TEMPLATE_JSON="${TEST_TEMP_HOME}/template.json"

    write_auth_headers "$MOCK_GH_AUTH_HEADERS" "repo, project"
    write_json_fixture "$MOCK_GH_REPO_CONTEXT_JSON" \
        '{"data":{"repository":{"id":"R_new","name":"widget","url":"https://github.com/deity/widget","owner":{"__typename":"User","login":"deity","id":"U_9"},"defaultBranchRef":{"name":"main"}}}}'
    write_json_fixture "$MOCK_GH_EXISTING_PROJECTS_JSON" \
        '{"data":{"repositoryOwner":{"__typename":"User","projectsV2":{"nodes":[]}}}}'
    write_json_fixture "$MOCK_GH_CREATE_PROJECT_JSON" \
        '{"data":{"createProjectV2":{"projectV2":{"id":"PVT_new","number":34,"title":"Widget Board","url":"https://github.com/users/deity/projects/34"}}}}'
    write_json_fixture "$MOCK_GH_STATUS_FIELD_JSON" \
        '{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_status","name":"Status"}]}}}}'
    write_json_fixture "$MOCK_GH_TEMPLATE_JSON" \
        '{"data":{"repository":{"object":null}}}'

    run_setup_kanban --owner deity --repo widget --title "Widget Board"
    assert_success
    assert_output --partial "Created .github/pull_request_template.md on main"
    assert_output --partial "Board: https://github.com/users/deity/projects/34"
    assert_output --partial "gh issue create --repo deity/widget --title \"[Test] kanban smoke\" --body \"ignore\""

    grep -q 'mutation CreateProject' "$MOCK_LOG"
    grep -q 'mutation LinkProject' "$MOCK_LOG"
    grep -q 'mutation UpdateStatusField' "$MOCK_LOG"
    grep -q 'repos/deity/widget/contents/.github/pull_request_template.md' "$MOCK_LOG"
}

@test "missing project scope fails from gh api header scopes" {
    export MOCK_GH_AUTH_HEADERS="${TEST_TEMP_HOME}/auth-headers.txt"

    write_auth_headers "$MOCK_GH_AUTH_HEADERS" "repo, gist"

    run_setup_kanban --owner deity --repo dotfiles
    assert_failure
    assert_output --partial "Your gh token is missing the project scope required for mutations"
    grep -q '^api user -i$' "$MOCK_LOG"
}

@test "auto-detects --owner and --repo from current git context when both omitted" {
    export MOCK_GH_AUTH_HEADERS="${TEST_TEMP_HOME}/auth-headers.txt"
    export MOCK_GH_REPO_CONTEXT_JSON="${TEST_TEMP_HOME}/repo.json"
    export MOCK_GH_EXISTING_PROJECTS_JSON="${TEST_TEMP_HOME}/projects.json"
    export MOCK_GH_CREATE_PROJECT_JSON="${TEST_TEMP_HOME}/create.json"
    export MOCK_GH_STATUS_FIELD_JSON="${TEST_TEMP_HOME}/status.json"
    export MOCK_GH_TEMPLATE_JSON="${TEST_TEMP_HOME}/template.json"
    export MOCK_GH_REPO_VIEW_OUTPUT="acme widget"

    write_auth_headers "$MOCK_GH_AUTH_HEADERS" "repo, read:project"
    write_json_fixture "$MOCK_GH_REPO_CONTEXT_JSON" \
        '{"data":{"repository":{"id":"R_org","name":"widget","url":"https://github.com/acme/widget","owner":{"__typename":"Organization","login":"acme","id":"O_1"},"defaultBranchRef":{"name":"main"}}}}'
    write_json_fixture "$MOCK_GH_EXISTING_PROJECTS_JSON" \
        '{"data":{"repositoryOwner":{"__typename":"Organization","projectsV2":{"nodes":[]}}}}'
    write_json_fixture "$MOCK_GH_CREATE_PROJECT_JSON" \
        '{"data":{"createProjectV2":{"projectV2":{"id":"PVT_new","number":77,"title":"widget","url":"https://github.com/orgs/acme/projects/77"}}}}'
    write_json_fixture "$MOCK_GH_STATUS_FIELD_JSON" \
        '{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_status","name":"Status"}]}}}}'
    write_json_fixture "$MOCK_GH_TEMPLATE_JSON" \
        '{"data":{"repository":{"object":null}}}'

    run_setup_kanban --dry-run
    assert_success
    assert_output --partial "[dry-run] Would create project 'widget' under acme"
    grep -q '^repo view --json owner,name' "$MOCK_LOG"
}

@test "fails with auto-detect hint when args omitted and gh repo view fails" {
    export MOCK_GH_AUTH_HEADERS="${TEST_TEMP_HOME}/auth-headers.txt"
    write_auth_headers "$MOCK_GH_AUTH_HEADERS" "repo, project"

    run_setup_kanban --dry-run
    assert_failure
    assert_output --partial "auto-detect"
    grep -q '^repo view --json owner,name' "$MOCK_LOG"
}

@test "explicit --owner is preserved when only --repo can be auto-detected" {
    export MOCK_GH_AUTH_HEADERS="${TEST_TEMP_HOME}/auth-headers.txt"
    export MOCK_GH_REPO_CONTEXT_JSON="${TEST_TEMP_HOME}/repo.json"
    export MOCK_GH_EXISTING_PROJECTS_JSON="${TEST_TEMP_HOME}/projects.json"
    export MOCK_GH_CREATE_PROJECT_JSON="${TEST_TEMP_HOME}/create.json"
    export MOCK_GH_STATUS_FIELD_JSON="${TEST_TEMP_HOME}/status.json"
    export MOCK_GH_TEMPLATE_JSON="${TEST_TEMP_HOME}/template.json"
    export MOCK_GH_REPO_VIEW_OUTPUT="acme widget"

    write_auth_headers "$MOCK_GH_AUTH_HEADERS" "repo, read:project"
    write_json_fixture "$MOCK_GH_REPO_CONTEXT_JSON" \
        '{"data":{"repository":{"id":"R_org","name":"widget","url":"https://github.com/myorg/widget","owner":{"__typename":"Organization","login":"myorg","id":"O_2"},"defaultBranchRef":{"name":"main"}}}}'
    write_json_fixture "$MOCK_GH_EXISTING_PROJECTS_JSON" \
        '{"data":{"repositoryOwner":{"__typename":"Organization","projectsV2":{"nodes":[]}}}}'
    write_json_fixture "$MOCK_GH_CREATE_PROJECT_JSON" \
        '{"data":{"createProjectV2":{"projectV2":{"id":"PVT_new","number":77,"title":"widget","url":"https://github.com/orgs/myorg/projects/77"}}}}'
    write_json_fixture "$MOCK_GH_STATUS_FIELD_JSON" \
        '{"data":{"node":{"fields":{"nodes":[{"id":"PVTSSF_status","name":"Status"}]}}}}'
    write_json_fixture "$MOCK_GH_TEMPLATE_JSON" \
        '{"data":{"repository":{"object":null}}}'

    run_setup_kanban --owner myorg --dry-run
    assert_success
    assert_output --partial "[dry-run] Would create project 'widget' under myorg"
}

@test "scope parser ignores x-oauth-scopes text in response body" {
    export MOCK_GH_AUTH_HEADERS="${TEST_TEMP_HOME}/auth-headers.txt"

    cat >"$MOCK_GH_AUTH_HEADERS" <<'EOF'
HTTP/2 200
content-type: application/json

x-oauth-scopes: project
{"login":"mock"}
EOF

    run_setup_kanban --owner deity --repo dotfiles
    assert_failure
    assert_output --partial "gh api user could not read token scopes"
    grep -q '^api user -i$' "$MOCK_LOG"
}
