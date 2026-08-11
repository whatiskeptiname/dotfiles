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

# ── 12 non-red colors — red is reserved for urgent windows ───────────────
COLOR_POOL=(
    "#7aa2f7"  # blue
    "#9ece6a"  # green
    "#e0af68"  # yellow
    "#bb9af7"  # purple
    "#7dcfff"  # light cyan
    "#ff9e64"  # orange
    "#2ac3de"  # cyan
    "#41a6b5"  # teal
    "#73daca"  # mint
    "#c3e88d"  # lime
    "#89ddff"  # sky
    "#b4f9f8"  # ice
)
TOTAL=${#COLOR_POOL[@]}

# Cycle through start indices so colors rotate before repeating
mapfile -t USED < "$STATE_FILE" 2>/dev/null
if [[ ${#USED[@]} -ge $TOTAL ]]; then
    USED=(); > "$STATE_FILE"
fi
ALL_INDICES=($(seq 0 $((TOTAL - 1))))
AVAILABLE=($(comm -23 <(printf '%s\n' "${ALL_INDICES[@]}" | sort) \
                       <(printf '%s\n' "${USED[@]}"    | sort)))
IDX=${AVAILABLE[$RANDOM % ${#AVAILABLE[@]}]}
echo "$IDX" >> "$STATE_FILE"

# Rotate pool from IDX, shuffle the rest — gives 9 unique colors per boot
ROTATED=("${COLOR_POOL[@]:$IDX}" "${COLOR_POOL[@]:0:$IDX}")
ACCENT=${ROTATED[0]}
MODULE_COLORS=($(printf '%s\n' "${ROTATED[@]:1}" | shuf | head -9))

# ── Clock separator (shifts pixels each boot) ────────────────────────────
SEP_POOL=(":" "-" "_" " " "∶")
CLOCK_SEP=${SEP_POOL[$RANDOM % ${#SEP_POOL[@]}]}

# ── 1. Random position + side ────────────────────────────────────────────
POSITIONS=("top" "bottom")
POSITION=${POSITIONS[$RANDOM % 2]}
FLIPPED=$((RANDOM % 2))

# ── 2. Shuffle vitals modules (tray always last) ──────────────────────────
RIGHT=(cpu temperature memory "custom/gpu" disk battery backlight pulseaudio "pulseaudio#source")
SHUFFLED=($(printf '%s\n' "${RIGHT[@]}" | shuf))
VITALS_JSON=$(printf '"%s", ' "${SHUFFLED[@]}")"\"custom/notification\", \"tray\""

MEDIA='"custom/mpris-prev", "custom/mpris-now", "custom/mpris-next", "custom/cava"'
if [[ $FLIPPED -eq 0 ]]; then
    MODULES_LEFT='"sway/workspaces"'; MODULES_RIGHT="$VITALS_JSON"
    MODULES_CENTER="$MEDIA, \"clock\""
else
    MODULES_LEFT="$VITALS_JSON";     MODULES_RIGHT='"sway/workspaces"'
    MODULES_CENTER="\"clock\", $MEDIA"
fi

# ── 3. Build runtime waybar config ───────────────────────────────────────
sed \
  -e "s/\"position\": \"[^\"]*\"/\"position\": \"$POSITION\"/" \
  -e "s|\"modules-left\": \[\"sway/workspaces\"\]|\"modules-left\": [$MODULES_LEFT]|" \
  -e "s|\"cpu\", \"temperature\", \"memory\", \"custom/gpu\", \"disk\", \"battery\", \"backlight\", \"pulseaudio\", \"pulseaudio#source\", \"custom/notification\", \"tray\"|$MODULES_RIGHT|" \
  -e "s|\"modules-center\": \[\"custom/mpris-prev\", \"custom/mpris-now\", \"custom/mpris-next\", \"custom/cava\", \"clock\"\]|\"modules-center\": [$MODULES_CENTER]|" \
  -e "s/∶/$CLOCK_SEP/g" \
  "$WAYBAR_TEMPLATE" > "$WAYBAR_RUNTIME"

# ── 4. Build runtime CSS — unique color per module underline ─────────────
MODULES_WITH_UNDERLINE=(cpu custom-gpu temperature memory disk battery backlight pulseaudio network)
{
  # Keep base color variables (values don't matter much — overridden below)
  cat "$COLORS_FILE"
  grep -v '@import' "$WAYBAR_CSS_TEMPLATE"
  # Each module gets its own unique color from the shuffled pool
  for i in "${!MODULES_WITH_UNDERLINE[@]}"; do
    echo "#${MODULES_WITH_UNDERLINE[$i]} { border-bottom-color: ${MODULE_COLORS[$i]}; }"
  done
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
