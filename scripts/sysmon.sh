#!/bin/bash

# Atoll: the system monitor half of Ambxst's Go backend
# (backend/pkg/svc/systemmonitor). Omarchy has no streaming resource monitor
# (omarchy-system-stats prints once, for humans), so this streams the same
# payload the dashboard's Metrics tab reads. It only runs while that tab is
# open; the shell starts it with the interval and the disks to report.
#
#   sysmon.sh <interval-ms> <disk>[,<disk>...]
#
# First line:  S {"cpu_model", "gpu_names", "gpu_vendors", "gpu_count", "disk_types"}
# Then, every interval:
#              D {"cpu":{usage,temp}, "ram":{usage,total,used,available}, "disk":{usage:{mount:pct}}, "gpu":{usages,temps}}

interval_ms=${1:-2000}
IFS=, read -r -a disks <<<"${2:-/}"
(( interval_ms < 100 )) && interval_ms=100
interval=$(awk -v ms="$interval_ms" 'BEGIN { printf "%.3f", ms / 1000 }')

# GPUs: DRM cards with a PCI vendor; usage from gpu_busy_percent (AMD, Intel
# Xe) or nvidia-smi when the NVIDIA driver is present.
gpu_cards=()
gpu_vendors=()
gpu_names=()
for dev in /sys/class/drm/card[0-9]*/device; do
  [[ -r $dev/vendor ]] || continue
  [[ $dev == */card*-*/device ]] && continue
  case $(<"$dev/vendor") in
    0x1002) vendor=amd ;;
    0x8086) vendor=intel ;;
    0x10de) vendor=nvidia ;;
    *) continue ;;
  esac
  name=$(lspci -s "$(basename "$(readlink -f "$dev")")" 2>/dev/null | sed 's/^[^:]*: //; s/^[^:]*: //')
  gpu_cards+=("$dev")
  gpu_vendors+=("$vendor")
  gpu_names+=("${name:-$vendor}")
done

cpu_model=$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo)

disk_types="{}"
for mount in "${disks[@]}"; do
  src=$(findmnt -no SOURCE --target "$mount" 2>/dev/null | sed 's/\[.*//')
  base=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1)
  [[ -z $base ]] && base=$(basename "$src")
  rotational=$(cat "/sys/block/$base/queue/rotational" 2>/dev/null)
  if [[ $base == nvme* ]]; then
    type=nvme
  elif [[ $rotational == "0" ]]; then
    type=ssd
  elif [[ $rotational == "1" ]]; then
    type=hdd
  else
    type=unknown
  fi
  disk_types=$(jq -c --arg m "$mount" --arg t "$type" '. + {($m): $t}' <<<"$disk_types")
done

printf 'S %s\n' "$(jq -cn --arg cpu "$cpu_model" --argjson types "$disk_types" \
  --args '{cpu_model:$cpu, gpu_names:$ARGS.positional[0:($ARGS.positional|length/2)],
    gpu_vendors:$ARGS.positional[($ARGS.positional|length/2):], gpu_count:($ARGS.positional|length/2),
    disk_types:$types}' "${gpu_names[@]}" "${gpu_vendors[@]}")"

cpu_temp_file=""
for hw in /sys/class/hwmon/hwmon*; do
  case $(cat "$hw/name" 2>/dev/null) in
    coretemp | k10temp | zenpower | cpu_thermal | x86_pkg_temp)
      [[ -r $hw/temp1_input ]] && cpu_temp_file=$hw/temp1_input && break
      ;;
  esac
done

read -r _ a b c idle_prev e f g h _ </proc/stat
total_prev=$((a + b + c + idle_prev + e + f + g + h))

while true; do
  sleep "$interval"

  read -r _ a b c idle e f g h _ </proc/stat
  total=$((a + b + c + idle + e + f + g + h))
  dt=$((total - total_prev))
  di=$((idle - idle_prev))
  cpu_usage=$(awk -v t="$dt" -v i="$di" 'BEGIN { printf "%.1f", (t > 0 ? (t - i) * 100 / t : 0) }')
  total_prev=$total
  idle_prev=$idle

  cpu_temp=-1
  [[ -n $cpu_temp_file ]] && cpu_temp=$(( $(<"$cpu_temp_file") / 1000 ))

  read -r mem_total mem_avail < <(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{print t, a}' /proc/meminfo)
  mem_used=$((mem_total - mem_avail))

  disk_json=$(df -P "${disks[@]}" 2>/dev/null | awk 'NR>1 { sub(/%/, "", $5); print $6 "\t" $5 }' |
    jq -Rsc --args 'split("\n") | map(select(length>0) | split("\t")) as $rows
      | [$ARGS.positional, $rows] | transpose | map(select(.[1] != null) | {(.[0]): (.[1][1] | tonumber)}) | add // {}' "${disks[@]}")

  gpu_usages=()
  gpu_temps=()
  for i in "${!gpu_cards[@]}"; do
    dev=${gpu_cards[$i]}
    usage=0
    temp=-1
    if [[ ${gpu_vendors[$i]} == "nvidia" ]] && command -v nvidia-smi >/dev/null; then
      read -r usage temp < <(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ',')
    else
      [[ -r $dev/gpu_busy_percent ]] && usage=$(<"$dev/gpu_busy_percent")
      for t in "$dev"/hwmon/hwmon*/temp1_input; do
        [[ -r $t ]] && temp=$(( $(<"$t") / 1000 )) && break
      done
    fi
    gpu_usages+=("${usage:-0}")
    gpu_temps+=("${temp:--1}")
  done

  printf 'D {"cpu":{"usage":%s,"temp":%s},"ram":{"usage":%s,"total":%s,"used":%s,"available":%s},"disk":{"usage":%s},"gpu":{"usages":[%s],"temps":[%s]}}\n' \
    "$cpu_usage" "$cpu_temp" \
    "$(awk -v u="$mem_used" -v t="$mem_total" 'BEGIN { printf "%.1f", (t > 0 ? u * 100 / t : 0) }')" \
    "$mem_total" "$mem_used" "$mem_avail" \
    "$disk_json" \
    "$(IFS=,; echo "${gpu_usages[*]}")" "$(IFS=,; echo "${gpu_temps[*]}")"
done
