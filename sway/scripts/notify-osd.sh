#!/bin/bash
# Usage: notify-osd.sh volume-up|volume-down|mute|mic-mute|brightness-up|brightness-down

case "$1" in
    volume-up)
        wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+
        VOL=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "%d", $2*100}')
        notify-send -h string:synchronous:volume -h int:value:"$VOL" "󰕾 Volume" "$VOL%"
        ;;
    volume-down)
        wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
        VOL=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "%d", $2*100}')
        notify-send -h string:synchronous:volume -h int:value:"$VOL" "󰕾 Volume" "$VOL%"
        ;;
    mute)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        if wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED; then
            notify-send -h string:synchronous:volume -h int:value:0 "󰝟 Volume" "Muted"
        else
            VOL=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "%d", $2*100}')
            notify-send -h string:synchronous:volume -h int:value:"$VOL" "󰕾 Volume" "Unmuted"
        fi
        ;;
    mic-mute)
        wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
        if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED; then
            notify-send -h string:synchronous:mic "󰍭 Mic" "Muted"
        else
            notify-send -h string:synchronous:mic "󰍬 Mic" "Unmuted"
        fi
        ;;
    brightness-up)
        brightnessctl set 5%+
        BRI=$(brightnessctl -m | awk -F, '{gsub(/%/,"",$4); print $4}')
        notify-send -h string:synchronous:brightness -h int:value:"$BRI" "󰃠 Brightness" "$BRI%"
        ;;
    brightness-down)
        brightnessctl set 5%-
        BRI=$(brightnessctl -m | awk -F, '{gsub(/%/,"",$4); print $4}')
        notify-send -h string:synchronous:brightness -h int:value:"$BRI" "󰃞 Brightness" "$BRI%"
        ;;
esac
