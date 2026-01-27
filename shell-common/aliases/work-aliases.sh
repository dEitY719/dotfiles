#!/bin/sh
# shell-common/aliases/work-aliases.sh
# Work management command aliases (make-jira, make-confluence)
# Supports both bash and zsh

# Make-jira: Generate weekly Jira reports from work logs
alias make-jira='bash ~/dotfiles/shell-common/tools/custom/make_jira.sh'

# Make-confluence: Transform markdown docs to Confluence guides
alias make-confluence='bash ~/dotfiles/shell-common/tools/custom/make_confluence.sh'
