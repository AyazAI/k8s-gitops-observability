# PortfolioSampleHighLatency

## Meaning

The 95th percentile latency of `/api` requests stayed above 0.5 seconds for 2 minutes.

```promql
histogram_quantile(0.95,
  sum by (le) (
    rate(http_request_duration_seconds_bucket{namespace="portfolio-sample",path=~"/api/.+"}[5m])
  )
)
```

Buckets on `http_request_duration_seconds` are 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, and 2.5s.

## What to check

1. Split the histogram by `path`. `/api/echo` accepts `sleep_ms` from 0 to 2000 and waits that long before responding. Calls with `sleep_ms` above 500 move the p95 above the threshold. That delay is in the handler, not in the cluster network.
2. Check CPU throttling and the pod memory limit if latency is high without `sleep_ms`.
3. Compare the Git revision Argo CD deployed with the chart values for the resource requests.

## Notes

This sample has no production latency baseline.
