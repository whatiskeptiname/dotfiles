#!/usr/bin/env bash

# Detect which DRM card sway is using
active_card_path=""
active_vendor=""

sway_pid=$(pgrep -x sway | head -1)
if [ -n "$sway_pid" ]; then
    for dev in $(readlink /proc/$sway_pid/fd/* 2>/dev/null | grep '/dev/dri/card'); do
        card_num=${dev##*card}
        card_path="/sys/class/drm/card${card_num}/device"
        vendor=$(cat "$card_path/vendor" 2>/dev/null)
        case "$vendor" in
            0x1002) active_vendor="amd";    active_card_path="$card_path"; break ;;
            0x10de) active_vendor="nvidia"; break ;;
            0x8086) active_vendor="intel";  active_card_path="$card_path"; break ;;
        esac
    done
fi

# Fallback: any AMD card
if [ -z "$active_vendor" ]; then
    for f in /sys/class/drm/card*/device/gpu_busy_percent; do
        [ -f "$f" ] || continue
        active_vendor="amd"; active_card_path=$(dirname "$f"); break
    done
fi
[ -z "$active_vendor" ] && command -v nvidia-smi &>/dev/null && active_vendor="nvidia"

# --- stat collectors ---

amd_stats() {
    local p="$1"
    local usage vram_used vram_total um tm temp temp_raw name
    usage=$(cat "$p/gpu_busy_percent" 2>/dev/null || echo "0")
    vram_used=$(cat "$p/mem_info_vram_used" 2>/dev/null || echo "0")
    vram_total=$(cat "$p/mem_info_vram_total" 2>/dev/null || echo "0")
    um=$((vram_used / 1024 / 1024)); tm=$((vram_total / 1024 / 1024))
    temp="N/A"
    for hwmon in /sys/class/hwmon/hwmon*/name; do
        [ "$(cat "$hwmon" 2>/dev/null)" = "amdgpu" ] || continue
        temp_raw=$(cat "$(dirname "$hwmon")/temp1_input" 2>/dev/null || echo "0")
        temp=$((temp_raw / 1000)); break
    done
    name=$(cat "$p/product_name" 2>/dev/null)
    [ -z "$name" ] && name=$(lspci 2>/dev/null | grep -E 'VGA|3D|Display' | grep -i amd | head -1 | sed 's/.*: //;s/ (.*//')
    [ -z "$name" ] && name="AMD GPU"
    echo "${name}|${usage}|${um}|${tm}|${temp}"
}

nvidia_stats() {
    local line name usage um tm temp
    line=$(nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu \
           --format=csv,noheader,nounits 2>/dev/null | head -1)
    [ -z "$line" ] && return
    name=$(echo "$line" | cut -d',' -f1 | xargs)
    usage=$(echo "$line" | cut -d',' -f2 | xargs)
    um=$(echo "$line"    | cut -d',' -f3 | xargs)
    tm=$(echo "$line"    | cut -d',' -f4 | xargs)
    temp=$(echo "$line"  | cut -d',' -f5 | xargs)
    echo "${name}|${usage}|${um}|${tm}|${temp}"
}

tooltip_section() {
    # "name|usage|vram_used|vram_total|temp" [label]
    local IFS='|'; read -r name usage um tm temp <<< "$1"
    local label="${2:+  ($2)}"
    printf '%s%s\nGPU: %s%%\nVRAM: %s/%s MB\nTemp: %s°C' \
        "$name" "$label" "$usage" "$um" "$tm" "$temp"
}

# --- gather active GPU stats ---

active=""
case "$active_vendor" in
    amd)    active=$(amd_stats "$active_card_path") ;;
    nvidia) active=$(nvidia_stats) ;;
esac

if [ -z "$active" ]; then
    echo '{"text": "N/A", "tooltip": "No GPU detected"}'; exit 0
fi

IFS='|' read -r _ usage um _ temp <<< "$active"
bar_text="${usage}% ${um}M ${temp}°C "

tooltip=$(tooltip_section "$active" "active")

# --- find dedicated GPU (different from active) ---

# NVIDIA discrete (when active is AMD/Intel)
if [ "$active_vendor" != "nvidia" ] && command -v nvidia-smi &>/dev/null; then
    nv=$(nvidia_stats)
    [ -n "$nv" ] && tooltip="${tooltip}\n\n$(tooltip_section "$nv" "dedicated")"
fi

# Other AMD cards (dedicated or second integrated)
for f in /sys/class/drm/card*/device/gpu_busy_percent; do
    [ -f "$f" ] || continue
    card_path=$(dirname "$f")
    [ "$card_path" = "$active_card_path" ] && continue
    stats=$(amd_stats "$card_path")
    [ -n "$stats" ] && tooltip="${tooltip}\n\n$(tooltip_section "$stats" "dedicated")"
done

# Escape newlines for JSON
tooltip_json=$(printf '%s' "$tooltip" | sed ':a;N;$!ba;s/\n/\\n/g')

echo "{\"text\": \"${bar_text}\", \"tooltip\": \"${tooltip_json}\"}"
