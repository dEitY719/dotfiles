# path.bash
# PATH 관련 환경 변수 설정

# 로컬 바이너리 경로 추가
export PATH="$HOME/.local/bin:$PATH"

# 개발 도구 경로 추가
export PATH="/usr/local/go/bin:$PATH"     # Go

# 사용자 정의 스크립트 경로
export PATH="$DOTFILES_BASH_DIR/scripts:$PATH"

# 환경 변수 파일 로드
safe_source "$HOME/.local/bin/env" ".local/bin/env file not found"


# PATH 변수 중복 제거 함수
# PathCleaner.clean_path()
clean_path() {
  local newpath
  local path_entry
  local seen

  # PATH 변수를 콜론(:)으로 분리하여 각 경로를 순회
  IFS=':' read -ra path_entries <<< "$PATH"
  declare -A seen

  for path_entry in "${path_entries[@]}"; do
    # 이미 확인한 경로인지 체크
    if [[ ! "${seen[$path_entry]}" ]]; then
      # 새로운 경로에 추가하고 'seen'에 기록
      newpath="${newpath}${newpath:+:}${path_entry}"
      seen["$path_entry"]=1
    fi
  done

  # 정리된 경로를 PATH 변수에 다시 할당
  export PATH="$newpath"
}
