#!/usr/bin/env bash
set -euo pipefail

echo "Argo CD    http://127.0.0.1:8080"
echo "Grafana    http://127.0.0.1:3000"
echo "Prometheus http://127.0.0.1:9090"
echo "App        http://127.0.0.1:18080"

kubectl -n argocd port-forward svc/argocd-server 8080:80 >/tmp/pf-argocd.log 2>&1 &
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80 >/tmp/pf-grafana.log 2>&1 &
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 >/tmp/pf-prometheus.log 2>&1 &
kubectl -n portfolio-sample port-forward svc/portfolio-sample 18080:8080 >/tmp/pf-app.log 2>&1 &

echo "port-forwards started; logs are in /tmp/pf-*.log"
wait
