#!/bin/sh
# shell-common/aliases/work-aliases.sh
# Work management command aliases (make-jira, make-confluence, work-help)
# Supports both bash and zsh

# Work-help: Show work management commands help
alias work-help='work_help'

# Work-log: CLI tool for logging work activities
alias work-log='bash ~/dotfiles/shell-common/tools/custom/work_log.sh'

# Make-jira: Generate weekly Jira reports from work logs
alias make-jira='bash ~/dotfiles/shell-common/tools/custom/make_jira.sh'

# Make-confluence: Transform markdown docs to Confluence guides
alias make-confluence='bash ~/dotfiles/shell-common/tools/custom/make_confluence.sh'

# SSAI Server Access: Host variables for use with ssh, scp, rsync, etc.
SSAI_DEV='bwyoon@12.81.221.129'
SSAI_OPS='bwyoon@12.81.221.140'

alias ssh-ssai-dev="ssh $SSAI_DEV"
alias ssh-ssai-ops="ssh $SSAI_OPS"
