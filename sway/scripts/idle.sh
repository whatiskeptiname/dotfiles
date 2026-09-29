#!/bin/bash
# Idle handling: dim → lock → display off, and lock before sleep.
# Lives in a script (not inline in sway/config) because sway splits config
# lines on ';', so an inline `pkill ...; swayidle ...` never starts swayidle
# on first login — only after a reload.

pkill -x swayidle
exec swayidle -w \
    timeout 180 'brightnessctl -s set 1%'      resume 'brightnessctl -r' \
    timeout 600 "$HOME/.config/sway/scripts/lock.sh" \
    timeout 602 'swaymsg "output * power off"' resume 'swaymsg "output * power on"' \
    before-sleep "$HOME/.config/sway/scripts/lock.sh"
