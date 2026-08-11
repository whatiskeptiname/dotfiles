#!/usr/bin/env bash
# Continuously-looping waybar custom module: streams cava's raw bar heights
# and renders them as a small rainbow histogram, visible while Playing or
# Paused (matches custom/mpris-now's own condition).

BARS=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
RAINBOW=("#ff2626" "#ffc826" "#92ff26" "#26ff5c" "#26ffff" "#265cff" "#9226ff" "#ff26c8")
playing=0
tick=0

cava -p "$HOME/.config/cava/config" 2>/dev/null | while IFS=';' read -r -a levels; do
    [ "${#levels[@]}" -eq 0 ] && continue

    # Polling playerctl at cava's frame rate would fork way too often —
    # only re-check status once per second (every 30th frame at 30fps).
    if (( tick % 30 == 0 )); then
        st=$(playerctl status 2>/dev/null)
        if [ "$st" = Playing ] || [ "$st" = Paused ]; then
            playing=1
        else
            playing=0
        fi
    fi
    tick=$(( (tick + 1) % 10000 ))

    if [ "$playing" -ne 1 ]; then
        printf '\n'
        continue
    fi

    out=""
    for i in "${!levels[@]}"; do
        lvl=${levels[$i]}
        (( lvl < 0 )) && lvl=0
        (( lvl > 7 )) && lvl=7
        color=${RAINBOW[$(( i % ${#RAINBOW[@]} ))]}
        out+="<span foreground=\"${color}\">${BARS[$lvl]}</span>"
    done
    printf '%s\n' "$out"
done
