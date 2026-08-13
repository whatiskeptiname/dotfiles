#!/bin/bash
# Randomizes static UI elements on each start to prevent OLED burn-in

WAYBAR_TEMPLATE="$HOME/Documents/self/dotfiles/waybar/config.jsonc"
WAYBAR_CSS_TEMPLATE="$HOME/Documents/self/dotfiles/waybar/style.css"
COLORS_FILE="$HOME/Documents/self/dotfiles/waybar/colors/colors.dark.css"
WAYBAR_RUNTIME="/tmp/waybar-runtime.jsonc"
WAYBAR_CSS_RUNTIME="/tmp/waybar-runtime.css"
STATE_FILE="$HOME/.cache/burn-in-palette-state"

# ── Random wallpaper ──────────────────────────────────────────────────────
WALLPAPER_DIR="$HOME/Documents/self/dotfiles/wallpapers"
WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -name "*.jpg" -o -name "*.png" \) | shuf -n 1)
swaymsg "output * bg $WALLPAPER fill"
echo "$WALLPAPER" > "$HOME/.cache/current-wallpaper"

# ── Gradient theme — two complementary hues, one for "info" (read-only
# sensor) cells and one for "control" (interactive) cells, each rendered
# as a smooth lightness gradient instead of independent random colors.
# The hue pair rotates each boot (anti-burn-in) — same rotate-before-
# repeat mechanism the old flat color pool used — but the gradient itself
# (how shades vary within a hue) is fixed, so it holds for every theme.
# Anchors skip 0/180: red is reserved for urgent windows, and 180 is red's
# complement, so either landing there would collide with that meaning.
ANCHOR_HUES=(30 60 90 120 150 210 240 270 300 330)
TOTAL=${#ANCHOR_HUES[@]}

# Cycle through start indices so hues rotate before repeating
mapfile -t USED < "$STATE_FILE" 2>/dev/null
if [[ ${#USED[@]} -ge $TOTAL ]]; then
    USED=(); > "$STATE_FILE"
fi
ALL_INDICES=($(seq 0 $((TOTAL - 1))))
AVAILABLE=($(comm -23 <(printf '%s\n' "${ALL_INDICES[@]}" | sort) \
                       <(printf '%s\n' "${USED[@]}"    | sort)))
IDX=${AVAILABLE[$RANDOM % ${#AVAILABLE[@]}]}
echo "$IDX" >> "$STATE_FILE"

HUE_INFO=${ANCHOR_HUES[$IDX]}

# 6 info shades + 5 control shades + 1 clock color (info/control's blend)
read -ra THEME_COLORS <<< "$(python3 -c "
import colorsys, sys

def avoid_red(h):  # nudge away from 0/360 — reserved for urgent windows
    h %= 360
    return (h + 40) % 360 if (h < 15 or h > 345) else h

h_info_deg = float(sys.argv[1])
# Control sits 140° from info — enough contrast to read as a distinct
# family without being an exact complement, which would always RGB-blend
# to flat gray. Clock takes the hue exactly between the two.
h_control_deg = avoid_red(h_info_deg + 140)
h_clock_deg = avoid_red(h_info_deg + 70)
h_info, h_control, h_clock = h_info_deg / 360, h_control_deg / 360, h_clock_deg / 360

def shade(h, l, s=0.62):
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return '#%02x%02x%02x' % (round(r * 255), round(g * 255), round(b * 255))

n_info, n_control = 6, 5
info = [shade(h_info, 0.72 - i * 0.32 / (n_info - 1)) for i in range(n_info)]
control = [shade(h_control, 0.72 - i * 0.32 / (n_control - 1)) for i in range(n_control)]
clock = shade(h_clock, 0.62, 0.68)

print(' '.join(info + control + [clock]))
" "$HUE_INFO")"

INFO_COLORS=("${THEME_COLORS[@]:0:6}")
CONTROL_COLORS=("${THEME_COLORS[@]:6:5}")
ACCENT="${THEME_COLORS[11]}"

# ── Clock separator (shifts pixels each boot) ────────────────────────────
SEP_POOL=(":" "-" "_" " " "∶")
CLOCK_SEP=${SEP_POOL[$RANDOM % ${#SEP_POOL[@]}]}

# ── 1. Random position + side ────────────────────────────────────────────
POSITIONS=("top" "bottom")
POSITION=${POSITIONS[$RANDOM % 2]}
FLIPPED=$((RANDOM % 2))

# ── 2. Read-only sensors on one side, controllable things on the other ───
# INFO = things you only look at (workspaces tags along here since it has
# nowhere else to go, not because it's a sensor). CONTROL = things you
# click/scroll to change (volume, brightness, mic, media transport,
# notification toggle, tray). Keeping them apart makes each side read as
# one coherent group instead of an arbitrary width-balanced mix.
#
# modules-left renders edge→center, left-to-right; modules-right renders
# center→edge, since it's anchored to the screen's right edge — the same
# array position means opposite physical placement depending on the side.
# Each group is a FLAT array, one element per module, built center→edge —
# join() uses that order as-is for modules-right, reverse() flips it to
# edge→center for modules-left. Reversing element-by-element (not as one
# glued-together block) is what keeps "closest to clock" pinned to the
# same element (index 0) on both sides — needed so the color gradient
# below tracks actual clock-distance consistently regardless of which
# physical side FLIPPED sends a group to. Media is the one exception kept
# as a single opaque element, so its internal prev/track/next/visualizer
# order never gets reversed along with everything else.
INFO_ITEMS=(cpu temperature memory "custom/gpu" disk battery)
INFO_SHUFFLED=($(printf '%s\n' "${INFO_ITEMS[@]}" | shuf))
INFO_GROUP=()
for m in "${INFO_SHUFFLED[@]}"; do INFO_GROUP+=("\"$m\""); done
INFO_GROUP+=('"sway/workspaces"')

SLIDERS=("pulseaudio#source" pulseaudio backlight)
SLIDERS_SHUFFLED=($(printf '%s\n' "${SLIDERS[@]}" | shuf))
CONTROL_GROUP=()
for m in "${SLIDERS_SHUFFLED[@]}"; do CONTROL_GROUP+=("\"$m\""); done
CONTROL_GROUP+=('"custom/mpris-prev", "custom/mpris-now", "custom/mpris-next", "custom/cava"')
CONTROL_GROUP+=('"custom/notification"')
CONTROL_GROUP+=('"tray"')

join() {
    local out="" a
    for a in "$@"; do
        [[ -z "$out" ]] && out="$a" || out="$out, $a"
    done
    echo "$out"
}
reverse() {
    local rev=() i
    for ((i = $#; i >= 1; i--)); do rev+=("${!i}"); done
    join "${rev[@]}"
}

if [[ $FLIPPED -eq 0 ]]; then
    MODULES_LEFT=$(reverse "${INFO_GROUP[@]}");    MODULES_RIGHT=$(join "${CONTROL_GROUP[@]}")
else
    MODULES_LEFT=$(reverse "${CONTROL_GROUP[@]}"); MODULES_RIGHT=$(join "${INFO_GROUP[@]}")
fi

# ── 3. Build runtime waybar config ───────────────────────────────────────
sed \
  -e "s/\"position\": \"[^\"]*\"/\"position\": \"$POSITION\"/" \
  -e "s|\"modules-left\": \[\"sway/workspaces\", \"cpu\", \"temperature\", \"memory\", \"custom/gpu\", \"disk\", \"battery\"\]|\"modules-left\": [$MODULES_LEFT]|" \
  -e "s|\"modules-right\": \[\"pulseaudio#source\", \"pulseaudio\", \"backlight\", \"custom/mpris-prev\", \"custom/mpris-now\", \"custom/mpris-next\", \"custom/cava\", \"custom/notification\", \"tray\"\]|\"modules-right\": [$MODULES_RIGHT]|" \
  -e "s/∶/$CLOCK_SEP/g" \
  "$WAYBAR_TEMPLATE" > "$WAYBAR_RUNTIME"

# ── 4. Build runtime CSS — gradient underline per module ──────────────────
# Shades are assigned in the same order INFO_SHUFFLED/SLIDERS_SHUFFLED put
# those modules on the bar, so the gradient actually reads as a smooth
# sweep across each group instead of a scrambled set of unrelated shades.
# The mpris cluster gets one shared shade across all four selectors,
# rather than one slot per module, since it should read as one cell.
css_id() {  # "custom/gpu" -> "#custom-gpu"; "pulseaudio#source" -> "#pulseaudio.source"
    local name="$1"
    if [[ "$name" == *"#"* ]]; then
        echo "#${name%%#*}.${name##*#}"
    else
        echo "#${name//\//-}"
    fi
}
{
  # Keep base color variables (values don't matter much — overridden below)
  cat "$COLORS_FILE"
  grep -v '@import' "$WAYBAR_CSS_TEMPLATE"
  for i in "${!INFO_SHUFFLED[@]}"; do
    echo "$(css_id "${INFO_SHUFFLED[$i]}") { border-bottom-color: ${INFO_COLORS[$i]}; }"
  done
  for i in "${!SLIDERS_SHUFFLED[@]}"; do
    echo "$(css_id "${SLIDERS_SHUFFLED[$i]}") { border-bottom-color: ${CONTROL_COLORS[$i]}; }"
  done
  echo "#custom-mpris-prev, #custom-mpris-now, #custom-mpris-next, #custom-cava { border-bottom-color: ${CONTROL_COLORS[3]}; }"
  echo "#custom-notification { border-bottom-color: ${CONTROL_COLORS[4]}; }"
  echo "#clock { color: $ACCENT; }"
} > "$WAYBAR_CSS_RUNTIME"

# ── 5. Apply accent color to sway window borders ─────────────────────────
swaymsg "client.focused $ACCENT #08080b #acb0d0 $ACCENT $ACCENT"

# ── 6. Restart waybar ────────────────────────────────────────────────────
# custom/cava is a continuous self-looping module (cava-viz.sh piping cava);
# killing waybar alone orphans that whole child tree, so it has to be swept
# separately or it leaks one more pair of processes on every reload.
pkill -f cava-viz.sh
pkill -x cava
pkill -x waybar
waybar -c "$WAYBAR_RUNTIME" -s "$WAYBAR_CSS_RUNTIME" &
