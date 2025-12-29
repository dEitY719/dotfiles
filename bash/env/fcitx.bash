#!/usr/bin/env bash
# bash/env/fcitx.bash
# Korean input configuration using fcitx

# Only configure if fcitx is installed and explicitly enabled
if command -v fcitx &>/dev/null && [[ "${ENABLE_FCITX:-false}" = "true" ]]; then
    # fcitx environment variables
    export QT_IM_MODULE=fcitx
    export GTK_IM_MODULE=fcitx
    export XMODIFIERS=@im=fcitx
    export DefaultIMModule=fcitx

    # Auto-start fcitx if not running
    if ! pgrep -x fcitx >/dev/null 2>&1; then
        fcitx-autostart &>/dev/null &
    fi
fi
