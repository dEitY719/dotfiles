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

# SSAI Server Access: Quick SSH aliases for internal environments
alias ssai-dev-server='ssh bwyoon@12.81.221.129'
alias ssai-ops-server='ssh bwyoon@12.81.221.140'
