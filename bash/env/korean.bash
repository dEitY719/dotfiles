# locale.bash

export QT_IM_MODULE=fcitx
export GTK_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export DefaultIMModule=fcitx
# fcitx가 아직 실행되지 않았다면 시작 (선택 사항이지만 권장)
if ! pgrep -x fcitx >/dev/null; then
    fcitx-autostart &>/dev/null
fi