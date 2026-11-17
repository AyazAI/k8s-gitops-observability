#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/versions.env"
IMAGE="${IMAGE:-portfolio-sample:dev}"

"$ROOT/scripts/kind-up.sh"
docker build -t "$IMAGE" "$ROOT/app"
kind load docker-image "$IMAGE" --name "$CLUSTER_NAME"

kubectl create namespace portfolio-sample --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace portfolio-sample pod-security.kubernetes.io/enforce=restricted --overwrite

# ServiceMonitor and PrometheusRule need the Prometheus Operator CRDs,
# which the full GitOps bootstrap installs. This smoke test checks the
# workload, probes, and /metrics endpoint.
helm upgrade --install portfolio-sample "$ROOT/charts/portfolio-sample" \
  --namespace portfolio-sample \
  -f "$ROOT/charts/portfolio-sample/values.yaml" \
  -f "$ROOT/charts/portfolio-sample/values-dev.yaml" \
  --set serviceMonitor.enabled=false \
  --set prometheusRule.enabled=false \
  --wait --timeout 180s

kubectl -n portfolio-sample rollout status deployment/portfolio-sample --timeout 180s

kubectl -n portfolio-sample port-forward svc/portfolio-sample 18080:8080 >/tmp/portfolio-smoke-pf.log 2>&1 &
pf=$!
cleanup() {
  kill "$pf" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:18080/healthz >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

curl -fsS http://127.0.0.1:18080/healthz
echo
curl -fsS http://127.0.0.1:18080/readyz
echo
curl -fsS http://127.0.0.1:18080/metrics | grep -q http_requests_total
echo "kind smoke passed"
