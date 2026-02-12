---
name: datadog
description: Query logs, metrics, monitors, and dashboards from Datadog. Search logs, check alert status, and investigate incidents.
---

# Datadog Monitoring

This skill provides access to Datadog for monitoring, logging, and alerting. **Use the `pup` CLI** (DataDog/pup) as the primary tool. Fall back to the API directly only for features pup doesn't cover yet.

## Setup

### pup CLI (preferred)

pup is installed via `install.sh`. Authenticate with OAuth2 or API keys:

```bash
# OAuth2 (preferred — browser-based, auto-refreshing tokens)
export DD_SITE="us3.datadoghq.com"
pup auth login

# Or API keys (fallback)
export DD_API_KEY="your-api-key"
export DD_APP_KEY="your-application-key"
export DD_SITE="us3.datadoghq.com"
```

Verify: `pup auth status` or `pup test`

### API fallback

For features pup doesn't cover, use curl with API keys:

```bash
export DD_API_KEY="your-api-key"
export DD_APP_KEY="your-application-key"
export DD_SITE="us3.datadoghq.com"
```

## When to Use

Use this skill when the user:
- Asks about logs, errors, or application behavior
- Wants to check monitor/alert status
- Needs to investigate an incident
- Asks about metrics or performance
- Mentions "Datadog" or monitoring

## pup CLI Reference

Output formats: `pup <command> -o json|table|yaml` (default: json). Use `-y` to skip confirmation on destructive ops.

### Logs

```bash
pup logs search --query="service:my-service status:error" --from="1h"
pup logs list --query="status:error" --from="30m"
pup logs aggregate --query="service:api" --from="1d"
```

### Monitors (Alerts)

```bash
pup monitors list
pup monitors get 12345678
pup monitors search --query="status:Alert"
```

### Metrics

```bash
pup metrics query --query="avg:system.cpu.user{*}" --from="1h"
pup metrics search --query="avg:system.cpu.user{*}" --from="1h"
pup metrics list --filter="system.*"
pup metrics get METRIC_NAME
```

### Dashboards

```bash
pup dashboards list
pup dashboards get abc-123-def
pup dashboards url abc-123-def
```

### Incidents

```bash
pup incidents list
pup incidents get abc-123-def
pup incidents attachments abc-123-def
```

### Events

```bash
pup events list --from="1d"
pup events search --query="source:my-service" --from="1h"
```

### SLOs

```bash
pup slos list
pup slos get abc-123
```

### Traces (APM)

```bash
pup traces search --query="service:api" --from="1h"
pup apm services
pup apm dependencies --service=api
pup apm flow-map --service=api
```

### Infrastructure

```bash
pup infrastructure hosts list
pup tags list
pup tags get HOSTNAME
```

### Security

```bash
pup security rules list
pup security signals list --from="1d"
pup security findings search --query="status:critical"
```

### Other Commands

```bash
pup on-call teams                    # On-call team management
pup cases search --query="status:open"  # Case management
pup error-tracking issues search     # Error tracking
pup service-catalog list             # Service catalog
pup audit-logs search --from="1d"    # Audit logs
pup usage summary                    # Usage metering
pup cost projected                   # Cost management
pup synthetics tests list            # Synthetic tests
pup downtime list                    # Scheduled downtimes
pup cicd pipelines list              # CI/CD visibility
```

## API Fallback

pup covers ~45% of Datadog APIs. For features it doesn't support (profiling, containers, processes, session replay, DORA metrics, etc.), fall back to the API directly.

Base URL: `https://api.$(printenv DD_SITE)/api/v1` or `v2`

```bash
# Example: API endpoint not covered by pup
curl -s "https://api.$(printenv DD_SITE)/api/v2/ENDPOINT" \
  -H "DD-API-KEY: $(printenv DD_API_KEY)" \
  -H "DD-APPLICATION-KEY: $(printenv DD_APP_KEY)"
```

## Log Query Syntax

Works in both `pup logs search --query=` and API calls:

| Operator | Example | Description |
|----------|---------|-------------|
| AND | `service:api status:error` | Both conditions (implicit) |
| OR | `status:error OR status:warn` | Either condition |
| NOT | `-status:debug` | Exclude matches |
| Wildcard | `service:api-*` | Pattern matching |
| Range | `@duration:>1000` | Numeric comparisons |
| Exists | `@http.url:*` | Field exists |

Common filters: `service:name`, `status:error|warn|info|debug`, `@http.status_code:500`, `host:hostname`, `env:production`

## Hawk/Scout Scan Metrics

Hawk scan jobs emit structured log entries containing `@scan_metrics` and `@scan_progress` fields. These are **log-based** (not Datadog custom metrics) — query them via `pup logs search`.

### Querying scan metrics

```bash
# Get scan metrics for a specific job (use --limit 1000 --sort asc for chronological history)
pup logs search \
  --query="inspect_ai_job_id:<JOB_ID> @scan_metrics.tasks_scanning:*" \
  --from="7d" --limit 1000 --sort asc -o json

# Note: default limit is 10. Use --limit 1000 to get more entries.
# Logs are emitted every ~6 seconds by inspect_scout.
# To cover the full timeline, query both --sort asc (oldest 1000) and --sort desc (newest 1000).
```

### Available fields

**`@scan_metrics.*`** (from `inspect_scout.ScanMetrics`):

| Field | Description |
|-------|-------------|
| `@scan_metrics.task_count` | Total async worker tasks |
| `@scan_metrics.tasks_idle` | Workers doing nothing |
| `@scan_metrics.tasks_parsing` | Workers parsing transcript files |
| `@scan_metrics.tasks_scanning` | Workers running scanners (making API calls) |
| `@scan_metrics.buffered_scanner_jobs` | Jobs buffered waiting to be scanned |
| `@scan_metrics.completed_scans` | Total completed scan operations |
| `@scan_metrics.memory_usage` | Process memory (RSS/USS) in bytes |
| `@scan_metrics.process_count` | Number of OS processes |
| `@scan_metrics.batch_pending` | Pending batch API requests |
| `@scan_metrics.batch_failures` | Failed batch API requests |
| `@scan_metrics.batch_oldest_created` | Timestamp of oldest pending batch |

**`@scan_progress.*`**:

| Field | Description |
|-------|-------------|
| `@scan_progress.completed` | Number of completed scans |
| `@scan_progress.total` | Total scans expected |
| `@scan_progress.percent` | Completion percentage |

### Common tags for filtering

- `inspect_ai_job_id:<JOB_ID>` — the scan run ID
- `inspect_ai_job_type:scan`
- `inspect_ai_created_by:<user>`
- `kube_job:<JOB_ID>`
- `service:runner`

### Container-level metrics

Standard Datadog container metrics are also available, tagged by `kube_job:<JOB_ID>`:

```bash
pup metrics query --query="avg:container.pid.thread_count{kube_job:<JOB_ID>}" --from="24h"
pup metrics query --query="avg:container.cpu.usage{kube_job:<JOB_ID>}" --from="24h"
pup metrics query --query="avg:container.memory.usage{kube_job:<JOB_ID>}" --from="24h"
```

## Notes

- Datadog site: `us3.datadoghq.com`
- API rate limits apply — be mindful of query frequency
- Log queries return max 1000 results per request; use pagination for more
- Monitor status values: OK, Alert, Warn, No Data
