#!/bin/sh
# shell-common/functions/dirhelp.sh
# dirHelp - shared between bash and zsh

dirhelp() {
    cat <<-'EOF'

[Directory Navigation Commands]

  Basic:
    cd_dot       : cd ~/dotfiles
    cd_down      : cd ~/downloads
    cd_work      : cd ~/workspace

  Windows Directories (WSL):
    cd_wdocu     : Windows Documents
    cd_wobsidian : Windows Obsidian folder
    cd_wdown     : Windows Downloads
    cd_wpicture  : Windows Pictures
    cd_tilnote   : Obsidian TilNote vault
    cd_obsidian  : Obsidian vault

  PARA Method:
    mkpara       : mkdir -p para/{archive,area,project,resource}
    cd_para      : cd ~/para
    cd_project   : cd ~/para/project
    cd_area      : cd ~/para/area
    cd_vault     : cd ~/para/area/vault
    cd_resource  : cd ~/para/resource
    cd_archive   : cd ~/para/archive

  Advanced:
    cp_wdown     : Copy files from Windows Downloads to WSL
                   Usage: cp_wdown [options] <file1> [file2] ...
                   Run 'cp_wdown -h' for detailed help

[Quick Examples]
  # 빠른 이동
  cd_dot              # dotfiles로 이동
  cd_obsidian         # Obsidian vault로 이동

  # Windows 파일 복사
  cp_wdown "*.pdf"    # 모든 PDF 파일 복사
  cp_wdown -r folder  # 폴더 전체 복사

EOF
}
