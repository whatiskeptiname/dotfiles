#!/bin/bash

lock="Lock"
shutdown="Shutdown"
suspend="Suspend"
hibernate="Hibernate"
reboot="Reboot"
exit_sway="Exit Sway"

chosen=$(printf "%s\n%s\n%s\n%s\n%s\n%s" \
    "$lock" "$shutdown" "$reboot" "$suspend" "$hibernate" "$exit_sway" \
    | rofi -dmenu -p "Power" -i)

case "$chosen" in
    "$lock")     "$HOME/.config/sway/scripts/lock.sh" ;;
    "$shutdown") systemctl poweroff ;;
    "$suspend")  systemctl suspend ;;
    "$hibernate") systemctl hibernate ;;
    "$reboot")   systemctl reboot ;;
    "$exit_sway") swaymsg exit ;;
esac
