#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-http://127.0.0.1:18080}"
DURATION="${2:-180}"
end=$((SECONDS + DURATION))

echo "sending traffic to $BASE for ${DURATION}s"
while [ "$SECONDS" -lt "$end" ]; do
  curl -s -o /dev/null "$BASE/api/echo" || true
  curl -s -o /dev/null "$BASE/api/echo?sleep_ms=20" || true
  curl -s -o /dev/null "$BASE/api/echo?sleep_ms=800" || true
  curl -s -o /dev/null "$BASE/api/error" || true
  sleep 0.2
done
echo "traffic complete"
