#!/bin/sh
# locale.bash
# 로케일 및 언어 설정

# 기본 언어 설정
export LANG=en_US.UTF-8
# export LANG=ko_KR.UTF-8
# export LANGUAGE=ko_KR:ko
# export LC_ALL=ko_KR.UTF-8

# UTF-8 인코딩 명시 (특히 OpenCode TUI 호환성)
export LC_ALL=en_US.UTF-8

# 터미널 호환성 설정 (OpenCode TUI, 색상 지원, WSL2)
export TERM=xterm-256color

# 시간대 설정
export TZ='Asia/Seoul'
