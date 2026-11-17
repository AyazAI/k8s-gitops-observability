.PHONY: help lint-app test docker-build docker-smoke helm-lint kubeconform yamllint \
	terraform-validate gitleaks check-metrics ci kind-up kind-down kind-smoke \
	kind-bootstrap kind-loki port-forward traffic print-passwords architecture

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
YAMLLINT ?= $(shell command -v yamllint || echo $(HOME)/.local/bin/yamllint)

help:
	@echo "lint-app test docker-build docker-smoke helm-lint kubeconform yamllint"
	@echo "terraform-validate gitleaks check-metrics ci"
	@echo "kind-up kind-smoke kind-bootstrap kind-down port-forward traffic print-passwords"

lint-app:
	test -z "$$(gofmt -l app)"
	cd app && go vet ./...

test:
	cd app && go test ./...

docker-build:
	docker build -t portfolio-sample:dev app

docker-smoke:
	scripts/docker-smoke.sh

helm-lint:
	helm repo add grafana https://grafana.github.io/helm-charts --force-update
	helm repo update grafana
	helm lint charts/portfolio-sample -f charts/portfolio-sample/values.yaml -f charts/portfolio-sample/values-dev.yaml
	helm lint charts/portfolio-sample -f charts/portfolio-sample/values.yaml -f charts/portfolio-sample/values-prod.yaml
	helm template loki-check grafana/loki --version 7.6.0 -f gitops/optional/loki-values.yaml >/dev/null
	helm template metrics-check metrics-server --repo https://kubernetes-sigs.github.io/metrics-server/ --version 3.14.0 \
		--set-string args={--kubelet-insecure-tls} >/dev/null

kubeconform:
	scripts/kubeconform.sh

yamllint:
	$(YAMLLINT) -c .yamllint.yaml .

terraform-validate:
	terraform -chdir=infra/terraform/eks fmt -check -recursive
	terraform -chdir=infra/terraform/eks init -backend=false -input=false
	terraform -chdir=infra/terraform/eks validate

gitleaks:
	gitleaks detect --source . --redact --verbose

check-metrics:
	grep -q http_requests_total charts/portfolio-sample/dashboards/portfolio-sample.json
	grep -q http_request_duration_seconds_bucket charts/portfolio-sample/dashboards/portfolio-sample.json
	grep -q kube_pod_container_status_restarts_total charts/portfolio-sample/dashboards/portfolio-sample.json
	grep -q PortfolioSampleHighErrorRate charts/portfolio-sample/templates/prometheusrules.yaml
	grep -q PortfolioSampleHighLatency charts/portfolio-sample/templates/prometheusrules.yaml
	grep -q PortfolioSamplePodCrashLoop charts/portfolio-sample/templates/prometheusrules.yaml
	python3 -m json.tool charts/portfolio-sample/dashboards/portfolio-sample.json >/dev/null

ci: lint-app test check-metrics helm-lint kubeconform yamllint terraform-validate gitleaks

kind-up:
	scripts/kind-up.sh

kind-down:
	scripts/kind-down.sh

kind-smoke:
	scripts/kind-smoke.sh

kind-bootstrap:
	scripts/kind-bootstrap.sh

kind-loki:
	@echo "Optional. Not applied by the root Application."
	kubectl apply -f gitops/optional/loki.yaml

port-forward:
	scripts/port-forward.sh

traffic:
	scripts/generate-traffic.sh

print-passwords:
	@echo -n "argocd admin: "
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
	@echo
	@echo -n "grafana admin: "
	@kubectl -n monitoring get secret grafana-admin-credentials -o jsonpath='{.data.admin-password}' | base64 -d
	@echo

architecture:
	mkdir -p /tmp/mmd
	cp docs/architecture.mmd /tmp/mmd/architecture.mmd
	docker run --rm -u "$$(id -u):$$(id -g)" -v /tmp/mmd:/data minlag/mermaid-cli:11.4.2 -i /data/architecture.mmd -o /data/architecture.png -b white
	cp /tmp/mmd/architecture.png docs/architecture.png
