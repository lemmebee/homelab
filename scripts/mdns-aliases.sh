#!/usr/bin/env bash
# Publish one mDNS alias per app, so every device on the LAN can reach the
# stack by short name: http://ouioui.local, http://kashkul.local, ...
#
# App names are read from dynamic/routes.yaml (the router keys), so adding an
# app there is enough: no list to keep in sync here. Aliases all point at this
# machine's LAN IP; traefik then routes by Host header as usual.
#
# Runs under systemd, see homelab-mdns.service and `make mdns-install`.
set -euo pipefail

ROUTES="$(dirname "$(readlink -f "$0")")/../dynamic/routes.yaml"

current_ip() {
  # LAN address of whichever interface holds the default route.
  ip -4 -o route get 1.1.1.1 2>/dev/null | awk '{print $7}'
}

app_names() {
  # Router keys: the 4-space-indented `name:` entries under `routers:`,
  # stopping at the next top-level key (`services:`).
  awk '
    /^  routers:/      { in_routers = 1; next }
    /^  [a-z]+:/       { in_routers = 0 }
    in_routers && /^    [a-z0-9_-]+:$/ { gsub(/[ :]/, "", $0); print }
  ' "$ROUTES"
}

IP="$(current_ip)"
[ -n "$IP" ] || { echo "no LAN IP found (no default route?)" >&2; exit 1; }

mapfile -t APPS < <(app_names)
[ "${#APPS[@]}" -gt 0 ] || { echo "no routers found in $ROUTES" >&2; exit 1; }

pids=()
for app in "${APPS[@]}"; do
  avahi-publish -a -R "$app.local" "$IP" &
  pids+=("$!")
done
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT

echo "publishing ${APPS[*]} as *.local -> $IP"

# Exit if the DHCP lease changes the IP or any publisher dies; systemd's
# Restart=always then brings us back up with the new address.
while sleep 60; do
  [ "$(current_ip)" = "$IP" ] || { echo "LAN IP changed, restarting" >&2; exit 0; }
  for pid in "${pids[@]}"; do
    kill -0 "$pid" 2>/dev/null || { echo "publisher $pid died, restarting" >&2; exit 1; }
  done
done
