# OTS-DevOps — Learning Docs

You built this project without much prior DevOps experience — these docs exist so you can come back later, open one file at a time, and actually understand *what* each tool does, *why* we chose it, and *what specifically* we configured for OTS. Read them in order the first time; after that, treat each one as a standalone reference.

| # | Doc | What it covers |
|---|---|---|
| 1 | [Architecture](01-architecture.md) | The whole system in one picture, and how the pieces connect |
| 2 | [Terraform & AWS](02-terraform-aws.md) | What "infrastructure as code" means, every AWS resource we created and why |
| 3 | [Ansible](03-ansible.md) | Server configuration automation, idempotency, the roles we wrote |
| 4 | [Docker](04-docker.md) | Containers, images, the Dockerfile, how the image gets into Kubernetes |
| 5 | [Kubernetes & k3s](05-kubernetes-k3s.md) | Pods/Deployments/Services/Namespaces/PVCs — the core concepts, explained with our actual objects |
| 6 | [Helm](06-helm.md) | Kubernetes' package manager, chart structure, our app's chart |
| 7 | [Jenkins & CI/CD](07-jenkins-cicd.md) | What a CI/CD pipeline is, every stage in our Jenkinsfile explained |
| 8 | [Ingress & TLS](08-ingress-tls.md) | How your app gets a real domain and a real HTTPS certificate for free |
| 9 | [Monitoring](09-monitoring.md) | Prometheus/Grafana/Loki — metrics vs. logs, what we're watching |
| 10 | [Security scanning](10-security-scanning.md) | Bandit/Gitleaks/Trivy — what each one actually catches |
| 11 | [Command reference](11-command-reference.md) | Every real command used across this project, organized by tool |

Each doc follows the same shape: **what is this tool** (in general) → **why we're using it here** (the actual reasoning, including cost tradeoffs) → **what we configured** (the real files/settings in this project) → **key things that went wrong and what that taught us** (real bugs we hit, not hypothetical ones).
