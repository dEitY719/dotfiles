# ux

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/ux_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic ux --force`

## 호출

- Help 진입점: `ux-help [section|--list|--all]`
- 통합 라우팅: `my-help ux [section]`
- Alias: `ux-help`

## 요약 (ux-help)

- Usage: ux-help [section|--list|--all]
- sections
    - colors: semantic color variables
    - output: ux_header | ux_section | ux_success | ux_error
    - progress: ux_spinner | ux_with_spinner
    - interactive: ux_confirm | ux_input
    - tables: ux_table_header | ux_table_row | ux_bullet
    - utilities: ux_divider | ux_usage | ux_require
    - example: usage example template
    - quickstart: load library and use
    - demo: ux-demo
    - docs: library and demo locations
    - details: ux-help <section>  (example: ux-help colors)

## 섹션

### colors

- **Variable** — Purpose — Color
- **UX_PRIMARY** — Headers, titles, commands — Blue
- **UX_SUCCESS** — Success states, valid input — Green
- **UX_WARNING** — Warnings, confirmations — Yellow
- **UX_ERROR** — Errors, failed operations — Red
- **UX_INFO** — Info messages, tips — Cyan
- **UX_MUTED** — Secondary info, hints — Gray

### output

- **Function** — Purpose
- **ux_header** — Display prominent header with box
- **ux_section** — Display section title with underline
- **ux_success** — Success message with check
- **ux_error** — Error message (to stderr)
- **ux_warning** — Warning message
- **ux_info** — Info message
- **ux_step** — Step indicator with number

### progress

- **Function** — Usage
- **ux_spinner** — ux_spinner <pid> "message"
- **ux_with_spinner** — ux_with_spinner "msg" command args

### interactive

- **Function** — Usage
- **ux_confirm** — if ux_confirm "prompt" "y"; then ...
- **ux_input** — result=$(ux_input "prompt" "pattern")

### tables

- **Function** — Usage
- **ux_table_header** — ux_table_header "Col1" "Col2" ["Col3"]
- **ux_table_row** — ux_table_row "val1" "val2" ["val3"]
- **ux_bullet** — ux_bullet "Item description"
- **ux_numbered** — ux_numbered 1 "First item"

### utilities

- **Function** — Purpose
- **ux_divider** — Print horizontal line (60 chars)
- **ux_usage** — Display usage help template
- **ux_require** — Check if command exists

### example

  #!/bin/bash

  my_function() {
      # Load UX library (unified library at shell-common/tools/ux_lib/)
      source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

      # Show help if no arguments
      if [ -z "$1" ]; then
          ux_header "My Function"
          ux_usage "my-function" "<arg>" "Description"
          return 0
      fi

      # Check requirements
      if ! ux_require "docker"; then
          return 1
      fi

      # Show progress
      ux_info "Processing $1..."
      ux_with_spinner "Running task" some_command "$1"

      # Show result
      if [ $? -eq 0 ]; then
          ux_success "Task completed"
      else
          ux_error "Task failed"
          return 1
      fi
  }

### quickstart

1. Load library: source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
2. Use semantic colors: ${UX_PRIMARY}, ${UX_SUCCESS}, etc.
3. Use helper functions: ux_header, ux_success, etc.
4. Always end with ${UX_RESET} to reset colors

### demo

- Run the interactive demo to see all features in action:
- ux-demo  or  bash ${SHELL_COMMON}/tools/custom/demo_ux.sh

### docs

- Library file: shell-common/tools/ux_lib/ux_lib.sh
- Demo script: shell-common/tools/custom/demo_ux.sh
- Example migrations: my_help(), dcl(), dbash()

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/ux.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/ux_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
