#!/bin/sh
# shell-common/env/fcitx.sh
# Fcitx input method environment and optional autostart for Korean input

# Opt-in: set ENABLE_FCITX=true to enable configuration
if command -v fcitx >/dev/null 2>&1 && [ "${ENABLE_FCITX:-false}" = "true" ]; then
    export QT_IM_MODULE=fcitx
    export GTK_IM_MODULE=fcitx
    export XMODIFIERS=@im=fcitx
    export DefaultIMModule=fcitx

    # Start fcitx only when a display session exists and it's not already running
    if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        if command -v fcitx-autostart >/dev/null 2>&1 && ! pgrep -x fcitx >/dev/null 2>&1; then
            fcitx-autostart >/dev/null 2>&1 &
        fi
    fi
fi
