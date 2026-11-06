#!/bin/bash
# Idle handling: dim, then suspend (battery) or lock + display off (charger), and
# lock before sleep.
# Lives in a script (not inline in sway/config) because sway splits config
# lines on ';', so an inline `pkill ...; swayidle ...` never starts swayidle
# on first login — only after a reload.

# Both: dim at 3 min. Battery: suspend at 10. Charger: lock + display off at 19.
# Checked when each timeout fires, so it follows whether the charger is connected
# at that moment.
ON_BATTERY='[ "$(cat /sys/class/power_supply/ADP0/online)" = 0 ]'
ON_CHARGER='[ "$(cat /sys/class/power_supply/ADP0/online)" = 1 ]'

pkill -x swayidle
exec swayidle -w \
    timeout 180 'brightnessctl -s set 1%' resume 'brightnessctl -r' \
    timeout 600 "$ON_BATTERY && systemctl suspend" \
    timeout 1140 "$ON_CHARGER && $HOME/.config/sway/scripts/lock.sh" \
    timeout 1142 "$ON_CHARGER && swaymsg 'output * power off'" resume 'swaymsg "output * power on"' \
    before-sleep "$HOME/.config/sway/scripts/lock.sh"
