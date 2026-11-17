# PortfolioSamplePodCrashLoop

## Meaning

kube-state-metrics reports a container in the `portfolio-sample` namespace waiting with reason `CrashLoopBackOff` for 2 minutes.

```promql
kube_pod_container_status_waiting_reason{namespace="portfolio-sample",reason="CrashLoopBackOff"} > 0
```

## What to check

1. `kubectl -n portfolio-sample get pods`
2. `kubectl -n portfolio-sample describe pod <pod>`
3. `kubectl -n portfolio-sample logs <pod> --previous` when a previous container exists.
4. The container runs as UID 65532 with a read-only root filesystem and an emptyDir mounted at `/tmp`. A crash after a securityContext change usually shows up as a permission or filesystem error in those logs.
5. Confirm the image `portfolio-sample:dev` was loaded into the kind node. The chart does not pull from a public registry.

## Notes

This alert does not fire while the sample pods stay up. The alerts page can show it inactive.
