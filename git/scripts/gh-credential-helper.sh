#!/bin/sh
# Portable gh credential helper wrapper.
# git credential helpers run in a minimal environment where PATH may not
# include gh. This script probes common install locations before falling
# back to PATH so both Linux system packages and macOS Homebrew installs
# work without hardcoding a single absolute path in .gitconfig.
for _p in \
    /usr/bin/gh \
    /usr/local/bin/gh \
    /opt/homebrew/bin/gh \
    "$HOME/.local/bin/gh" \
    "$HOME/bin/gh"; do
    [ -x "$_p" ] && exec "$_p" auth git-credential "$@"
done
exec gh auth git-credential "$@"
