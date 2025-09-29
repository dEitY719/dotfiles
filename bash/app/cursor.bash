#!/bin/bash
# /home/deity719/dotfiles/bash/app/cursor.bash



# 1️⃣ Cursor IDE Linux deb 실행 설정 (👌권장=선호)
# https://cursor.com/download 에서 "linux.deb(x64)" 파일을 다운 받는다.
# cd ~/downloads
# cp_wdown cursor_1.6.45_amd64.deb
# sudo dpkg -i ./cursor_1.6.45_amd64.deb
# sudo apt -f install



# 2️⃣ Cursor IDE Linux AppImage 실행 설정
# 1. 파일 정리 및 권한 부여 (실제 스크립트 실행 시 수동으로 처리해야 함)
# mkdir -p ~/application/cursor
# mv ~/downloads/Cursor-1.6.45-x86_64.AppImage ~/application/cursor/cursor
# chmod +x ~/application/cursor/cursor

# 2. Alias 설정: 'cursor' 명령이 Linux AppImage를 직접 호출하도록 정의
# alias cursor='~/application/cursor/cursor'







# 3️⃣...