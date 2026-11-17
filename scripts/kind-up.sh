#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/versions.env"

# Docker 29 on some hosts keeps an iptables-legacy filter table whose
# FORWARD policy is DROP. nftables accepts the kind bridge, then the legacy
# table drops it, so pods cannot pull images. Accept forwarding and NAT the
# kind subnet in the legacy table when that policy is present.
if command -v iptables-legacy >/dev/null 2>&1; then
  if sudo iptables-legacy -S FORWARD 2>/dev/null | head -n 1 | grep -q 'FORWARD DROP'; then
    echo "iptables-legacy FORWARD is DROP; setting it to ACCEPT for kind egress"
    sudo iptables-legacy -P FORWARD ACCEPT
  fi
fi

if kind get clusters | grep -qx "$CLUSTER_NAME"; then
  echo "kind cluster $CLUSTER_NAME already exists"
else
  kind create cluster --config "$ROOT/kind/cluster.yaml"
fi

if command -v iptables-legacy >/dev/null 2>&1 && docker network inspect kind >/dev/null 2>&1; then
  bridge_id="$(docker network inspect kind -f '{{.Id}}' | cut -c1-12)"
  ifname="$(ip -o link | awk -v id="$bridge_id" '$2 ~ ("br-" id) {gsub(/:/, "", $2); print $2; exit}')"
  while read -r subnet; do
    case "$subnet" in
      *.*) ;;
      *) continue ;;
    esac
    if [ -n "$ifname" ]; then
      sudo iptables-legacy -t nat -C POSTROUTING -s "$subnet" ! -o "$ifname" -j MASQUERADE 2>/dev/null || \
        sudo iptables-legacy -t nat -A POSTROUTING -s "$subnet" ! -o "$ifname" -j MASQUERADE
    fi
  done < <(docker network inspect kind -f '{{range .IPAM.Config}}{{println .Subnet}}{{end}}')
fi

kubectl cluster-info
kubectl get nodes
