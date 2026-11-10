#!/bin/bash

# Atoll: the network half of Ambxst's Go backend
# (backend/pkg/svc/network), as nmcli calls. Omarchy runs NetworkManager but
# has no command that prints this state as JSON, so the shell asks here.
#
#   net.sh status              -> {wifi, ethernet, wifi_enabled, wifi_status, network_name, strength, connectivity}
#   net.sh networks            -> [{active, strength, frequency, ssid, bssid, security}]
#   net.sh enable <on|off>     -> status
#   net.sh connect <ssid> [pw] -> {ok, need_password, error}
#   net.sh disconnect <ssid>   -> {ok}
#   net.sh monitor             -> one line per NetworkManager change (long-running)

status() {
  local wifi=false ethernet=false wifi_status="" conn name strength=0 radio=false
  conn=$(nmcli -t -f CONNECTIVITY general 2>/dev/null)

  while IFS=: read -r type state; do
    case $type in
      ethernet) [[ $state == "connected" ]] && ethernet=true ;;
      wifi)
        case $state in
          connected)
            wifi=true
            wifi_status="connected"
            if [[ $conn == "limited" ]]; then
              wifi_status="limited"
              wifi=false
            fi
            ;;
          connecting*) wifi_status="connecting" ;;
          unavailable) wifi_status="disabled" ;;
        esac
        ;;
    esac
  done < <(nmcli -t -f TYPE,STATE device status 2>/dev/null)

  name=$(nmcli -t -f NAME connection show --active 2>/dev/null | head -n1)
  strength=$(nmcli -t -f IN-USE,SIGNAL device wifi list --rescan no 2>/dev/null | awk -F: '$1=="*"{print $2; exit}')
  [[ $(nmcli radio wifi 2>/dev/null) == "enabled" ]] && radio=true
  [[ $wifi == "false" && -z $wifi_status && $ethernet == "false" ]] && wifi_status="disconnected"

  jq -cn --argjson wifi "$wifi" --argjson ethernet "$ethernet" --argjson radio "$radio" \
    --arg status "$wifi_status" --arg name "$name" --arg strength "${strength:-0}" --arg conn "$conn" \
    '{wifi:$wifi, ethernet:$ethernet, wifi_enabled:$radio, wifi_status:$status, network_name:$name,
      strength:(($strength|tonumber?) // 0), connectivity:$conn}'
}

networks() {
  # -t escapes ':' inside fields as '\:'; split on unescaped colons only.
  nmcli -t -f ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY device wifi list --rescan auto 2>/dev/null |
    jq -Rsc '
      split("\n") | map(select(length > 0)
        | gsub("\\\\:"; "\u0001") | split(":") | map(gsub("\u0001"; ":")) as $f
        | select(($f | length) >= 6 and $f[3] != "")
        | {active: ($f[0] == "yes"), strength: ($f[1] | tonumber? // 0),
           frequency: ($f[2] | gsub("[^0-9]"; "") | tonumber? // 0),
           ssid: $f[3], bssid: $f[4], security: $f[5]})'
}

connect() {
  local ssid=$1 password=${2:-} out
  if [[ -n $password ]]; then
    out=$(nmcli device wifi connect "$ssid" password "$password" 2>&1)
  elif nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "$ssid"; then
    out=$(nmcli connection up id "$ssid" 2>&1)
  else
    out=$(nmcli device wifi connect "$ssid" 2>&1)
  fi
  local code=$?

  if (( code == 0 )); then
    jq -cn '{ok:true, need_password:false}'
  elif grep -qiE "secrets were required|password|802-11-wireless-security" <<<"$out"; then
    jq -cn --arg e "$out" '{ok:false, need_password:true, error:$e}'
  else
    jq -cn --arg e "$out" '{ok:false, need_password:false, error:$e}'
  fi
}

case ${1:-} in
  status) status ;;
  networks) networks ;;
  enable)
    nmcli radio wifi "${2:-on}" >/dev/null 2>&1
    status
    ;;
  connect) connect "${2:-}" "${3:-}" ;;
  disconnect)
    nmcli connection down id "${2:-}" >/dev/null 2>&1
    jq -cn '{ok:true}'
    ;;
  monitor) exec nmcli monitor ;;
  *)
    echo "Usage: net.sh <status|networks|enable|connect|disconnect|monitor>" >&2
    exit 2
    ;;
esac
