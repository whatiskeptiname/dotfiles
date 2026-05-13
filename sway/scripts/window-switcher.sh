#!/bin/bash
# Window switcher using swaymsg so workspace numbers are visible

entries=()
ids=()

while IFS=$'\t' read -r ws app title con_id; do
    entries+=("[${ws}]  ${app}  ${title}")
    ids+=("${con_id}")
done < <(
    swaymsg -t get_tree | jq -r '
        .nodes[] | .nodes[] | select(.type == "workspace") | . as $ws |
        [recurse(.nodes[]?, .floating_nodes[]?) |
         select(.pid? != null and .name? != null and .name != "")] |
        .[] |
        [$ws.name, (.app_id // .window_properties.class // "?"), .name, (.id | tostring)] |
        @tsv
    '
)

[ ${#entries[@]} -eq 0 ] && exit 1

selected=$(printf '%s\n' "${entries[@]}" | rofi -dmenu -i -p " Windows" -format i)
[ -z "$selected" ] && exit 0

swaymsg "[con_id=${ids[$selected]}] focus"
