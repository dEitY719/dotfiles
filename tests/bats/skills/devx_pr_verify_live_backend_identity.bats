#!/usr/bin/env bats
# tests/bats/skills/devx_pr_verify_live_backend_identity.bats
# Integration tests for devx_pr_verify_live_backend_identity.py helper.

load '../test_helper'

setup() {
    setup_isolated_home
    # Create bin directory for fake executables
    mkdir -p "$TEST_TEMP_HOME/bin"
    export PATH="$TEST_TEMP_HOME/bin:$PATH"
    
    # Paths
    HELPER_PY="${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/devx_pr_verify_live_backend_identity.py"
    REPO_ROOT="$TEST_TEMP_HOME/repo"
    mkdir -p "$REPO_ROOT"

    # Default mock docker that fails (hermetic)
    cat <<'EOF' > "$TEST_TEMP_HOME/bin/docker"
#!/bin/sh
exit 1
EOF
    chmod +x "$TEST_TEMP_HOME/bin/docker"

    # Default mock ss that fails
    cat <<'EOF' > "$TEST_TEMP_HOME/bin/ss"
#!/bin/sh
exit 1
EOF
    chmod +x "$TEST_TEMP_HOME/bin/ss"

    # Default mock lsof that fails
    cat <<'EOF' > "$TEST_TEMP_HOME/bin/lsof"
#!/bin/sh
exit 1
EOF
    chmod +x "$TEST_TEMP_HOME/bin/lsof"

    # Default mock ps that returns python
    cat <<'EOF' > "$TEST_TEMP_HOME/bin/ps"
#!/bin/sh
echo "python"
EOF
    chmod +x "$TEST_TEMP_HOME/bin/ps"

    # Default mock git
    cat <<EOF > "$TEST_TEMP_HOME/bin/git"
#!/bin/sh
exit 1
EOF
    chmod +x "$TEST_TEMP_HOME/bin/git"
}

teardown() {
    teardown_isolated_home
}

@test "host success path" {
    # 1. Fake ss outputting host PID 12345
    cat <<'EOF' > "$TEST_TEMP_HOME/bin/ss"
#!/bin/sh
if echo "$*" | grep -q -- "-ltnp"; then
    echo 'LISTEN 0 4096 127.0.0.1:8000 0.0.0.0:* users:(("python",pid=12345,fd=3))'
fi
EOF
    chmod +x "$TEST_TEMP_HOME/bin/ss"

    # 2. Fake lsof returning correct format
    cat <<EOF > "$TEST_TEMP_HOME/bin/lsof"
#!/bin/sh
if echo "\$*" | grep -q -- "-Fn"; then
    echo "p12345"
    echo "fcwd"
    echo "n$REPO_ROOT"
else
    # lsof -nP -iTCP:8000 -sTCP:LISTEN
    echo "COMMAND     PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME"
    echo "python    12345 user    3u  IPv4  12345      0t0  TCP 127.0.0.1:8000 (LISTEN)"
fi
EOF
    chmod +x "$TEST_TEMP_HOME/bin/lsof"

    # 3. Fake git returning success for toplevel and merge-base checks
    cat <<EOF > "$TEST_TEMP_HOME/bin/git"
#!/bin/sh
# Check arguments
if echo "\$*" | grep -q -- "rev-parse --show-toplevel"; then
    echo "$REPO_ROOT"
    exit 0
elif echo "\$*" | grep -q -- "merge-base --is-ancestor"; then
    exit 0
elif echo "\$*" | grep -q -- "rev-parse HEAD"; then
    echo "verified_commit_sha"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_TEMP_HOME/bin/git"

    # Run Python script directly
    run python3 "$HELPER_PY" --repo-root "$REPO_ROOT" --target-repo "foo/bar" --target-sha "target_sha" --base-url "http://localhost:3000" --backend-ports "8000"
    assert_success
    assert_output --partial '"result": "verified"'
    assert_output --partial '"mode": "host-pid-ancestry"'
}

@test "docker success path" {
    # 1. ss/lsof return nothing (no host process)
    cat <<'EOF' > "$TEST_TEMP_HOME/bin/ss"
#!/bin/sh
exit 0
EOF
    chmod +x "$TEST_TEMP_HOME/bin/ss"

    # 2. Fake docker ps returning candidate container
    cat <<'EOF' > "$TEST_TEMP_HOME/bin/docker"
#!/bin/sh
case "$*" in
    *ps*)
        echo "my-container-backend 0.0.0.0:8000->8000/tcp"
        exit 0
        ;;
    *inspect*)
        # Return mounts pointing to our repo_root
        # Source must match args.repo_root which is $REPO_ROOT
        # Destination: /app
        echo '[{"Mounts": [{"Source": "'"$REPO_ROOT"'", "Destination": "/app"}], "Config": {"WorkingDir": "/app"}}]'
        exit 0
        ;;
    *exec*)
        # docker exec my-container-backend git -C /app rev-parse --show-toplevel
        # docker exec my-container-backend git -C /app merge-base --is-ancestor target_sha HEAD
        if echo "$*" | grep -q -- "rev-parse --show-toplevel"; then
            echo "/app"
            exit 0
        elif echo "$*" | grep -q -- "merge-base --is-ancestor"; then
            exit 0
        elif echo "$*" | grep -q -- "rev-parse HEAD"; then
            echo "docker_verified_commit_sha"
            exit 0
        fi
        exit 1
        ;;
esac
exit 1
EOF
    chmod +x "$TEST_TEMP_HOME/bin/docker"

    run python3 "$HELPER_PY" --repo-root "$REPO_ROOT" --target-repo "foo/bar" --target-sha "target_sha" --base-url "http://localhost:3000" --backend-ports "8000"
    assert_success
    assert_output --partial '"result": "verified"'
    assert_output --partial '"mode": "docker-exec-git"'
    assert_output --partial '"container": "my-container-backend"'
}

@test "docker mismatch path" {
    # 1. ss/lsof return nothing
    cat <<'EOF' > "$TEST_TEMP_HOME/bin/ss"
#!/bin/sh
exit 0
EOF
    chmod +x "$TEST_TEMP_HOME/bin/ss"

    # 2. Fake docker ps returning container and git check failing
    cat <<'EOF' > "$TEST_TEMP_HOME/bin/docker"
#!/bin/sh
case "$*" in
    *ps*)
        echo "my-mismatch-container 0.0.0.0:8000->8000/tcp"
        exit 0
        ;;
    *inspect*)
        echo '[{"Mounts": [{"Source": "'"$REPO_ROOT"'", "Destination": "/app"}], "Config": {"WorkingDir": "/app"}}]'
        exit 0
        ;;
    *exec*)
        if echo "$*" | grep -q -- "rev-parse --show-toplevel"; then
            echo "/app"
            exit 0
        elif echo "$*" | grep -q -- "merge-base --is-ancestor"; then
            # Ancestor check failed
            exit 1
        elif echo "$*" | grep -q -- "rev-parse HEAD"; then
            echo "old_commit_sha"
            exit 0
        fi
        exit 1
        ;;
esac
exit 1
EOF
    chmod +x "$TEST_TEMP_HOME/bin/docker"

    run python3 "$HELPER_PY" --repo-root "$REPO_ROOT" --target-repo "foo/bar" --target-sha "target_sha" --base-url "http://localhost:3000" --backend-ports "8000"
    assert_success
    assert_output --partial '"result": "mismatch"'
    assert_output --partial '"mode": "docker-exec-git"'
    assert_output --partial '"observed_sha": "old_commit_sha"'
}

@test "docker unsupported/unverified path" {
    # 1. ss/lsof return nothing
    cat <<'EOF' > "$TEST_TEMP_HOME/bin/ss"
#!/bin/sh
exit 0
EOF
    chmod +x "$TEST_TEMP_HOME/bin/ss"

    # 2. Docker unavailable
    cat <<'EOF' > "$TEST_TEMP_HOME/bin/docker"
#!/bin/sh
exit 1
EOF
    chmod +x "$TEST_TEMP_HOME/bin/docker"

    run python3 "$HELPER_PY" --repo-root "$REPO_ROOT" --target-repo "foo/bar" --target-sha "target_sha" --base-url "http://localhost:3000" --backend-ports "8000"
    assert_success
    assert_output --partial '"result": "unverified"'
    assert_output --partial '"reason":'
}
