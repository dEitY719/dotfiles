#!/usr/bin/env bash
# bash/env/fcitx.bash
# Korean input configuration using fcitx

# Only configure if fcitx is installed
if ! command -v fcitx &>/dev/null; then
    return 0
fi

# Only enable if explicitly requested
if [[ "${ENABLE_FCITX:-false}" != "true" ]]; then
    return 0
fi

# fcitx environment variables
export QT_IM_MODULE=fcitx
export GTK_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export DefaultIMModule=fcitx

# Auto-start fcitx if not running
if ! pgrep -x fcitx >/dev/null; then
    fcitx-autostart &>/dev/null
fi
