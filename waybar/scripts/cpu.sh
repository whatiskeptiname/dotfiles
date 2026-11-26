#!/usr/bin/env bash
# custom/cpu: CPU usage on the bar; hover shows per-core usage, average
# clock and the fans (fans.sh). Replaces waybar's built-in cpu module, whose
# tooltip can't include anything it doesn't measure itself (like the fans).
#
# Usage is the change in /proc/stat since the previous call, so the last
# sample is kept in a file (waybar runs this once a second).

prev="${XDG_RUNTIME_DIR:-/tmp}/waybar-cpu-stat"

cur=$(grep '^cpu' /proc/stat)
old=$(cat "$prev" 2>/dev/null)
printf '%s\n' "$cur" > "$prev"

# One line per cpu line: "<name> <usage%>", the aggregate "cpu" line first.
usage=$(awk '
    NR == FNR { for (i = 2; i <= 9; i++) t[$1] += $i; idle[$1] = $5 + $6; next }
    {
        tot = 0; for (i = 2; i <= 9; i++) tot += $i
        dt = tot - t[$1]; di = ($5 + $6) - idle[$1]
        printf "%s %d\n", $1, (dt > 0 && ($1 in t)) ? (100 * (dt - di) / dt + 0.5) : 0
    }' <(printf '%s\n' "$old") <(printf '%s\n' "$cur"))

total=$(awk '$1 == "cpu" { print $2 }' <<< "$usage")

# Per-core usage, four to a row, in a monospace block.
cores=$(awk '$1 != "cpu" { n = substr($1, 4); printf "%sCore%-2s %3d%%", (c % 4 ? "   " : (c ? "\n" : "")), n, $2; c++ }' <<< "$usage")

freq=$(awk '{ s += $1; n++ } END { if (n) printf "%.2f", s / n / 1e6 }' \
    /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null)

tooltip="Total: ${total}%  ·  ${freq} GHz avg"
fans=$("$(dirname "$0")/fans.sh")
[ -n "$fans" ] && tooltip+=$'\n'"$fans"
tooltip+=$'\n'"<tt><small>${cores}</small></tt>"

jq -cn --arg text "$total" --arg tooltip "$tooltip" \
    '{text: $text, tooltip: $tooltip, percentage: ($text | tonumber)}'
