#!/bin/bash
pgrep -x swaylock > /dev/null && exit 0   # no-op if timeout and before-sleep both fire
WALLPAPER=$(cat "$HOME/.cache/current-wallpaper" 2>/dev/null)

# Same palette as burn-in — red reserved for wrong-password state
COLOR_POOL=(
    "7aa2f7" "9ece6a" "e0af68" "bb9af7"
    "7dcfff" "ff9e64" "2ac3de" "41a6b5"
    "73daca" "c3e88d" "89ddff" "b4f9f8"
)
TOTAL=${#COLOR_POOL[@]}

# Two distinct random colors via /dev/urandom (more reliable than $RANDOM)
read -r RING_IDX KEY_IDX < <(shuf -i 0-$((TOTAL-1)) -n2 | tr '\n' ' ')
RING_COLOR=${COLOR_POOL[$RING_IDX]}
KEY_COLOR=${COLOR_POOL[$KEY_IDX]}

# Random indicator position — safe bounds across both outputs
IND_X=$(shuf -i 360-1560 -n1)
IND_Y=$(shuf -i 240-640 -n1)

if [[ -f "$WALLPAPER" ]]; then
    IMG_ARGS=(--image "$WALLPAPER" --scaling fill)
else
    IMG_ARGS=(--color 08080b)
fi

swaylock -f \
    "${IMG_ARGS[@]}" \
    --indicator-idle-visible \
    --show-failed-attempts \
    --indicator-x-position "$IND_X" \
    --indicator-y-position "$IND_Y" \
    --font "CaskaydiaCove Nerd Font Propo" \
    --indicator-radius 150 \
    --indicator-thickness 15 \
    --inside-color 08080bcc \
    --inside-clear-color 08080bcc \
    --inside-ver-color 08080bcc \
    --inside-wrong-color 3b0000cc \
    --ring-color "${RING_COLOR}ff" \
    --ring-clear-color "${RING_COLOR}ff" \
    --ring-ver-color e0af68ff \
    --ring-wrong-color f7768eff \
    --key-hl-color "${KEY_COLOR}ff" \
    --bs-hl-color f7768eff \
    --text-color acb0d0ff \
    --text-clear-color acb0d0ff \
    --text-ver-color e0af68ff \
    --text-wrong-color f7768eff \
    --line-color 00000000 \
    --line-clear-color 00000000 \
    --separator-color 00000000
