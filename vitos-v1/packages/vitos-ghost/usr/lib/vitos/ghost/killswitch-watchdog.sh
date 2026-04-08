#!/usr/bin/env bash
# /usr/lib/vitos/ghost/killswitch-watchdog.sh <ns>
#
# Polls 'wg show' inside the given netns every 2 s. If the latest
# handshake is older than 30 s, the kill-switch is reasserted (drop
# everything but lo + wg + tor) so even a dropped tunnel doesn't leak.
set -euo pipefail
NS="${1:?usage: killswitch-watchdog.sh <netns>}"

while true; do
  if ! ip netns list | grep -q "^${NS}\b"; then
    echo "netns ${NS} gone, exiting watchdog"
    exit 0
  fi
  HS=$(ip netns exec "$NS" wg show all latest-handshakes 2>/dev/null | awk '{print $NF}' | sort -n | tail -1)
  HS=${HS:-0}
  NOW=$(date +%s)
  AGE=$((NOW - HS))
  if [ "$AGE" -gt 30 ]; then
    ip netns exec "$NS" nft -f /etc/nftables.d/vitos-ghost.nft || true
    logger -t vitos-ghost "killswitch reasserted on ${NS} (handshake age=${AGE}s)"
  fi
  sleep 2
done
