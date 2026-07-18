# Architecture

## The one-picture version

```
                              Internet
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
          Elastic IP: 13.203.126.12   nip.io DNS (13.203.126.12.nip.io)
                    │                           │
        ┌───────────▼───────────────────────────▼───────────┐
        │           EC2 instance (t3.medium, 4GB RAM)         │
        │           Ubuntu 24.04, ap-south-1 (Mumbai)          │
        │                                                      │
        │   Docker daemon ──── Jenkins (CI/CD)                 │
        │                                                      │
        │   k3s (single-node Kubernetes)                       │
        │    ├─ namespace: ots           → your Django app     │
        │    ├─ namespace: monitoring    → Prometheus/Grafana/Loki
        │    ├─ namespace: ingress-nginx → the traffic router  │
        │    └─ namespace: cert-manager  → HTTPS certificates  │
        └──────────────────────────────────────────────────────┘
```

Everything — Jenkins, Docker, and the entire Kubernetes cluster — runs on **one single EC2 instance**. That's a deliberate simplification for a learning project: real production setups would spread this across multiple machines, but one machine is enough to genuinely learn every layer of the stack without paying for a fleet of servers.

## How the pieces on that one server actually talk to each other

It looks like "one server," but internally it's several independent processes talking to each other over local sockets and APIs — worth understanding, because it explains *why* several of the bugs we hit happened.

```
┌─────────────────────────── the EC2 instance ───────────────────────────┐
│                                                                          │
│  Jenkins (a Java process)                                              │
│      │ shells out to the `docker` CLI                                  │
│      ▼                                                                  │
│  Docker daemon (/var/run/docker.sock) ── builds/stores images          │
│                                                                          │
│  Jenkins also shells out to `kubectl` / `helm`                         │
│      │ reads ~/.kube/config → talks to https://127.0.0.1:6443          │
│      ▼                                                                  │
│  k3s API server ── the "front desk" for the whole cluster.             │
│  Every kubectl/helm command is really just: "here's the state          │
│  I want" sent to this API. Nothing talks to Pods directly.             │
│      │                                                                  │
│      ▼                                                                  │
│  k3s's own controllers notice the desired state changed and act:       │
│   • kubelet starts/stops actual containers, via containerd             │
│     (k3s bundles its OWN containerd — a separate image store from      │
│     Docker's, which is exactly why `docker save | k3s ctr images       │
│     import` is a real, necessary step, not a formality)                │
│   • kube-proxy configures networking (iptables rules) so a Service's   │
│     stable IP actually reaches whichever Pod is currently healthy      │
│                                                                          │
│  ingress-nginx and cert-manager aren't special/built-in — they're      │
│  just more Pods, running in their own namespaces, that happen to       │
│  watch the API server for Ingress/Certificate objects and act on them  │
└──────────────────────────────────────────────────────────────────────┘
```

**Two concrete things this explains, that we actually hit:**
- Jenkins needed its **own** copy of `~/.kube/config` (separate from the `ubuntu` user's) before it could run `helm upgrade` at all — because "talking to k3s" always goes through that one config file, and Jenkins runs as its own Linux user (see [doc 3](03-ansible.md)).
- Pods inside the cluster address each other by **Kubernetes DNS names**, not IPs — e.g. our Grafana datasource points at `http://loki.monitoring.svc.cluster.local:3100`, which reads as "the `loki` Service, in the `monitoring` namespace." This works because k3s runs its own internal DNS server (CoreDNS) resolving exactly that naming pattern — it's not a coincidence or a made-up hostname.

## Why two separate GitHub repos?

- **`OTS-devops`** (infrastructure) — Terraform, Ansible, the Jenkinsfile *reference copy*. Lives on your WSL laptop.
- **`ONline_testing_app_django`** (the actual app) — Django code, the Dockerfile, the Helm chart, and the **real, live Jenkinsfile** that Jenkins actually executes. Lives on the EC2 server itself.

The reasoning: application code changes constantly (every feature, every bugfix). Infrastructure changes rarely (you don't touch Terraform every day). Keeping them apart means a routine app commit never risks touching Terraform state, and infra changes never get buried in app commit history.

**Important quirk this causes**: Jenkins can only see files from whatever repo it's currently building (`ONline_testing_app_django`). That's why the *real* Jenkinsfile and the Helm chart both had to live in the app repo, not here — Jenkins has no way to reach into `OTS-devops` mid-build. The copy of the Jenkinsfile in `OTS-devops/jenkins/` is just a reference so you can read it without SSHing into the server.

## How a request actually flows through the system

Say you open `https://13.203.126.12.nip.io/` in a browser:

1. Your browser resolves `13.203.126.12.nip.io` via nip.io's DNS → gets back `13.203.126.12` (the Elastic IP)
2. Connects to that IP on port 443 (HTTPS)
3. Hits **ingress-nginx**, which is listening on that port directly on the EC2 host (see [Ingress & TLS](08-ingress-tls.md) for why)
4. ingress-nginx terminates the TLS connection using the Let's Encrypt certificate `cert-manager` obtained automatically, and reads the `Ingress` rule to figure out where to send the request
5. Forwards it to the **Service** `ots-django-app` (a stable internal address inside the cluster)
6. The Service forwards it to whichever **Pod** is currently running and healthy — right now, one pod running your Django app via `manage.py runserver`
7. Your Django code (in `OTS/`, `testingApp/`) handles the request and returns a response, which travels back the same path

## How a code change actually reaches production

```
You push code to ONline_testing_app_django
        ↓
Jenkins detects it (you click "Build Now" — no auto-trigger configured yet)
        ↓
Runs tests, lint, security scans, builds a Docker image
        ↓
Loads that image directly into k3s (no external registry)
        ↓
helm upgrade — tells Kubernetes "run this new image instead"
        ↓
Kubernetes starts a new Pod, waits until it's healthy,
ONLY THEN removes the old Pod (zero-downtime, see doc 5)
        ↓
If anything in that chain fails, Helm automatically rolls back
        ↓
Jenkins curls the app to confirm it's actually responding
```

Every arrow in that diagram is a real, working step in this project — see [Jenkins & CI/CD](07-jenkins-cicd.md) for the details of each stage.

## Where each tool's config actually lives

| Tool | Config location |
|---|---|
| Terraform | `OTS-devops/terraform/*.tf` |
| Ansible | `OTS-devops/ansible/roles/*/tasks/main.yml`, run via `ansible/playbooks/site.yml` |
| Jenkins pipeline | `ONline_testing_app_django/Jenkinsfile` (real), `OTS-devops/jenkins/Jenkinsfile` (reference copy) |
| Helm chart for the app | `ONline_testing_app_django/helm/ots-django-app/` |
| Monitoring stack config | `OTS-devops/ansible/roles/monitoring/files/*.yml` |
| Ingress/TLS config | `OTS-devops/ansible/roles/ingress/`, `ONline_testing_app_django/helm/ots-django-app/templates/ingress.yaml` |
