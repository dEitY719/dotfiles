#!/bin/bash

kill_by_port() {
    if [ -z "$1" ]; then
        echo "사용법: kill_by_port <포트번호>"
        return 1
    fi

    PORT=$1
    PID=$(lsof -t -i :"$PORT")

    if [ -n "$PID" ]; then
        echo "포트 $PORT 를 점유 중인 PID $PID 종료..."
        kill -9 "$PID"
    else
        echo "포트 $PORT 를 점유 중인 프로세스가 없습니다."
    fi
}

# alias 로 간단하게 호출할 수 있게 정의
alias kp=kill_by_port
