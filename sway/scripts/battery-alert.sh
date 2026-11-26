#!/bin/bash
# Low-battery alerts. Nothing else in this setup sends one (upower doesn't
# notify by itself).
#
# While discharging, warns at each of LEVELS as the charge falls past it, so
# you get repeated, more urgent reminders instead of a single one. Each alert
# replaces the previous one instead of stacking. Alerts are sent with
# critical urgency because that's what swaync still shows during Do Not
# Disturb (normal ones are held back). swaync keeps critical notifications
# until dismissed (it ignores their timeout); plugging in clears the alert.
#
# The bar also changes: the battery cell blinks red while it's critical and
# discharging (#battery.critical.discharging in waybar/style.css).
#
# Started once per session from sway/config with `exec` (not `exec_always`):
# exec'd processes survive `swaymsg reload`. The flock also guards against a
# second copy started by hand.

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/battery-alert.lock"
flock -n 9 || exit 0

LEVELS=(20 15 10 7 5 3)   # %, highest first
URGENT=10                 # at or below: "plug in now" wording and icon
POLL=30                   # seconds between checks
SOUND=/usr/share/sounds/freedesktop/stereo/dialog-warning.oga

bat=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
[ -n "$bat" ] || exit 0

ICON_LOW=battery-low-symbolic
ICON_CAUTION=battery-caution-symbolic

alerted=101   # lowest level already alerted for this discharge; 101 = none yet
id=           # swaync id of the current alert, to replace or close it

while :; do
    cap=$(cat "$bat/capacity" 2>/dev/null)
    status=$(cat "$bat/status" 2>/dev/null)

    if [ "$status" != Discharging ]; then
        # Charging, full or held by the charge limit: reset, clear the alert.
        alerted=101
        if [ -n "$id" ]; then swaync-client --close "$id" >/dev/null 2>&1; id=; fi
    elif [[ "$cap" =~ ^[0-9]+$ ]]; then
        # The lowest level the charge is at or below, if any.
        hit=
        for l in "${LEVELS[@]}"; do (( cap <= l )) && hit=$l; done
        if [ -n "$hit" ] && (( hit < alerted )); then
            alerted=$hit
            if (( cap <= URGENT )); then
                icon=$ICON_CAUTION
                body="Plug in now. The laptop will shut down when it runs out."
            else
                icon=$ICON_LOW
                body="Plug in soon."
            fi
            id=$(notify-send -p -u critical -a Battery -i "$icon" \
                ${id:+-r "$id"} "Battery low: ${cap}%" "$body")
            pw-play "$SOUND" &>/dev/null &
        fi
    fi
    sleep "$POLL" 9>&-   # don't hand the lock to sleep: it would outlive a kill
done
