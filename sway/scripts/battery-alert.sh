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
# At SLEEP_AT the laptop suspends by itself (hibernation isn't available
# here: no disk swap). It warns first: a countdown notification for GRACE
# seconds, cancelled by plugging in. If woken while still that low on
# battery, it counts down again. swayidle locks the screen before sleep.
#
# The bar also changes: the battery cell pulses red while it's critical and
# discharging (#battery.critical.discharging in waybar/style.css). Clicking
# it stops the pulse; plugging in re-arms it (waybar/scripts/battery-pulse.sh).
#
# Started once per session from sway/config with `exec` (not `exec_always`):
# exec'd processes survive `swaymsg reload`. The flock also guards against a
# second copy started by hand.

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/battery-alert.lock"
flock -n 9 || exit 0

LEVELS=(20 15 10 7)       # %, highest first
URGENT=10                 # at or below: "plug in now" wording and icon
SLEEP_AT=5                # %: suspend at or below this, after the countdown
GRACE=60                  # seconds of countdown warning before suspending
POLL=30                   # seconds between checks
SUSPEND="systemctl suspend"
SOUND=/usr/share/sounds/freedesktop/stereo/dialog-warning.oga

bat=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
[ -n "$bat" ] || exit 0

ICON_LOW=battery-low-symbolic
ICON_CAUTION=battery-caution-symbolic

alerted=101   # lowest level already alerted for this discharge; 101 = none yet
id=           # swaync id of the current alert, to replace or close it

alert() {  # icon title body: show or replace the alert, with a sound
    id=$(notify-send -p -u critical -a Battery -i "$1" ${id:+-r "$id"} "$2" "$3")
    pw-play "$SOUND" &>/dev/null &
}

discharging() { [ "$(cat "$bat/status" 2>/dev/null)" = Discharging ]; }

# Count down GRACE seconds with a live notification, then suspend. Returns
# early, without suspending, if the charger is plugged in.
countdown_then_sleep() {
    local left=$GRACE
    alert "$ICON_CAUTION" "Battery critical: ${cap}% — sleeping in ${left} s" \
        "Plug in to stay awake. Save your work."
    while (( left > 0 )); do
        sleep 1 9>&-
        discharging || return 0
        left=$((left - 1))
        # Update every 10 s, and each second for the last 5, sound at 10 s.
        if (( left % 10 == 0 || left <= 5 )) && (( left > 0 )); then
            id=$(notify-send -p -u critical -a Battery -i "$ICON_CAUTION" -r "$id" \
                "Battery critical: ${cap}% — sleeping in ${left} s" \
                "Plug in to stay awake. Save your work.")
            (( left == 10 )) && pw-play "$SOUND" &>/dev/null &
        fi
    done
    id=$(notify-send -p -u critical -a Battery -i "$ICON_CAUTION" -r "$id" \
        "Battery critical: sleeping now" "Plug in, then wake the laptop.")
    $SUSPEND
}

while :; do
    cap=$(cat "$bat/capacity" 2>/dev/null)
    status=$(cat "$bat/status" 2>/dev/null)

    if [ "$status" != Discharging ]; then
        # Charging, full or held by the charge limit: reset, clear the alert,
        # and re-arm the bar pulse if it was stopped by a click.
        alerted=101
        if [ -n "$id" ]; then swaync-client --close "$id" >/dev/null 2>&1; id=; fi
        "$HOME/.config/waybar/scripts/battery-pulse.sh" on
    elif [[ "$cap" =~ ^[0-9]+$ ]]; then
        # The lowest level the charge is at or below, if any.
        hit=
        for l in "${LEVELS[@]}"; do (( cap <= l )) && hit=$l; done
        if (( cap <= SLEEP_AT )); then
            countdown_then_sleep
        elif [ -n "$hit" ] && (( hit < alerted )); then
            alerted=$hit
            if (( cap <= URGENT )); then
                alert "$ICON_CAUTION" "Battery low: ${cap}%" \
                    "Plug in now. The laptop will go to sleep at ${SLEEP_AT}%."
            else
                alert "$ICON_LOW" "Battery low: ${cap}%" "Plug in soon."
            fi
        fi
    fi
    sleep "$POLL" 9>&-   # don't hand the lock to sleep: it would outlive a kill
done
