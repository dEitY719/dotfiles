#!/bin/sh
# lint_setup_steps.sh — root setup.sh 스텝 목록 드리프트 검사 (issue #2142)
#
# 정책 (docs/.ssot/one-click-setup.md "출력 규약"):
#   - git 이 추적하는 1단계 모듈 setup.sh(`<module>/setup.sh`, root 제외)는
#     root `setup.sh` 의 main() 에 `./<module>/setup.sh` 로 등록되거나,
#     `<module>/.setup-optin`(등록하지 않는 사유 1줄)을 가져야 한다.
#   - 둘 다 없으면 FAIL(조용히 빠진 모듈), 둘 다 있으면 FAIL(모순).
#   - 스텝 자동 발견이 아니라 명시 목록 + 이 lint 다 — 순서가 의미를 가진다(#2127).
#
# 사용 (현재 git 저장소 root 기준):
#   sh scripts/lint_setup_steps.sh

set -eu

cd "$(git rev-parse --show-toplevel)"
git() { command git -c core.quotepath=false "$@"; }

# main() 본문에서 주석 줄·줄 끝 주석을 뺀 것 — 주석 속 `./x/setup.sh` 언급은 등록이 아니다.
steps="$(awk '/^main\(\) *\{/ { in_main = 1; next }
    in_main && /^\}/ { exit }
    in_main && !/^[[:space:]]*#/ { sub(/[[:space:]]+#.*/, ""); print }' setup.sh)"
if [ -z "$steps" ]; then
    echo "FAIL  setup.sh — main() 을 찾지 못했습니다." >&2
    exit 1
fi

errors=0
checked=0

while IFS= read -r file; do
    case "$file" in */*/*) continue ;; esac # 1단계 모듈만
    [ -f "$file" ] || continue
    module="${file%/setup.sh}"
    checked=$((checked + 1))
    registered=0
    case "$steps" in *"./${module}/setup.sh"*) registered=1 ;; esac
    optin=0
    [ -f "${module}/.setup-optin" ] && optin=1
    if [ "$registered" = 1 ] && [ "$optin" = 1 ]; then
        echo "FAIL  ${module} — setup.sh main() 에 등록돼 있는데 ${module}/.setup-optin 도 있습니다(모순)." >&2
        errors=$((errors + 1))
    elif [ "$registered" = 0 ] && [ "$optin" = 0 ]; then
        echo "FAIL  ${module} — setup.sh main() 에 없고 ${module}/.setup-optin(사유 1줄)도 없습니다." >&2
        errors=$((errors + 1))
    elif [ "$optin" = 1 ]; then
        echo "info  ${module} — opt-in: $(head -n 1 "${module}/.setup-optin")"
    fi
done <<EOF
$(git ls-files '*/setup.sh')
EOF

echo "lint-setup-steps: checked=${checked} errors=${errors}"

[ "$errors" -eq 0 ] || exit 1
