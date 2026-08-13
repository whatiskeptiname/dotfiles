#!/bin/bash
# Usage: notify-osd.sh dnd-toggle
# Volume/mic/brightness OSD is handled directly by swayosd-client via the
# XF86 media key bindings in sway/config — this script only toggles DND.

case "$1" in
    dnd-toggle)
        if [ "$(swaync-client -D)" = "false" ]; then
            notify-send -h string:synchronous:dnd "󰂛 Focus Mode" "Notifications muted"
            sleep 1
            swaync-client -dn >/dev/null
        else
            swaync-client -df >/dev/null
            notify-send -h string:synchronous:dnd "󰂚 Focus Mode" "Notifications unmuted"
        fi
        ;;
esac
