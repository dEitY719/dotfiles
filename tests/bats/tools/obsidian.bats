#!/usr/bin/env bats
# tests/bats/tools/obsidian.bats
# Black-box tests for the standalone `obsidian` executable (issue #1023).
# It is a PATH executable (not a shell function), so we invoke the script
# directly with env overrides and assert on output / exit code.
#
# Note: the WSL branch is exercised by forcing WSL_DISTRO_NAME. The native
# Linux (AppImage) branch is not unit-tested via _ob_is_wsl because the test
# host is itself WSL (/proc/version contains "microsoft"), so it cannot be
# forced off without a production test-hook — out of scope. The AppImage
# launch IS covered for the REST-configured case, which reaches it regardless
# of WSL.
#
# The REST backend is exercised through a fake `curl` first on PATH that
# records each request and replays canned responses — no Obsidian instance
# and no network. The assertions are on the real request shape the script
# built (method, URL, headers, body), so the REST code path really runs.

load '../test_helper'

OBSIDIAN_BIN="${DOTFILES_ROOT}/obsidian/bin/obsidian"

setup() {
    # The developer's own ~/.config/obsidian-rest-api/env would otherwise
    # reroute every legacy-path test into the REST backend. Isolate $HOME and
    # clear the env vars so each test states its own backend explicitly.
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    unset OBSIDIAN_REST_API_KEY OBSIDIAN_REST_API_URL

    export OB_STUB_DIR="${BATS_TEST_TMPDIR}/stub"
    mkdir -p "${OB_STUB_DIR}/bin"
}

teardown() {
    [ -n "$TEST_HOME" ] && rm -rf "$TEST_HOME"
}

# A `curl` that records every invocation and replays canned responses.
#   $OB_STUB_DIR/codes    one HTTP status per line, Nth line = Nth request
#   $OB_STUB_DIR/bodyN    response body for the Nth request (optional)
#   $OB_STUB_DIR/reqN     args of the Nth request, one per line (written here)
#   $OB_STUB_DIR/reqbodyN --data-binary @file payload of the Nth request
_install_curl_stub() {
    cat >"${OB_STUB_DIR}/bin/curl" <<'STUB'
#!/bin/sh
d=${OB_STUB_DIR}
n=$(cat "$d/n" 2>/dev/null || echo 0)
n=$((n + 1))
printf '%s' "$n" >"$d/n"
: >"$d/req$n"
out=""
prev=""
for a in "$@"; do
    printf '%s\n' "$a" >>"$d/req$n"
    [ "$prev" = "-o" ] && out=$a
    case "$prev$a" in
    "--data-binary@"*) cp "${a#@}" "$d/reqbody$n" 2>/dev/null ;;
    esac
    prev=$a
done
code=$(sed -n "${n}p" "$d/codes" 2>/dev/null)
[ -n "$code" ] || code=200
if [ -n "$out" ]; then
    if [ -f "$d/body$n" ]; then cat "$d/body$n" >"$out"; else : >"$out"; fi
fi
printf '%s' "$code"
STUB
    chmod +x "${OB_STUB_DIR}/bin/curl"
    printf '%s\n' "$@" >"${OB_STUB_DIR}/codes"
}

# Run the wrapper with the REST backend configured and the curl stub on PATH.
_run_rest() {
    run env \
        OBSIDIAN_REST_API_KEY=testkey \
        OBSIDIAN_REST_API_URL=https://127.0.0.1:27124 \
        OB_STUB_DIR="${OB_STUB_DIR}" \
        PATH="${OB_STUB_DIR}/bin:${PATH}" \
        "$OBSIDIAN_BIN" "$@"
}

# Assert the Nth recorded request carried the exact argument <2>.
_assert_req_arg() {
    grep -Fxq -- "$2" "${OB_STUB_DIR}/req$1" ||
        fail "request $1 has no arg '$2'; got: $(tr '\n' ' ' <"${OB_STUB_DIR}/req$1")"
}

# Assert the Nth recorded request's URL (curl's last arg).
_assert_req_url() {
    local got
    got=$(tail -n1 "${OB_STUB_DIR}/req$1")
    [ "$got" = "$2" ] || fail "request $1 URL: expected '$2', got '$got'"
}

_req_count() {
    cat "${OB_STUB_DIR}/n" 2>/dev/null || echo 0
}

@test "obsidian executable exists and is executable" {
    [ -x "$OBSIDIAN_BIN" ]
}

@test "obsidian passes shellcheck" {
    run shellcheck "$OBSIDIAN_BIN"
    assert_success
}

@test "obsidian -h shows wrapper help (exit 0)" {
    run "$OBSIDIAN_BIN" -h
    assert_success
    assert_output --partial "obsidian - launch Obsidian"
    assert_output --partial "Usage"
}

@test "obsidian --help shows help" {
    run "$OBSIDIAN_BIN" --help
    assert_success
    assert_output --partial "Usage"
}

@test "obsidian help (bare word) shows help" {
    run "$OBSIDIAN_BIN" help
    assert_success
    assert_output --partial "Usage"
}

@test "WSL: missing redirector returns 127 with guidance + path" {
    run env WSL_DISTRO_NAME=Ubuntu OBSIDIAN_CLI_BIN=/no/such/Obsidian.com \
        "$OBSIDIAN_BIN" search query=x
    assert_failure 127
    assert_output --partial "CLI redirector not found"
    assert_output --partial "/no/such/Obsidian.com"
}

@test "WSL: existing-but-non-executable redirector passes the -f gate (not 127)" {
    # DrvFs files can lack +x yet run via interop, so the launcher tests -f not -x.
    local stub="${BATS_TEST_TMPDIR}/Obsidian.com"
    printf '#!/bin/sh\necho RAN "$@"\n' > "$stub"
    chmod 0644 "$stub" # deliberately NOT executable
    run env WSL_DISTRO_NAME=Ubuntu OBSIDIAN_CLI_BIN="$stub" "$OBSIDIAN_BIN" read file=x
    [ "$status" -ne 127 ]
    refute_output --partial "CLI redirector not found"
}

@test "bash runs the POSIX script (help)" {
    run bash "$OBSIDIAN_BIN" -h
    assert_success
    assert_output --partial "Usage"
}

@test "zsh runs the POSIX script (help)" {
    run zsh "$OBSIDIAN_BIN" -h
    assert_success
    assert_output --partial "Usage"
}

# ------------------------------------------------------------- REST: routing

@test "REST not configured: WSL still forwards the subcommand verbatim" {
    local stub="${BATS_TEST_TMPDIR}/Obsidian.com"
    printf '#!/bin/sh\nprintf "RAN %%s\\n" "$*"\n' >"$stub"
    chmod +x "$stub"
    run env WSL_DISTRO_NAME=Ubuntu OBSIDIAN_CLI_BIN="$stub" \
        "$OBSIDIAN_BIN" backlinks file="My Note"
    assert_success
    assert_output "RAN backlinks file=My Note"
}

@test "REST configured: no-args launch uses the AppImage even under WSL" {
    local app="${BATS_TEST_TMPDIR}/Obsidian-9.9.9.AppImage"
    printf '#!/bin/sh\necho APPIMAGE_LAUNCHED\n' >"$app"
    chmod +x "$app"
    run env WSL_DISTRO_NAME=Ubuntu \
        OBSIDIAN_REST_API_KEY=testkey \
        OBSIDIAN_REST_API_URL=https://127.0.0.1:27124 \
        OBSIDIAN_BIN="$app" \
        OBSIDIAN_CLI_BIN=/no/such/Obsidian.com \
        "$OBSIDIAN_BIN"
    assert_success
    assert_output "APPIMAGE_LAUNCHED"
}

@test "REST credentials are read from ~/.config/obsidian-rest-api/env" {
    mkdir -p "${HOME}/.config/obsidian-rest-api"
    cat >"${HOME}/.config/obsidian-rest-api/env" <<'EOF'
OBSIDIAN_REST_API_KEY=filekey
OBSIDIAN_REST_API_URL=https://file.example:1234
EOF
    _install_curl_stub 200
    printf 'from-file\n' >"${OB_STUB_DIR}/body1"
    run env OB_STUB_DIR="${OB_STUB_DIR}" PATH="${OB_STUB_DIR}/bin:${PATH}" \
        "$OBSIDIAN_BIN" read path="note.md"
    assert_success
    _assert_req_url 1 "https://file.example:1234/vault/note.md"
    _assert_req_arg 1 "Authorization: Bearer filekey"
}

@test "REST: exported env wins over the config file" {
    mkdir -p "${HOME}/.config/obsidian-rest-api"
    cat >"${HOME}/.config/obsidian-rest-api/env" <<'EOF'
OBSIDIAN_REST_API_KEY=filekey
OBSIDIAN_REST_API_URL=https://file.example:1234
EOF
    _install_curl_stub 200
    _run_rest read path="note.md"
    assert_success
    _assert_req_url 1 "https://127.0.0.1:27124/vault/note.md"
    _assert_req_arg 1 "Authorization: Bearer testkey"
}

@test "REST: an unreadable config file falls through to legacy WSL routing" {
    mkdir -p "${HOME}/.config/obsidian-rest-api"
    : >"${HOME}/.config/obsidian-rest-api/env" # empty: no key, no url
    run env WSL_DISTRO_NAME=Ubuntu OBSIDIAN_CLI_BIN=/no/such/Obsidian.com \
        "$OBSIDIAN_BIN" search query=x
    assert_failure 127
    assert_output --partial "CLI redirector not found"
}

# ------------------------------------------------------- REST: request shapes

@test "REST read path=: GET /vault/<path>, .md appended, insecure TLS" {
    _install_curl_stub 200
    printf '# Hello\n' >"${OB_STUB_DIR}/body1"
    _run_rest read path="folder/note"
    assert_success
    assert_output "# Hello"
    _assert_req_arg 1 "GET"
    _assert_req_arg 1 "-sk" # self-signed cert accepted
    _assert_req_arg 1 "Authorization: Bearer testkey"
    _assert_req_url 1 "https://127.0.0.1:27124/vault/folder/note.md"
}

@test "REST read with no target reads the active note" {
    _install_curl_stub 200
    printf 'active body\n' >"${OB_STUB_DIR}/body1"
    _run_rest read
    assert_success
    assert_output "active body"
    _assert_req_url 1 "https://127.0.0.1:27124/active/"
}

@test "REST read file=: resolves the wikilink, then GETs the encoded path" {
    _install_curl_stub 200 200
    cat >"${OB_STUB_DIR}/body1" <<'EOF'
[{"filename":"10-Project/My Note.md","result":"10-Project/My Note.md"},
 {"filename":"30-Resource/Other.md","result":"30-Resource/Other.md"}]
EOF
    printf 'resolved body\n' >"${OB_STUB_DIR}/body2"
    _run_rest read file="My Note"
    assert_success
    assert_output "resolved body"
    _assert_req_url 1 "https://127.0.0.1:27124/search/"
    _assert_req_arg 1 "Content-Type: application/vnd.olrapi.jsonlogic+json"
    _assert_req_url 2 "https://127.0.0.1:27124/vault/10-Project/My%20Note.md"
}

@test "REST read file=: unknown name fails loudly (no write, exit 1)" {
    _install_curl_stub 200
    printf '[{"filename":"a/b.md","result":"a/b.md"}]\n' >"${OB_STUB_DIR}/body1"
    _run_rest read file="Nope"
    assert_failure 1
    assert_output --partial 'no note named "Nope"'
}

@test "REST read file=: ambiguous name lists the candidates and refuses" {
    _install_curl_stub 200
    cat >"${OB_STUB_DIR}/body1" <<'EOF'
[{"filename":"a/Dup.md","result":"x"},{"filename":"b/Dup.md","result":"x"}]
EOF
    _run_rest read file="Dup"
    assert_failure 1
    assert_output --partial "ambiguous"
    assert_output --partial "a/Dup.md"
    assert_output --partial "b/Dup.md"
    assert_output --partial 'Use path="..."'
}

@test "REST create: probes for an existing file, then PUTs text/markdown" {
    _install_curl_stub 404 204
    _run_rest create name="New Note" path="folder/New Note.md" \
        content='# Hello\nsecond line' silent
    assert_success
    assert_output "folder/New Note.md"
    # 1: existence probe
    _assert_req_arg 1 "GET"
    _assert_req_url 1 "https://127.0.0.1:27124/vault/folder/New%20Note.md"
    # 2: the write
    _assert_req_arg 2 "PUT"
    _assert_req_arg 2 "Content-Type: text/markdown"
    _assert_req_url 2 "https://127.0.0.1:27124/vault/folder/New%20Note.md"
    # \n in content is an escape, as the native CLI documents it
    printf '# Hello\nsecond line' >"${BATS_TEST_TMPDIR}/expected"
    diff "${BATS_TEST_TMPDIR}/expected" "${OB_STUB_DIR}/reqbody2"
}

@test "REST create: name= only lands at the vault root with .md appended" {
    _install_curl_stub 404 204
    _run_rest create name="Loose" content="x"
    assert_success
    _assert_req_url 2 "https://127.0.0.1:27124/vault/Loose.md"
}

@test "REST create: refuses to clobber an existing note without overwrite" {
    _install_curl_stub 200
    _run_rest create path="folder/note.md" content="x"
    assert_failure 1
    assert_output --partial "already exists"
    assert_output --partial "overwrite"
    [ "$(_req_count)" = "1" ] # probed only; never wrote
}

@test "REST create: the overwrite flag skips the probe and writes" {
    _install_curl_stub 204
    _run_rest create path="folder/note.md" content="x" overwrite
    assert_success
    [ "$(_req_count)" = "1" ]
    _assert_req_arg 1 "PUT"
}

@test "REST search: POSTs /search/simple/ with the url-encoded query" {
    _install_curl_stub 200
    cat >"${OB_STUB_DIR}/body1" <<'EOF'
[{"filename":"a/one.md","matches":[{"context":"hit  one","match":{"start":0,"end":3}}]},
 {"filename":"b/two.md","matches":[{"context":"hit two","match":{"start":0,"end":3}}]},
 {"filename":"c/three.md","matches":[]}]
EOF
    _run_rest search query="search term" limit=2
    assert_success
    _assert_req_arg 1 "POST"
    _assert_req_arg 1 "--data-urlencode"
    _assert_req_arg 1 "query=search term"
    _assert_req_url 1 "https://127.0.0.1:27124/search/simple/"
    assert_line --index 0 "a/one.md"
    assert_line --index 1 "    hit one"
    assert_line --index 2 "b/two.md"
    refute_output --partial "c/three.md" # limit=2 honored
}

@test "REST property:set: PATCHes a frontmatter replace instruction" {
    _install_curl_stub 200
    _run_rest property:set name="status" value="done" path="folder/note.md"
    assert_success
    _assert_req_arg 1 "PATCH"
    _assert_req_arg 1 "Content-Type: application/json"
    _assert_req_url 1 "https://127.0.0.1:27124/vault/folder/note.md"
    run jq -r '[.targetType, .target, .operation, .value,
                (.createTargetIfMissing|tostring)] | join("|")' \
        "${OB_STUB_DIR}/reqbody1"
    assert_output "frontmatter|status|replace|done|true"
}

@test "REST property:set: JSON payload is escaped, never injected" {
    _install_curl_stub 200
    _run_rest property:set name="note" value='he said "hi" \ bye' path="n.md"
    assert_success
    run jq -r '.value' "${OB_STUB_DIR}/reqbody1"
    assert_output 'he said "hi" \ bye'
}

# --------------------------------------------------------- REST: loud refusals

@test "REST: an unsupported subcommand fails loudly without any request" {
    _install_curl_stub 200
    _run_rest backlinks file="My Note"
    assert_failure 2
    assert_output --partial "backlinks"
    assert_output --partial "no REST-backed equivalent"
    assert_output --partial "OBSIDIAN_CLI_BIN"
    [ "$(_req_count)" = "0" ]
}

@test "REST: daily:append is refused, not half-emulated" {
    _install_curl_stub 200
    _run_rest daily:append content="- [ ] task"
    assert_failure 2
    assert_output --partial "daily:append"
    [ "$(_req_count)" = "0" ]
}

@test "REST: vault= targeting is refused" {
    _install_curl_stub 200
    _run_rest vault="My Vault" search query="test"
    assert_failure 2
    assert_output --partial "vault="
    [ "$(_req_count)" = "0" ]
}

@test "REST: an unknown key=value parameter is refused, not dropped" {
    _install_curl_stub 200
    _run_rest create name="N" template="Daily" content="x"
    assert_failure 2
    assert_output --partial "template"
    [ "$(_req_count)" = "0" ]
}

@test "REST: an unreachable API reports the URL, never the key" {
    # Real curl against a closed port: exercises the 000 branch end to end.
    run env OBSIDIAN_REST_API_KEY=supersecretkey \
        OBSIDIAN_REST_API_URL=https://127.0.0.1:1 \
        "$OBSIDIAN_BIN" read path="note.md"
    assert_failure 1
    assert_output --partial "cannot reach the Obsidian REST API"
    assert_output --partial "https://127.0.0.1:1"
    refute_output --partial "supersecretkey"
}

@test "REST: an HTTP error surfaces the API's message" {
    _install_curl_stub 404
    printf '{"message":"Not Found","errorCode":40400}\n' >"${OB_STUB_DIR}/body1"
    _run_rest read path="missing.md"
    assert_failure 1
    assert_output --partial "HTTP 404"
    assert_output --partial "Not Found"
    refute_output --partial "testkey"
}
