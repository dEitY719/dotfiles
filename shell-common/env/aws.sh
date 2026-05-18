#!/bin/sh
# shell-common/env/aws.sh
# AWS env loader — sources aws/aws.local.sh when present.
#
# This loader itself exports NOTHING. The SSOT for AWS Bedrock shell env is
# aws/aws.local.sh (gitignored, created by aws/setup.sh in internal mode).
# On external/public PCs the .local.sh file is absent and this loader is a
# silent no-op — those PCs continue to talk directly to Anthropic.
#
# Why this lives in shell-common/env/ instead of bash/main.bash + zsh/main.zsh:
# both main loaders already source shell-common/env/*.sh automatically, so
# adding a new file here applies to both shells with zero loader changes
# (SSOT — see issue #677).

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_aws_root="${DOTFILES_ROOT:-$HOME/dotfiles}/aws"
if [ -f "$_aws_root/aws.local.sh" ]; then
    # shellcheck source=/dev/null
    . "$_aws_root/aws.local.sh"
fi
unset _aws_root
