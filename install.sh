#!/bin/bash
# install.sh: DEPRECATED (#2131) — ./setup.sh alone converges every PC. Exits 2 so old callers fail loudly.
. "$(cd "$(dirname "$0")" && pwd)/shell-common/tools/ux_lib/ux_lib.sh" 2>/dev/null || ux_error() { printf 'Error: %s\n' "$*" >&2; }
ux_error "install.sh 는 폐기됨 — ./setup.sh 를 사용하세요 (#2127)"
exit 2
