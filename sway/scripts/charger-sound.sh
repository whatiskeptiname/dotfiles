#!/bin/bash
# Play a short sound when the charger is plugged in or unplugged.
# Started once per session from sway/config with `exec` (not `exec_always`):
# exec'd processes survive `swaymsg reload`, so this never stacks up watchers.
# The flock also guards against a second copy started by hand.

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/charger-sound.lock"
flock -n 9 || exit 0

ADP=/sys/class/power_supply/ADP0/online
SOUNDS=/usr/share/sounds/freedesktop/stereo

last=$(cat "$ADP")
# power_supply also emits change events for the battery (capacity/status) and
# the USB-C ports, so act only when the adapter's online state actually flips.
udevadm monitor --udev --subsystem-match=power_supply | while read -r _; do
    now=$(cat "$ADP")
    [ "$now" = "$last" ] && continue
    last=$now
    if [ "$now" = 1 ]; then f=power-plug.oga; else f=power-unplug.oga; fi
    pw-play "$SOUNDS/$f" &
done
