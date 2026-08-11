#!/usr/bin/env bash
# Continuously-looping waybar custom module: shows a small scrolling
# marquee of the current track, visible while Playing or Paused.

WIDTH=12
SEP="   "
ICON_PLAYING="󰐊"
ICON_PAUSED="󰏤"

status=""
text=""
offset=0
tick=0

while true; do
    # Metadata/status lookups fork playerctl — only refresh once per second,
    # scroll the window every tick for a smooth marquee in between.
    if (( tick % 5 == 0 )); then
        status=$(playerctl status 2>/dev/null)
        text=$(playerctl metadata --format '{{ artist }} - {{ title }}' 2>/dev/null)
    fi
    tick=$(( (tick + 1) % 10000 ))

    if [ "$status" != Playing ] && [ "$status" != Paused ]; then
        printf '\n'
        offset=0
        sleep 0.2
        continue
    fi

    icon="$ICON_PLAYING"
    [ "$status" = Paused ] && icon="$ICON_PAUSED"

    if [ -z "$text" ] || [ "$text" = " - " ]; then
        printf '%s\n' "$icon"
        sleep 0.2
        continue
    fi

    if [ "${#text}" -le "$WIDTH" ]; then
        window="$text"
    else
        loop="${text}${SEP}"
        doubled="${loop}${loop}"
        window="${doubled:offset:WIDTH}"
        offset=$(( (offset + 1) % ${#loop} ))
    fi

    printf '%s %s\n' "$icon" "$window"
    sleep 0.2
done
