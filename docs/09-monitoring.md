# Monitoring: Prometheus, Grafana, Loki

## Two different questions, two different tools

"Is the CPU usage high right now?" is a **metrics** question — a number, tracked over time. "What error message did the app print at 3:47pm?" is a **logs** question — full text, searchable. These need genuinely different tools:

- **Prometheus** — collects and stores metrics (numbers over time: CPU%, memory, request counts)
- **Grafana** — the dashboard/visualization layer on top of Prometheus (and Loki) — the thing you actually look at
- **Loki** — collects and stores logs (the actual text output of every pod), designed to feel like "Prometheus, but for logs"
- **Promtail** — the agent that runs on the server and ships logs into Loki (Prometheus's equivalent job is done by tools installed alongside it, like `node-exporter`, below)

## How metrics actually get from a pod into Grafana

```
Your app / a system component
        ↓  (exposes a /metrics HTTP endpoint with current numbers)
Prometheus (scrapes /metrics on a timer, stores the history)
        ↓
Grafana (queries Prometheus, draws a graph)
```

We're not scraping the Django app's own metrics yet (that would need a library like `django-prometheus` added to the app) — currently we're watching **infrastructure**-level metrics: `node-exporter` (CPU/RAM/disk of the EC2 host itself) and `kube-state-metrics` (the health of Kubernetes objects — how many pods are running, etc.).

## How logs get from a pod into Grafana

```
Your app writes to stdout (e.g. "GET /OTS/ 200")
        ↓
Promtail (runs on the node, tails every container's log output)
        ↓
Loki (stores it, indexed by labels like namespace/pod name)
        ↓
Grafana → Explore → select Loki as the data source → search
```

## Why we deploy this via `kube-prometheus-stack` and `loki-stack` rather than installing each piece separately

`kube-prometheus-stack` is a Helm chart that bundles Prometheus + Grafana + the operator that manages them + sensible default dashboards, all pre-wired to work together — installing each piece by hand and connecting them manually is a lot of tedious, error-prone config. Same reasoning for `loki-stack` (Loki + Promtail together).

## Real bugs we hit, worth understanding

**Resource limits matter on a small box.** We deliberately set low CPU/memory requests/limits on every component in `ansible/roles/monitoring/files/*.yml` — without this, our first attempt to run the *entire* monitoring stack alongside Jenkins/Docker/k3s on a 2GB box actually exhausted memory badly enough to hang the whole server (see [doc 2](02-terraform-aws.md)).

**A dashboard too large to `kubectl apply` normally.** We imported the community "Node Exporter Full" dashboard as a ConfigMap (Grafana auto-discovers ConfigMaps labeled `grafana_dashboard: "1"`). Plain `kubectl apply` stores a complete copy of whatever you're applying inside an annotation, for diffing next time — and this dashboard's JSON is large enough to blow past Kubernetes' 256KB annotation size limit. Fixed with `kubectl apply --server-side`, which uses a different mechanism that doesn't have this limit.

**A chart's own default config conflicting with another chart's** — covered in [doc 6](06-helm.md)'s `loki-stack` story. Worth re-reading here too since it specifically broke Grafana.

## Where to actually look

- Grafana: `http://13.203.126.12:31123/` (see main README for credentials)
- Click **Dashboards** in the left sidebar — the home page is just Grafana's generic welcome screen, not a dashboard itself
- Good starting points: **Node Exporter Full** (host-level resource usage) and **Kubernetes / Compute Resources / Cluster** (what's actually running and how much it's using)
- **Explore** (left sidebar) → select the **Loki** data source → to search raw logs
