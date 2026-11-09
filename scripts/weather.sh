#!/bin/bash

# Ambxst on Omarchy: the weather half of Ambxst's Go backend
# (backend/pkg/svc/weather). Omarchy's weather widget keeps its data to
# itself, so this asks open-meteo for the payload Ambxst's WeatherService
# reads: {current_weather, daily} or {error}.
#
#   weather.sh [location]   location: "" (from IP), "lat,lon", or a city name

location=${1:-}

fail() {
  jq -cn --arg e "$1" '{error:$e}'
  exit 0
}

get() {
  curl -fsL --max-time 20 "$@"
}

if [[ -z $location ]]; then
  geo=$(get "http://ip-api.com/json/") || fail "geolocation failed"
  coords=$(jq -r 'select(.status == "success") | "\(.lat),\(.lon)"' <<<"$geo")
  [[ -n $coords ]] || fail "geolocation: $(jq -r '.message // "unknown"' <<<"$geo")"
elif [[ $location =~ ^[[:space:]]*-?[0-9.]+[[:space:]]*,[[:space:]]*-?[0-9.]+[[:space:]]*$ ]]; then
  coords=${location// /}
else
  geo=$(get --get --data-urlencode "name=$location" --data "count=1" "https://geocoding-api.open-meteo.com/v1/search") || fail "geocoding failed"
  coords=$(jq -r '.results[0] // empty | "\(.latitude),\(.longitude)"' <<<"$geo")
  [[ -n $coords ]] || fail "geocoding: no results for $location"
fi

lat=${coords%%,*}
lon=${coords##*,}

data=$(get --get "https://api.open-meteo.com/v1/forecast" \
  --data "latitude=$lat" --data "longitude=$lon" --data "current_weather=true" \
  --data "daily=temperature_2m_max,temperature_2m_min,sunrise,sunset,weathercode" \
  --data "timezone=auto" --data "forecast_days=7") || fail "forecast request failed"

if [[ $(jq -r '.error // false' <<<"$data") == "true" ]]; then
  fail "$(jq -r '.reason // "open-meteo error"' <<<"$data")"
fi

jq -c '{current_weather, daily}' <<<"$data"
