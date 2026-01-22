# Git Hook Anti-Patterns (SSOT)

**Purpose**: Hook에서 감지/차단하는 “반복 실수”를 한 곳에 정리하고, 메시지/문서 드리프트를 방지합니다.

## 1) Subshell Sourcing (함수/alias 전파 실패)

### Bad
```sh
output=$(. ./some_file.sh)   # subshell에서 source → 함수/alias가 현재 셸에 남지 않음
```

### Good
```sh
. ./some_file.sh             # 현재 셸에서 source
```

## 2) Alias / Function Name Conflict (zsh 파싱 에러 유발)

### Bad
```sh
alias my-cmd='...'
my_cmd() { ... }  # dash/underscore 변형 포함 동일 이름으로 취급될 수 있음
```

### Good
```sh
alias my-cmd='my_cmd'
my_cmd() { ... }
```

## 3) Wrapper Function Anti-pattern (불필요 래퍼)

### Bad
```sh
foo() { bar "$@"; }
```

### Good
```sh
alias foo='bar'
```

## 4) tools/custom Auto-sourcing (Postmortem 재발)

`shell-common/tools/custom/`는 “실행 전용 유틸” 디렉토리입니다. shell init에서 이 디렉토리를 loop로 source 하면, `demo_ux.sh` 같은 인터랙티브 스크립트가 셸 시작 시 실행되어 hang/무한루프가 발생할 수 있습니다.

### Bad
```sh
for f in "${SHELL_COMMON}/tools/custom/"*.sh; do
  . "$f"
done
```

### Good
```sh
# tools/integrations/만 auto-source
# tools/custom/은 필요할 때 직접 실행: bash "${SHELL_COMMON}/tools/custom/demo_ux.sh"
```

## 5) Library Purity (auto-sourced 경로의 “순수성”)

다음 경로는 shell init에서 자동 로드될 수 있습니다:
- `shell-common/functions/*.sh`
- `shell-common/tools/integrations/*.sh`

따라서 이 경로의 파일은 “source 시 즉시 실행되는 동작”을 포함하면 안 됩니다.

### 금지(대표 예)
- 파일 top-level에서 `main`/`*_main` 호출
- 파일 top-level에서 `read`/`select` 등 사용자 입력 대기
- 파일 top-level에서 패키지 설치(`apt-get install`, `pip install`, `npm install`, `brew install` 등)

### 권장 패턴 (직접 실행 가드)
`tools/custom/*.sh` 처럼 “실행 스크립트”에는 direct-exec guard를 둡니다.

```bash
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
```

## References

- `docs/postmortem/postmortem-auto-sourcing-utility-scripts.md`
