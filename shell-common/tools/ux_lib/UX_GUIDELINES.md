# Dotfiles UX Guidelines

## Design Principles

1.  **Consistency**: All functions use the same color scheme and formatting.
2.  **Discoverability**: Help text is always available with no arguments, and `my-help` lists all available help topics.
3.  **Safety**: Destructive operations require explicit confirmation.
4.  **Feedback**: Operations provide clear success/error/warning messages and progress indicators.
5.  **Readability**: Output is well-structured, easy to read, and uses semantic colors effectively.

## Color Semantics

-   **Primary (Blue)**: Headers, section titles, command names.
-   **Success (Green)**: Successful operations, valid states, positive feedback.
-   **Warning (Yellow)**: Warnings, confirmations needed, potentially risky actions.
-   **Error (Red)**: Errors, failed operations, critical issues.
-   **Info (Cyan)**: Informational messages, tips, general guidance.
-   **Muted (Gray)**: Secondary information, hints, dividers, less important details.

## Function Structure Template

```bash
my_function() {
    # 1. Load UX library (if not already sourced globally in main.bash/main.zsh)
    #    If using in a standalone script, source relative to the script:
    #    source "$(dirname "$0")/../../tools/ux_lib/ux_lib.sh"

    # 2. Show help if no arguments
    if [ -z "$1" ]; then
        ux_header "Function Name"
        ux_usage "my_function" "<arg>" "Description"
        return 0
    fi
```

(Skipping unchanged parts...)

## File Locations

-   **Central UX Library**: `shell-common/tools/ux_lib/ux_lib.sh`
-   **Python Menu Script**: `shell-common/tools/ux_lib/ux_menu.py` (Internal dependency)
-   **Python Progress Script**: `shell-common/tools/ux_lib/ux_progress.py` (Internal dependency)
-   **UX Demo Script**: `shell-common/tools/custom/demo_ux.sh`
-   **UX Consistency Checker**: `shell-common/tools/custom/check_ux_consistency.sh`

## Portability (Using in Other Projects)

This UX library is designed to be self-contained. To use it in another project:

1.  Copy the entire `ux_lib` directory to your project (e.g., `lib/ux_lib`).
2.  Source the `ux_lib.bash` file in your scripts.

```bash
# Example: Sourcing from a script in the project root
source "./shell-common/tools/ux_lib/ux_lib.sh"
```

The library automatically handles the paths for its internal Python dependencies (`ux_menu.py`, `ux_progress.py`) via the `UX_LIB_DIR` variable.

## Testing and Validation

*   Use `mytool/demo_ux.sh` to interactively test UX features.
*   Run `mytool/check_ux_consistency.sh` to ensure adherence to guidelines.

## Table Formatting

`ux_table_row` 의 첫 컬럼(라벨)은 20칸으로 정렬된다.

*   줄일 수 있는 라벨은 20칸(표시 폭) 이하로 유지한다.
*   정확한 명령 구문처럼 줄일 수 없는 라벨(예: `claude mcp remove <name>`)은 그대로 넘긴다. 표시 폭이 20칸을 넘으면 `ux_table_row` 가 라벨을 한 줄에 먼저 출력하고 설명을 다음 줄로 넘겨 구분자 정렬을 유지한다.
*   따라서 호출부에서 긴 라벨을 따로 처리할 필요가 없다. 라벨 길이를 강제하는 lint 는 두지 않는다 (#1501).

## Best Practices

*   **Never hardcode colors**: Always use `UX_PRIMARY`, `UX_SUCCESS`, etc.
*   **Use semantic functions**: Prefer `ux_success` over `echo "${UX_SUCCESS}..."`.
*   **Provide clear feedback**: Inform the user about the state of operations.
*   **Keep it clean**: Remove commented-out `tput` definitions after migration.
*   **Error gracefully**: Use `ux_error` for failures and consider `ux_enable_error_trap`.
