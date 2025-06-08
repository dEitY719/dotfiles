# path.bash
# PATH 관련 환경 변수 설정

# 로컬 바이너리 경로 추가
export PATH="$HOME/.local/bin:$PATH"

# 개발 도구 경로 추가
export PATH="/usr/local/go/bin:$PATH"     # Go
export PATH="$HOME/.cargo/bin:$PATH"      # Rust
export PATH="$HOME/.npm-global/bin:$PATH" # npm global

# 사용자 정의 스크립트 경로
export PATH="$DOTFILES_BASH_DIR/scripts:$PATH"

# 환경 변수 파일 로드
safe_source "$HOME/.local/bin/env" ".local/bin/env file not found"
