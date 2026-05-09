#!/bin/sh
# shell-common/functions/parse_yaml_defaults.sh
# POSIX-compatible mini-parser for `.gh-issue-defaults.yml` consumed by
# claude/skills/gh-issue-create Step 2.5. Avoids a hard `yq` dependency
# so the skill works on any host with awk + sh. Recognises only the
# narrow schema documented in claude/skills/gh-issue-create/references/
# auto-labels.md ("Schema (recognised keys)" section) — anything richer
# should reach for a real YAML parser instead.
#
# Public helpers (all read from $1, write newline-separated labels or a
# single milestone string to stdout, return 0 even when no match):
#
#   _parse_yaml_defaults_static <yml>
#   _parse_yaml_defaults_by_prefix <yml> <prefix>
#   _parse_yaml_defaults_milestone <yml>
#
# Each helper exits 1 only on missing-file / empty-file argument errors.

# Static labels under `default_labels.static: [a, b]` or block-list form.
_parse_yaml_defaults_static() {
    _yml="$1"
    [ -n "$_yml" ] && [ -r "$_yml" ] || return 1
    awk '
        BEGIN { in_dl = 0; in_static = 0 }
        /^[[:space:]]*#/ { next }
        /^default_labels:[[:space:]]*$/ { in_dl = 1; next }
        in_dl && /^[^[:space:]]/ { in_dl = 0; in_static = 0 }
        in_dl && /^[[:space:]]+static:[[:space:]]*\[/ {
            line = $0
            sub(/^[^\[]*\[/, "", line)
            sub(/\].*/, "", line)
            n = split(line, a, ",")
            for (i = 1; i <= n; i++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i])
                gsub(/^["'\'']|["'\'']$/, "", a[i])
                if (a[i] != "") print a[i]
            }
            next
        }
        in_dl && /^[[:space:]]+static:[[:space:]]*$/ { in_static = 1; next }
        in_static && /^[[:space:]]+-[[:space:]]+/ {
            v = $0
            sub(/^[[:space:]]+-[[:space:]]+/, "", v)
            gsub(/^["'\'']|["'\'']$/, "", v)
            print v
            next
        }
        in_static && /^[[:space:]]+[A-Za-z_]/ { in_static = 0 }
    ' "$_yml"
}

# Labels mapped from a conventional-commit title prefix.
_parse_yaml_defaults_by_prefix() {
    _yml="$1"
    _prefix="$2"
    [ -n "$_yml" ] && [ -r "$_yml" ] || return 1
    [ -n "$_prefix" ] || return 1
    awk -v want="$_prefix" '
        BEGIN { in_dl = 0; in_btp = 0 }
        /^[[:space:]]*#/ { next }
        /^default_labels:[[:space:]]*$/ { in_dl = 1; next }
        in_dl && /^[^[:space:]]/ { in_dl = 0; in_btp = 0 }
        in_dl && /^[[:space:]]+by_title_prefix:[[:space:]]*$/ { in_btp = 1; next }
        in_btp && /^[[:space:]]+[A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*\[/ {
            key = $0
            sub(/^[[:space:]]+/, "", key)
            sub(/:.*/, "", key)
            if (key != want) next
            line = $0
            sub(/^[^\[]*\[/, "", line)
            sub(/\].*/, "", line)
            n = split(line, a, ",")
            for (i = 1; i <= n; i++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i])
                gsub(/^["'\'']|["'\'']$/, "", a[i])
                if (a[i] != "") print a[i]
            }
            next
        }
        in_btp && /^[^[:space:]]/ { in_btp = 0 }
    ' "$_yml"
}

# Milestone field — emits the literal value or nothing.
_parse_yaml_defaults_milestone() {
    _yml="$1"
    [ -n "$_yml" ] && [ -r "$_yml" ] || return 1
    awk '
        /^[[:space:]]*#/ { next }
        /^milestone:[[:space:]]*/ {
            v = $0
            sub(/^milestone:[[:space:]]*/, "", v)
            sub(/[[:space:]]*#.*$/, "", v)
            sub(/[[:space:]]+$/, "", v)
            gsub(/^["'\'']|["'\'']$/, "", v)
            print v
            exit
        }
    ' "$_yml"
}
