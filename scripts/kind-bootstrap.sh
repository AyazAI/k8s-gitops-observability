#!/usr/bin/env bash
# Bootstraps a local kind cluster and an Argo CD app-of-apps.
# Default mode mirrors this working tree to an in-cluster git server and
# rewrites only that mirror's repo URL. Files in the Git checkout stay
# pointed at GitHub. Grafana's admin password is generated into a Secret.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/versions.env"

GITOPS_MODE="${GITOPS_MODE:-local}"
IMAGE="${IMAGE:-portfolio-sample:dev}"
GIT_IMAGE="${GIT_IMAGE:-portfolio-git-server:dev}"
LOCAL_GIT_URL="http://git-server.git-system.svc.cluster.local:8080/portfolio.git"

"$ROOT/scripts/kind-up.sh"

load_image() {
  local image="$1"
  if ! kind load docker-image "$image" --name "$CLUSTER_NAME"; then
    echo "kind load failed for $image; importing with ctr"
    docker save "$image" | docker exec -i "${CLUSTER_NAME}-control-plane" ctr -n k8s.io images import -
  fi
}

echo "building $IMAGE"
docker build -t "$IMAGE" "$ROOT/app"
load_image "$IMAGE"

if [ "$GITOPS_MODE" = "local" ]; then
  echo "building $GIT_IMAGE"
  docker build -t "$GIT_IMAGE" "$ROOT/deploy/kind/git-server"
  load_image "$GIT_IMAGE"
fi

echo "installing Argo CD $ARGO_CD_VERSION"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/v${ARGO_CD_VERSION#v}/manifests/install.yaml"

kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
  -p '{"data":{"server.insecure":"true"}}'
# Local cluster only: SSO, notifications, and ApplicationSet are unused
# by this sample and are scaled to zero so the node can also run Prometheus.
kubectl -n argocd scale deploy/argocd-dex-server --replicas=0
kubectl -n argocd scale deploy/argocd-notifications-controller --replicas=0
kubectl -n argocd scale deploy/argocd-applicationset-controller --replicas=0
kubectl -n argocd rollout restart deploy/argocd-server
kubectl -n argocd rollout status deploy/argocd-server --timeout 300s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout 300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout 300s
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout 180s

echo "creating Grafana admin secret"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
grafana_password="$(python3 -c 'import secrets; print(secrets.token_urlsafe(18)[:24])')"
kubectl -n monitoring create secret generic grafana-admin-credentials \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$grafana_password" \
  --dry-run=client -o yaml | kubectl apply -f -
unset grafana_password

if [ "$GITOPS_MODE" = "github" ]; then
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    kubectl -n argocd create secret generic repo-github \
      --from-literal=url="$GITHUB_REPO_URL" \
      --from-literal=username=git \
      --from-literal=password="$GITHUB_TOKEN" \
      --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n argocd label secret repo-github \
      argocd.argoproj.io/secret-type=repository --overwrite
  fi
  kubectl apply -f "$ROOT/gitops/root-app.yaml"
else
  work="$(mktemp -d)"
  mkdir -p "$work/src"
  tar -C "$ROOT" --exclude .git --exclude .terraform -cf - . | tar -C "$work/src" -xf -
  find "$work/src/gitops" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 \
    | xargs -0 sed -i "s#${GITHUB_REPO_URL}#${LOCAL_GIT_URL}#g"
  git -C "$work/src" init -b main
  git -C "$work/src" add .
  git -C "$work/src" \
    -c user.name="Muhammad Ayaz" \
    -c user.email="45338553+AyazAI@users.noreply.github.com" \
    commit -m "Mirror working tree for the local kind GitOps remote"
  git clone --bare "$work/src" "$work/portfolio.git"
  git -C "$work/portfolio.git" update-server-info
  touch "$work/portfolio.git/git-daemon-export-ok"

  kubectl apply -f "$ROOT/deploy/kind/git-server.yaml"
  kubectl -n git-system wait --for=condition=Ready pod/git-server --timeout 180s
  kubectl -n git-system cp "$work/portfolio.git" git-server:/srv/git/portfolio.git
  kubectl -n git-system exec git-server -- chmod -R a+rX /srv/git/portfolio.git
  kubectl -n git-system delete pod git-clone-test --ignore-not-found
  kubectl -n git-system run git-clone-test --restart=Never --image="$GIT_IMAGE" \
    --image-pull-policy=IfNotPresent \
    --command -- git clone "$LOCAL_GIT_URL" /tmp/clone
  if ! kubectl -n git-system wait --for=jsonpath='{.status.phase}'=Succeeded pod/git-clone-test --timeout 120s; then
    kubectl -n git-system logs pod/git-clone-test || true
    kubectl -n git-system describe pod/git-clone-test || true
    exit 1
  fi
  kubectl apply -f "$work/src/gitops/root-app.yaml"
  rm -rf "$work"
fi

echo "waiting for Applications"
wait_app() {
  local name="$1"
  local i sync health
  for i in $(seq 1 90); do
    sync="$(kubectl -n argocd get application "$name" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
    health="$(kubectl -n argocd get application "$name" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
    echo "$name sync=${sync:-unknown} health=${health:-unknown} (${i})"
    if [ "$sync" = "Synced" ] && [ "$health" = "Healthy" ]; then
      return 0
    fi
    sleep 10
  done
  kubectl -n argocd describe application "$name" || true
  return 1
}

wait_app root
wait_app metrics-server
wait_app kube-prometheus-stack
wait_app portfolio-sample
kubectl -n argocd get applications
echo "bootstrap complete"
echo "passwords: make print-passwords"
echo "UI forwards: make port-forward"
