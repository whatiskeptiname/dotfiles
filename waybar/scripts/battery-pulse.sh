#!/usr/bin/env bash
# battery-pulse.sh off|on — stop or re-arm the low-battery pulse on the
# waybar battery cell (#battery.critical.discharging in style.css).
#
#   off  run by clicking the battery cell: the cell stays red but stops
#        pulsing, until the charger is next plugged in. That click also
#        toggled the time display; the bar reload below undoes it, so the
#        click only stops the pulse. Later clicks toggle the time as usual
#        (this exits early once there's nothing left to stop).
#   on   run by battery-alert.sh when the charger is plugged in
#
# Waybar can't change a module's CSS per click, so this edits the live
# stylesheet burn-in.sh generated; "reload_style_on_change" in config.jsonc
# makes waybar restyle at once, without restarting modules. A sway reload
# regenerates the stylesheet from style.css, which re-arms it too.

css=/tmp/waybar-runtime.css   # written by sway/scripts/burn-in.sh
[ -f "$css" ] || exit 0

case "$1" in
    off) from='animation-name: battery-low;' to='animation-name: none; /* snoozed */' ;;
    on)  from='animation-name: none; /* snoozed */' to='animation-name: battery-low;' ;;
    *)   echo "usage: $0 off|on" >&2; exit 1 ;;
esac

# Only write when something changes: every write makes waybar restyle.
grep -qF "$from" "$css" || exit 0
content=$(<"$css")
printf '%s\n' "${content//"$from"/"$to"}" > "$css"   # literal replace; same inode

# Reloading resets the battery cell's time toggle (and re-reads the
# stylesheet just written). Clean: waybar restarts its own module scripts.
[ "$1" = off ] && pkill -USR2 -x waybar
