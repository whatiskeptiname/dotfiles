#!/usr/bin/env bash
# Prints the fan line shared by the CPU and GPU tooltips (cpu.sh, gpu.sh),
# e.g. "Fans: 2300 · 2200 RPM" or "Fans: off". Prints nothing without a sensor.
#
# Source: the lenovo_wmi_other hwmon sensor (yogafan also exists here but
# always reads 0). The firmware runs both fans as a pair from whichever chip
# is hotter, over shared heat pipes, so neither is "the CPU fan" or "the GPU
# fan": both tooltips show both. hwmon numbers change between boots, so the
# sensor is found by name.

for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = lenovo_wmi_other ] || continue
    rpms=()
    for f in "$h"/fan[0-9]*_input; do
        [ -r "$f" ] && rpms+=("$(cat "$f")")
    done
    [ ${#rpms[@]} -eq 0 ] && exit 0
    spinning=0
    for r in "${rpms[@]}"; do (( r > 0 )) && spinning=1; done
    if (( spinning )); then
        line=$(printf ' · %s' "${rpms[@]}")
        echo "Fans: ${line:3} RPM"
    else
        echo "Fans: off"
    fi
    exit 0
done
