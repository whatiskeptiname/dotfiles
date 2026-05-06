#!/usr/bin/env bash
# $1: sink | source   $2: up | down
device="@DEFAULT_${1^^}@"
vol=$(pactl get-${1}-volume "$device" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
case "$2" in
    up)   new=$((vol + 2 > 100 ? 100 : vol + 2)) ;;
    down) new=$((vol - 2 <   0 ?   0 : vol - 2)) ;;
    *) exit 1 ;;
esac
pactl set-${1}-volume "$device" "${new}%"
