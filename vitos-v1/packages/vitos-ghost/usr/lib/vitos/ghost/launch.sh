#!/usr/bin/env bash
# /usr/lib/vitos/ghost/launch.sh <user> <profile>
#
# Spawns a network namespace ghost-<uid>, moves a veth pair into it,
# brings WireGuard up inside the netns, starts torsocks/Tor SOCKS,
# applies the nftables kill-switch, and exec's the user's shell inside
# the namespace. All ghost-mode events are still emitted on the
# vitos-busd UNIX socket via a bind mount of /run/vitos.
set -euo pipefail

USER="${1:?usage: launch.sh <user> <profile>}"
PROFILE="${2:?missing profile name}"
UID_NUM=$(id -u "$USER")
NS="ghost-${UID_NUM}"

PROFILE_DIR="/etc/vitos/ghost/profiles/${PROFILE}"
[ -d "$PROFILE_DIR" ] || { echo "profile not found: $PROFILE_DIR"; exit 2; }

# Approval guard — must be present in active/, written by 'vitosctl ghost approve'
APPROVAL="/var/lib/vitos/ghost/active/${USER}.${PROFILE}"
[ -f "$APPROVAL" ] || { echo "no approval token at $APPROVAL"; exit 13; }

ip netns list | grep -q "^${NS}\b" || ip netns add "$NS"

# veth pair: host side stays in default ns, guest side moves into the ns
VETH_HOST="vh-${UID_NUM}"
VETH_GUEST="vg-${UID_NUM}"
if ! ip link show "$VETH_HOST" >/dev/null 2>&1; then
  ip link add "$VETH_HOST" type veth peer name "$VETH_GUEST"
  ip link set "$VETH_GUEST" netns "$NS"
  ip addr add 10.200.${UID_NUM}.1/24 dev "$VETH_HOST"
  ip link set "$VETH_HOST" up
  ip netns exec "$NS" ip addr add 10.200.${UID_NUM}.2/24 dev "$VETH_GUEST"
  ip netns exec "$NS" ip link set "$VETH_GUEST" up
  ip netns exec "$NS" ip link set lo up
fi

# WireGuard config sourced from the profile
if [ -f "${PROFILE_DIR}/wg.conf" ]; then
  ip netns exec "$NS" wg-quick up "${PROFILE_DIR}/wg.conf" || true
fi

# Tor inside the netns (lazy — only if profile requests it)
if [ -f "${PROFILE_DIR}/tor.conf" ]; then
  ip netns exec "$NS" tor -f "${PROFILE_DIR}/tor.conf" --runasdaemon 1
fi

# nftables kill-switch — drops all traffic except lo + wg + tor
ip netns exec "$NS" nft -f /etc/nftables.d/vitos-ghost.nft

# MAC randomization on the guest veth
ip netns exec "$NS" macchanger -r "$VETH_GUEST" || true

# Bind-mount /run/vitos so the busd socket is reachable from inside the ns
mkdir -p "/var/run/netns/${NS}/run"
mount --bind /run/vitos "/var/run/netns/${NS}/run/vitos" 2>/dev/null || true

# Hand off to the user
exec sudo -u "$USER" ip netns exec "$NS" \
     env PS1="[ghost:${PROFILE}] \w\$ " VITOS_GHOST=1 bash -l
