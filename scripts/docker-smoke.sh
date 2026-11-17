#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-portfolio-sample:dev}"
NAME="portfolio-sample-ro-$$"
PORT="${PORT:-18081}"

docker build -t "$IMAGE" "$ROOT/app"

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" \
  --read-only \
  --user 65532:65532 \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  -p "127.0.0.1:${PORT}:8080" \
  "$IMAGE"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/healthz"; then
    echo
    break
  fi
  sleep 1
done

curl -fsS "http://127.0.0.1:${PORT}/readyz"
echo
curl -fsS "http://127.0.0.1:${PORT}/" 
echo
code="$(curl -s -o /tmp/portfolio-error-body -w "%{http_code}" "http://127.0.0.1:${PORT}/api/error")"
test "$code" = "500"
curl -fsS "http://127.0.0.1:${PORT}/metrics" | grep -q "http_requests_total"
echo "docker smoke passed"
