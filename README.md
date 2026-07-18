# OTS-DevOps

Infrastructure-as-code and CI/CD for the **Online Testing System (OTS)** — a Django MCQ testing platform. This repo is the *infrastructure* half of a deliberately two-repo project:

| Repo | Contains | Lives on |
|---|---|---|
| **OTS-devops** (this repo) | Terraform, Ansible, Jenkinsfile reference copy | Your WSL laptop |
| [`ONline_testing_app_django`](https://github.com/SURYASSACHINP22/ONline_testing_app_django) | Django app code, Dockerfile, **live Jenkinsfile**, Helm chart | The EC2 instance itself |

Why split: app code changes constantly, infra changes rarely — keeping them separate means CI/CD and Terraform state never get tangled up with day-to-day app commits.

> **New to this project, or coming back after a break?** [`docs/`](docs/README.md) has one file per tool (Terraform, Ansible, Docker, Kubernetes, Helm, Jenkins, Ingress/TLS, Monitoring, Security scanning) explaining what it is, why we chose it, what we actually configured, and the real bugs we hit along the way. This README stays focused on quick reference; `docs/` is where the actual learning happens.

---

## Architecture at a glance

```
                        Internet
                            │
              ┌─────────────┴─────────────┐
              │                           │
     Elastic IP: 13.203.126.12   nip.io DNS (13.203.126.12.nip.io)
              │                           │
    ┌─────────▼─────────────────────────▼─────────┐
    │        EC2 instance (t3.medium, 4GB RAM)      │
    │        Ubuntu 24.04, ap-south-1 (Mumbai)       │
    │                                                │
    │  Docker (builds images) ── Jenkins (CI/CD)     │
    │                                                │
    │  k3s (single-node Kubernetes)                  │
    │   ├─ namespace: ots                            │
    │   │   └─ Django app (Helm chart, PVC-backed    │
    │   │       SQLite, Ingress + real Let's Encrypt │
    │   │       TLS cert)                            │
    │   ├─ namespace: monitoring                     │
    │   │   └─ Prometheus + Grafana + Loki/Promtail  │
    │   ├─ namespace: ingress-nginx                   │
    │   │   └─ ingress-nginx controller (host ports  │
    │   │       80/443 -- no NodePort needed)        │
    │   └─ namespace: cert-manager                   │
    │       └─ cert-manager + Let's Encrypt issuer   │
    └────────────────────────────────────────────────┘
```

**Why these specific choices** (each one was a deliberate cost/complexity tradeoff, not a default):
- **k3s, not AWS EKS** — a managed EKS control plane costs ~$73/month *while it exists, even idle*. k3s is free software running on the EC2 instance you're already paying for, and still gives real Deployments/Services/Ingress/Helm experience.
- **No container registry** — Jenkins builds the Docker image and loads it straight into k3s's local image store (`docker save | k3s ctr images import`). Since Jenkins and k3s run on the same box, a registry (Docker Hub, ECR) would just be extra cost and credentials for no benefit.
- **nip.io instead of a real domain** — free wildcard DNS service that resolves `<ip>.nip.io` to `<ip>` with zero setup. Combined with an Elastic IP (stable forever) and cert-manager, this gets a **real, browser-trusted HTTPS certificate** from Let's Encrypt without ever buying a domain.
- **SQLite, not Postgres** — deliberately kept simple while learning; the SQLite file lives on a Kubernetes PersistentVolumeClaim, so it survives pod restarts (verified by actually deleting the running pod and confirming data survived).

---

## Quick start after a break

```bash
cd OTS-devops
./scripts/start-session.sh
```

This one script: loads your SSH key into an agent (asks for your passphrase once), detects if your IP changed and automatically fixes the Jenkins/Grafana firewall rule via Terraform if so, verifies SSH and Jenkins are reachable, and prints every URL/command you need below.

---

## Access points

### The application (public, real HTTPS, no VPN/tunnel needed)

| What | URL |
|---|---|
| App home | `https://13.203.126.12.nip.io/` (redirects to `/OTS/`) |
| Django admin panel | `https://13.203.126.12.nip.io/admin/` |
| API docs (Swagger UI) | `https://13.203.126.12.nip.io/api/schema/swagger-ui/` |
| API docs (ReDoc) | `https://13.203.126.12.nip.io/api/schema/redoc/` |
| Raw OpenAPI schema | `https://13.203.126.12.nip.io/api/schema/` |

### Operator tools (restricted to your current IP via Security Group)

| What | URL | Credentials |
|---|---|---|
| Jenkins | `http://13.203.126.12:8080/` | Your own Jenkins account (created during setup) |
| Grafana | `http://13.203.126.12:31123/` | `admin` / password in `ansible/grafana_admin_password.txt` (gitignored, not in git) |

If your ISP has rotated your IP since you last worked on this (very common — it's happened repeatedly), these two will look "down" until `start-session.sh` fixes the SG rule — not a real outage, just a stale firewall allowlist. The app/admin/API links above are unaffected since they're public.

### Useful Grafana dashboards (Dashboards → Browse, or jump straight in)

| Dashboard | Path |
|---|---|
| Node Exporter Full (host CPU/RAM/disk/network) | `/d/rYdddlPWk/node-exporter-full` |
| Kubernetes / Compute Resources / Cluster | `/d/efa86fd1d0c121a26444b636a3f509a8/kubernetes-compute-resources-cluster` |
| Kubernetes / Compute Resources / Pod | `/d/6581e46e4e5c7ba40a07646395ef7b23/kubernetes-compute-resources-pod` |

(append the path to `http://13.203.126.12:31123`)

### Git repositories

| Repo | URL |
|---|---|
| Infra (this repo) | `https://github.com/SURYASSACHINP22/OTS-devops` |
| App code | `https://github.com/SURYASSACHINP22/ONline_testing_app_django` |

### Server access

| What | Command |
|---|---|
| SSH | `ssh -i ~/.ssh/ots-devops ubuntu@13.203.126.12` |
| App repo location on the server | `~/ONline_testing_app_django` (only on the EC2 box, not your laptop) |
| kubectl/helm on the server | `export KUBECONFIG=/home/ubuntu/.kube/config` (already set in `ubuntu`'s `.bashrc`) |

---

## The CI/CD pipeline (Jenkinsfile, lives in the app repo)

Every stage does real work — none of these are placeholders:

1. **Checkout** — pulls the app repo via SSH deploy key
2. **Install dependencies** — Python venv (kept **outside** the repo tree so later scanning stages don't accidentally scan third-party libraries)
3. **Run Django unit tests** — blocks the pipeline if they fail
4. **Lint** (flake8) — blocks the pipeline if it fails
5. **Security scans** (Bandit + Gitleaks, run in parallel) — **advisory**, reported but don't block, since gating on pre-existing issues in an existing codebase would fail nearly every build
6. **Build Docker image**
7. **Trivy image scan** — `--ignore-unfixed` so it only flags CVEs that actually have a patch available (upstream-unpatched OS package noise is filtered out)
8. **Load image into k3s** — `docker save | k3s ctr images import`, no registry
9. **Deploy** — `helm upgrade --install ... --rollback-on-failure`, so a bad deploy **automatically rolls back** to the last good release
10. **Health check** — curls the app's Service; fails the build if it's not actually responding

**Verified, not just configured**: deliberately deployed a broken image while polling the live app every second for 90+ seconds — zero downtime the entire time, and the auto-rollback kicked in exactly as designed. The original pod was never killed because Kubernetes correctly refused to remove it before a healthy replacement existed (`maxUnavailable: 0`).

---

## Monitoring

Prometheus + Grafana + Loki/Promtail, all via Helm (`kube-prometheus-stack` + `loki-stack`), trimmed resource limits to fit this box's RAM budget. 25 dashboards available out of the box (Kubernetes cluster/pod/workload views, Node Exporter Full, CoreDNS, etc.) — in Grafana, click **Dashboards** in the left sidebar to browse them; the home page itself is just Grafana's generic welcome screen, not a dashboard.

Loki collects logs from every pod automatically via Promtail; it's wired into Grafana as a datasource (Explore → select Loki).

---

## Repository structure (this repo)

```
terraform/    VPC, subnet, security groups, EC2, Elastic IP -- infra only, no software installed here
ansible/      roles: docker, jenkins, k3s, helm, ingress, monitoring
              playbooks/site.yml runs all of them, idempotently, in order
scripts/      start-session.sh -- run this every time you sit down to work
jenkins/      Jenkinsfile -- REFERENCE COPY ONLY. The real one Jenkins actually
              runs lives in the app repo (Jenkins reads it from whatever repo
              it's building). Keep this copy in sync manually after changes.
```

## What's NOT done (honest list, not aspirational)

- Postgres migration — explicitly deferred, SQLite is fine for now
- Kubernetes Dashboard / Headlamp — considered, skipped due to resource cost on this box
- SonarQube — mentioned in original goals, never actually set up
- Custom Grafana dashboards for the Django app itself (request rate/latency) — would need a Prometheus metrics endpoint added to the app; currently only infra-level dashboards exist

## Status

✅ Terraform infra, Ansible automation, Jenkins CI/CD, k3s + Helm deploy, Ingress + real TLS, monitoring stack — all built **and independently verified working**, not just deployed.
