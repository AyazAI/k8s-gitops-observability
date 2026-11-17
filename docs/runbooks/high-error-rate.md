# PortfolioSampleHighErrorRate

## Meaning

Prometheus saw the 5xx ratio for `/api` requests on `portfolio-sample` stay above 5% for 2 minutes.

The ratio is:

```promql
sum(rate(http_requests_total{namespace="portfolio-sample",path=~"/api/.+",code=~"5.."}[5m]))
/
sum(rate(http_requests_total{namespace="portfolio-sample",path=~"/api/.+"}[5m]))
```

`namespace` is added by the Prometheus scrape. The application counter itself is labeled with `method`, `path`, and `code`.

## What to check

1. Confirm the series in Prometheus. If the ratio is empty, the ServiceMonitor is not scraping `/metrics`.
2. Read the pod logs. The process logs method, path label, status, and duration.
3. `GET /api/error` always returns 500. It exists so the error counter and this alert can be exercised. A burst of calls to that path will trip the alert. That is sample traffic, not a separate failure.
4. Compare the running image tag with the Git revision Argo CD synced.
5. Check whether the pod is restarting or hitting its memory limit.

## Notes

This sample has no production traffic and no customer impact to report.
