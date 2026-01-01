# path.bash
# PATH 관련 환경 변수 설정

# 로컬 바이너리 경로 추가
export PATH="$HOME/.local/bin:$PATH"

# 개발 도구 경로 추가
export PATH="/usr/local/go/bin:$PATH" # Go

# 사용자 정의 스크립트 경로
export PATH="$DOTFILES_BASH_DIR/scripts:$PATH"

# PATH 변수 중복 제거 함수
# PathCleaner.clean_paths()
clean_paths() {
    local newpath=""
    local path_entry

    # Shell-specific array handling
    if [ -n "$BASH_VERSION" ]; then
        # Bash implementation
        local -a path_entries
        local -A seen=()

        # PATH 문자열을 배열로 분리
        IFS=':' read -r -a path_entries <<<"$PATH"

        for path_entry in "${path_entries[@]}"; do
            # 끝 슬래시 정규화
            path_entry="${path_entry%/}"

            # 빈 항목 또는 디렉토리 없는 경로 건너뜀
            [[ -n "$path_entry" ]] || continue
            [[ -d "$path_entry" ]] || continue

            # 중복 방지: set -u에서도 안전
            if [[ ! -v "seen[$path_entry]" ]]; then
                seen["$path_entry"]=1
                newpath+="${newpath:+:}${path_entry}"
            fi
        done

    elif [ -n "$ZSH_VERSION" ]; then
        # Zsh implementation
        typeset -A seen=()
        local -a path_entries

        # PATH 문자열을 배열로 분리 (zsh 문법)
        path_entries=("${(@s/:/)PATH}")

        for path_entry in "${path_entries[@]}"; do
            # 끝 슬래시 정규화
            path_entry="${path_entry%/}"

            # 빈 항목 또는 디렉토리 없는 경로 건너뜀
            [[ -n "$path_entry" ]] || continue
            [[ -d "$path_entry" ]] || continue

            # 중복 방지
            if [[ ! -v "seen[$path_entry]" ]]; then
                seen[$path_entry]=1
                newpath+="${newpath:+:}${path_entry}"
            fi
        done

    else
        # POSIX fallback (slower but compatible)
        local seen_paths=""

        # Save IFS and split PATH manually
        local OLD_IFS="$IFS"
        IFS=':'
        set -- $PATH
        IFS="$OLD_IFS"

        for path_entry in "$@"; do
            # 끝 슬래시 정규화
            path_entry="${path_entry%/}"

            # 빈 항목 또는 디렉토리 없는 경로 건너뜀
            [ -n "$path_entry" ] || continue
            [ -d "$path_entry" ] || continue

            # 중복 확인 (POSIX 방식)
            case ":$seen_paths:" in
                *":$path_entry:"*) continue ;;
            esac

            seen_paths="${seen_paths}:${path_entry}"
            newpath="${newpath}${newpath:+:}${path_entry}"
        done
    fi

    # 정리된 PATH를 다시 적용
    export PATH="$newpath"
}
