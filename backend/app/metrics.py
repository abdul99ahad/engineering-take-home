"""Prometheus metrics, served on /metrics and scraped by the platform team."""

from prometheus_client import Counter, Histogram

REQUESTS = Counter(
    "http_requests_total",
    "HTTP requests by route template and status.",
    ["method", "route", "status"],
)
APP_EVENTS = Counter("app_events_total", "Product events sent by the app.", ["event"])
SHARES_CREATED = Counter("shares_created", "Diary shares created by patients.")
SHARES_REVOKED = Counter("shares_revoked", "Diary shares revoked by patients.")
CLINICIAN_READS = Counter(
    "clinician_reads",
    "Doctors' diary reads by outcome: ok, not_found, error, audit_failed.",
    ["outcome"],
)
LATENCY = Histogram(
    "http_request_duration_seconds", "HTTP request duration by route template.", ["method", "route"]
)
