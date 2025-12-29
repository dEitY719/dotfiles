#!/bin/bash

kill_by_port() {
    if [ -z "$1" ]; then
        ux_error "사용법: kill_by_port <포트번호>"
        return 1
    fi

    PORT=$1
    PID=$(lsof -t -i :"$PORT")

    if [ -n "$PID" ]; then
        ux_info "포트 $PORT 를 점유 중인 PID $PID 종료..."
        kill -9 "$PID"
    else
        ux_warning "포트 $PORT 를 점유 중인 프로세스가 없습니다."
    fi
}

# alias 로 간단하게 호출할 수 있게 정의
alias kp=kill_by_port

# 포트 확인 함수
check_port() {
    if [ -z "$1" ]; then
        ux_error "사용법: check_port <포트번호>"
        return 1
    fi
    PORT=$1
    ux_info "포트 $PORT 사용 현황:"
    lsof -i :"$PORT" || ux_warning "해당 포트를 사용하는 프로세스가 없습니다."
}

# 짧은 별칭
alias lp='check_port'
