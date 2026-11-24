#!/usr/bin/env bash
# Pomodoro timer that doubles as the bar's clock (custom/pomodoro).
#
#   idle     shows the clock; left-click toggles the long date (as the
#            built-in clock did)
#   running  shows the countdown; left-click swaps it for the full date
#            and time
#   tooltip  always the month calendar, like the built-in clock's
#
# Clicks (wired in waybar/config.jsonc):
#   left    toggle the full date (running: in place of the countdown)
#   right   open the panel (pomodoro-panel.py): start, controls, settings
#   middle  pause / resume (does nothing while idle; start from the panel)
#   scroll  add / remove a minute on the current phase
#
# State lives in a file, not in this process: burn-in.sh restarts waybar on
# every sway reload, and the timer has to survive that. Each `status` call
# (once a second) works out the remaining time from the stored end time.

# Defaults; the panel saves overrides to $conf (outside the repo, so tweaking
# a duration doesn't dirty the dotfiles).
WORK=25 SHORT=5 LONG=15   # minutes
LONG_EVERY=4              # long break after every Nth work session
SOUND=1                   # play a sound when a phase ends
AUTOSTART=0               # start the next work session when a break ends
conf="${XDG_CONFIG_HOME:-$HOME/.config}/waybar-pomodoro.conf"
[ -f "$conf" ] && . "$conf"
TZ=Asia/Kathmandu; export TZ
SIGNAL=9                                # must match "signal" in config.jsonc

dir="${XDG_RUNTIME_DIR:-/tmp}"
state="$dir/waybar-pomodoro"
SOUNDS=/usr/share/sounds/freedesktop/stereo

# Nerd Font glyphs.
ICON_WORK=$'\U000f051b'    # md-timer
ICON_BREAK=$'\U000f0176'   # md-coffee
ICON_PAUSE=$'\U000f03e4'   # md-pause
ICON_READY=$'\U000f051f'   # md-timer_sand

# phase:  idle | work | short | long
# status: running (end set) | paused (left set) | ready (left set, waiting to start)
# view:   timer | clock      — what a running timer shows
# alt:    0 | 1              — long date format for the idle clock
phase=idle status= end=0 left=0 count=0 view=timer alt=0

exec 9>"$dir/waybar-pomodoro.lock"
flock 9

load() { [ -f "$state" ] && . "$state"; }
save() {
    printf 'phase=%s\nstatus=%s\nend=%s\nleft=%s\ncount=%s\nview=%s\nalt=%s\n' \
        "$phase" "$status" "$end" "$left" "$count" "$view" "$alt" > "$state.tmp"
    mv "$state.tmp" "$state"
}
refresh() { pkill -RTMIN+$SIGNAL -x waybar; }
now() { printf '%(%s)T' -1; }

minutes_for() {
    case "$1" in work) echo $WORK ;; short) echo $SHORT ;; long) echo $LONG ;; esac
}

alert() {  # title body sound
    [ "$QUIET" = 1 ] && return
    notify-send -a Pomodoro -h string:x-canonical-private-synchronous:pomodoro "$1" "$2"
    [ "$SOUND" = 1 ] && pw-play "$SOUNDS/$3" &>/dev/null &
}

# Move past any phase whose end time has passed. Work rolls straight into a
# break; a finished break waits for a click (unless AUTOSTART=1), so a
# walk-away doesn't loop forever.
advance() {
    [ "$status" = running ] || return 0
    [ "$(now)" -ge "$end" ] || return 0
    if [ "$phase" = work ]; then
        count=$((count + 1))
        if (( count % LONG_EVERY == 0 )); then phase=long; else phase=short; fi
        local m; m=$(minutes_for "$phase")
        end=$(( $(now) + m * 60 ))
        alert "Work session $count done" "Take a $m-minute break." complete.oga
    elif [ "$AUTOSTART" = 1 ]; then
        phase=work end=$(( $(now) + WORK * 60 ))
        alert "Break over" "Work session $((count + 1)) started." bell.oga
    else
        phase=work status=ready left=$((WORK * 60))
        alert "Break over" "Middle-click the timer or open its panel to start the next work session." bell.oga
    fi
    view=timer
    save
}

remaining() {
    if [ "$status" = running ]; then echo $(( end - $(now) )); else echo "$left"; fi
}

case "$1" in
pause)  # bar middle-click: like toggle, but never starts a new pomodoro
    load
    [ "$phase" = idle ] && exit 0
    exec "$0" toggle ;;
toggle)
    load
    case "$status" in
        running) left=$(( end - $(now) )); status=paused ;;
        paused|ready) end=$(( $(now) + left )); status=running ;;
        *) phase=work status=running count=0 view=timer end=$(( $(now) + WORK * 60 )) ;;
    esac
    save; refresh; exit 0 ;;
skip)  # end the current phase now, without the alert
    load
    [ "$phase" = idle ] && exit 0
    status=running end=0 QUIET=1
    advance; refresh; exit 0 ;;
info)  # machine-readable state for the panel
    load; advance
    [ "$phase" = idle ] && secs=$((WORK * 60)) || secs=$(remaining)
    (( secs < 0 )) && secs=0
    jq -cn --arg phase "$phase" --arg status "$status" \
        --argjson remaining "$secs" --argjson count "$count" \
        --argjson work "$WORK" --argjson short "$SHORT" --argjson long "$LONG" \
        --argjson long_every "$LONG_EVERY" --argjson sound "$SOUND" \
        --argjson autostart "$AUTOSTART" '$ARGS.named'
    exit 0 ;;
stop)
    load
    phase=idle status= end=0 left=0 count=0 view=timer
    save; refresh; exit 0 ;;
view)
    load
    if [ "$phase" = idle ]; then
        alt=$(( 1 - alt ))
    elif [ "$view" = timer ]; then view=clock; else view=timer; fi
    save; refresh; exit 0 ;;
adjust)
    load
    [ "$phase" = idle ] && exit 0
    delta=$(( ${2:-0} * 60 ))
    if [ "$status" = running ]; then
        end=$(( end + delta )); (( end - $(now) < 60 )) && end=$(( $(now) + 60 ))
    else
        left=$(( left + delta )); (( left < 60 )) && left=60
    fi
    save; refresh; exit 0 ;;
status)
    sep="${2:-:}"   # burn-in.sh rotates the clock separator through config.jsonc
    ;;
*)
    echo "usage: $0 status [sep] | info | toggle | pause | skip | stop | view | adjust <±minutes>" >&2
    exit 1 ;;
esac

load
advance

short_clock() { printf "%(%H${sep}%M${sep}%S)T" -1; }
full_clock()  { printf "%(%a, %Y-%m-%d %H${sep}%M${sep}%S)T" -1; }

# Same tooltip as the old built-in clock: the month's calendar, today marked.
tooltip="<big>$(printf '%(%Y %B)T' -1)</big>
<tt><small>$(cal --color=always | sed -e '/^ *$/d' -e 's/\x1b\[7m/<b><u>/' -e 's/\x1b\[0m/<\/u><\/b>/')</small></tt>"

if [ "$phase" = idle ]; then
    class=idle
    if [ "$alt" = 1 ]; then text=$(full_clock); else text=$(short_clock); fi
else
    secs=$(remaining); (( secs < 0 )) && secs=0
    case "$status" in
        paused) icon=$ICON_PAUSE; class=paused ;;
        ready)  icon=$ICON_READY; class=ready ;;
        *) if [ "$phase" = work ]; then icon=$ICON_WORK; class=work; else icon=$ICON_BREAK; class=break; fi ;;
    esac
    if [ "$view" = clock ]; then
        text="$icon $(full_clock)"; class="$class clock"
    else
        text=$(printf "%s %02d${sep}%02d" "$icon" $((secs / 60)) $((secs % 60)))
    fi
fi

jq -cn --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" \
    '{text: $text, tooltip: $tooltip, class: ($class | split(" ")), alt: $class}'
