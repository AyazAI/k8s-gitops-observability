#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

conform() {
  kubeconform -strict -summary -kubernetes-version 1.35.0 \
    -schema-location default \
    -schema-location "$SCHEMA" "$@"
}

for values in values-dev.yaml values-prod.yaml; do
  echo "kubeconform chart with $values"
  helm template portfolio-sample "$ROOT/charts/portfolio-sample" \
    --namespace portfolio-sample \
    -f "$ROOT/charts/portfolio-sample/values.yaml" \
    -f "$ROOT/charts/portfolio-sample/$values" \
    | conform -
done

echo "kubeconform gitops and kind manifests"
conform \
  "$ROOT/gitops/root-app.yaml" \
  "$ROOT/gitops/apps" \
  "$ROOT/gitops/optional/loki.yaml" \
  "$ROOT/deploy/kind/git-server.yaml"
