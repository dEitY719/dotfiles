# shell-common/aliases/mytool.sh
# MyTool aliases (POSIX-compatible)
# Shared between bash and zsh

# MyTool 도움말 별칭
alias mthelp='mytool_help'

# 소스 번들링 짧은 별칭
alias sp='srcpack --ext .py --max-bytes 33000'

# 하드웨어 정보 별칭
alias hwinfo='get_hw_info'

# AGENTS.md 생성 짧은 별칭 (changed from 'ai' to avoid conflict with apt install)
alias aa='agents_init'
