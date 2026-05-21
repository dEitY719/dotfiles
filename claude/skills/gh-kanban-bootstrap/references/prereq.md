# Prereq Check — F-2 Procedure

## Tools

```sh
command -v gh >/dev/null 2>&1 || {
    printf 'gh CLI not found — install from https://cli.github.com\n' >&2
    return 1
}
command -v jq >/dev/null 2>&1 || {
    printf 'jq not found — apt/brew install jq\n' >&2
    return 1
}
```

## Host detection

```sh
_kanban_host() {
    local _u
    _u=$(git remote get-url origin 2>/dev/null) || return 1
    case "$_u" in
        git@*) printf '%s' "${_u#git@}" | cut -d: -f1 ;;
        https://*) printf '%s' "${_u#https://}" | cut -d/ -f1 ;;
        ssh://*) printf '%s' "${_u#ssh://}" | cut -d/ -f1 | cut -d@ -f2 ;;
        *) return 1 ;;
    esac
}
```

## Token scope check

```sh
HOST=$(_kanban_host) || {
    printf 'not in a git repository (or origin is unparseable)\n' >&2
    return 1
}

scopes=$(gh api -h "$HOST" -i user 2>/dev/null \
    | awk 'tolower($1) == "x-oauth-scopes:" { sub(/^[^:]*:[ \t]*/, ""); print; exit }')

case ",${scopes// /}," in
    *,project,*|*,read:project,*) : ;;
    *)
        printf 'token missing project scope — run: gh auth refresh -h %s -s project\n' "$HOST" >&2
        return 1
        ;;
esac
```

## rc matrix

| condition | rc | message |
|-----------|----|---------|
| gh missing | 1 | `gh CLI not found — install from https://cli.github.com` |
| jq missing | 1 | `jq not found — apt/brew install jq` |
| not in git | 1 | `not in a git repository (or origin is unparseable)` |
| project scope missing | 1 | `token missing project scope — run: gh auth refresh -h <host> -s project` |
| all good | 0 | (silent) |

Step 5 (label bootstrap) reuses the result of this check — `repo`
scope is implied by `project` scope, so no extra check.
