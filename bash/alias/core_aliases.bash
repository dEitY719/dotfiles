# core_aliases.bash
# 기본 명령어에 대한 alias 정의

# 환경 변수 리로드
alias reload='exec bash'
alias src='source ~/.bashrc'
alias rs='reload'
alias sb='src'

# 파일 시스템 탐색
alias ll='ls -alF'   # 상세 파일 정보 표시
alias la='ls -A'     # 숨김 파일 포함 표시
alias l='ls -CF'     # 간단한 파일 목록
alias ..='cd ..'     # 상위 디렉토리로 이동
alias ...='cd ../..' # 상위 상위 디렉토리로 이동
alias ~='cd ~'       # 홈 디렉토리로 이동
alias cls='clear'    # 화면 지우기

# 파일 조작
alias cp='cp -i'       # 복사 시 덮어쓰기 확인
alias mv='mv -i'       # 이동 시 덮어쓰기 확인
alias rm='rm -i'       # 삭제 시 확인
alias mkdir='mkdir -p' # 중첩 디렉토리 생성 가능

# 텍스트 처리
alias grep='grep --color=auto'   # 검색 결과 색상 표시
alias egrep='egrep --color=auto' # 확장 검색 결과 색상 표시
alias fgrep='fgrep --color=auto' # 고정 문자열 검색 결과 색상 표시

# 디렉토리 탐색
alias dirs='dirs -v'      # 디렉토리 스택 번호 표시
alias h='history'         # 명령어 히스토리
alias hg='history | grep' # 히스토리에서 검색

# 시스템 정보
alias df='df -h'     # 디스크 사용량을 사람이 읽기 쉬운 형태로
alias du='du -h'     # 디렉토리 크기를 사람이 읽기 쉬운 형태로
alias free='free -h' # 메모리 사용량을 사람이 읽기 쉬운 형태로
