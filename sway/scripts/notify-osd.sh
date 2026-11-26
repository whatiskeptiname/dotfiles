#!/bin/bash
# Usage: notify-osd.sh dnd-toggle
# Volume/mic/brightness OSD is handled directly by swayosd-client via the
# XF86 media key bindings in sway/config — this script only toggles DND.

case "$1" in
    dnd-toggle)
        if [ "$(swaync-client -D)" = "false" ]; then
            # DND on first, so the toggle is instant. The popup is critical
            # because swaync still shows those during DND; it ignores the
            # timeout on critical ones, so close it here after a moment.
            swaync-client -dn >/dev/null
            id=$(notify-send -p -u critical -h string:synchronous:dnd "󰂛 Focus Mode" "Notifications muted")
            (sleep 1.5; swaync-client --close "$id" >/dev/null) &
        else
            swaync-client -df >/dev/null
            notify-send -h string:synchronous:dnd "󰂚 Focus Mode" "Notifications unmuted"
        fi
        ;;
esac
