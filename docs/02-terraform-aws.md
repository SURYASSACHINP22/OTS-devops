# Terraform & AWS

## What Terraform is

Terraform is an "Infrastructure as Code" tool. Instead of clicking around the AWS Console to create a server, a network, a firewall rule — you **write down what you want** in `.tf` files, and Terraform figures out how to make AWS match that description. Run `terraform apply` again later, and it only changes what actually differs from your files — it won't recreate things that already match.

Why this matters over clicking in the console:
- **Reproducible**: if this EC2 instance got deleted tomorrow, `terraform apply` rebuilds the exact same VPC/subnet/security group/instance from scratch.
- **Reviewable**: `terraform plan` shows you *exactly* what would change before you commit to it — no surprises.
- **No untracked drift**: if it's not in a `.tf` file, it's not really "yours" — see the Grafana NodePort story below for what happens when you skip this.

## The AWS resources we actually created

All in `terraform/*.tf`, region `ap-south-1` (Mumbai):

| Resource | File | What it's for |
|---|---|---|
| VPC (`10.0.0.0/16`) | `vpc.tf` | A private network boundary in AWS — everything else lives inside it |
| Public subnet | `subnet.tf` | A slice of the VPC that has internet access |
| Internet Gateway | `internet_gateway.tf` | The actual door between the VPC and the internet |
| Route table | `route_table.tf` | Tells traffic "how to get out" — points `0.0.0.0/0` at the Internet Gateway |
| Security Group | `security_group.tf` | The firewall — see below |
| SSH key pair | `key_pair.tf` | Lets you SSH into the instance without a password |
| EC2 instance | `ec2.tf` | The actual server — `t3.medium`, Ubuntu 24.04 |
| Elastic IP | `eip.tf` | A permanent public IP address (see below — this solved a real recurring problem) |

## The Security Group — your firewall rules

Every port is closed by default; each `ingress` block in `security_group.tf` explicitly opens one:

| Port | Open to | Why |
|---|---|---|
| 22 (SSH) | Everyone (`0.0.0.0/0`) | Needed to manage the server at all |
| 80, 443 (HTTP/HTTPS) | Everyone | The app and its TLS cert need to be publicly reachable |
| 8080 (Jenkins) | Only your current IP (`jenkins_admin_cidr`) | Jenkins auth is meant for one operator, not the whole internet |
| 31123 (Grafana) | Only your current IP | Same reasoning |

**Why Jenkins/Grafana are IP-restricted but the app isn't**: the app is the actual product — it's *supposed* to be public. Jenkins and Grafana are operator tools; there's no reason a stranger on the internet should even be able to attempt a login.

**The recurring annoyance this caused**: your home/mobile ISP hands out a new IP address periodically. Every time that happened, the SG rule for 8080/31123 pointed at a now-stale IP, and Jenkins/Grafana looked "down" until we updated `jenkins_admin_cidr` and ran `terraform apply` again. `scripts/start-session.sh` now automates detecting and fixing this every time you start a session.

## Why we attached an Elastic IP

By default, AWS gives an EC2 instance a normal public IP that's temporarily borrowed from a shared pool. **Every time the instance stops** (which happens automatically when you resize it, e.g. our `t3.small → t3.medium` change), AWS takes that IP back and hands out a brand new one on restart.

This actually happened to us multiple times in one session — the server's IP changed from `3.111.187.147` → `13.201.10.58` → `13.203.126.12`, breaking the SG rules and any bookmarked URLs each time.

An **Elastic IP** is different: you reserve it permanently under your own AWS account, then attach it to whichever instance you want. It survives stops/restarts/resizes because it belongs to *you*, not to the instance's lifecycle. `13.203.126.12` is now permanently yours — no more IP churn.

**Cost note**: AWS charges a small hourly fee for an Elastic IP *only if it's reserved but not attached to a running instance*. Since ours is attached to a running instance, it's free.

## Why `t3.medium`, not `t3.small`

We started on `t3.small` (2 vCPU, 2GB RAM) to keep costs minimal. It **actually crashed** — the box became so memory-starved running Jenkins + Docker + k3s + the full monitoring stack simultaneously that even SSH stopped responding, for over 12 hours until we noticed and resized it. `t3.medium` (4GB RAM) fixed this. Lesson: on a single-box setup running this many services at once, 2GB genuinely isn't enough — this wasn't over-provisioning, it was a real, observed failure.

## Why k3s instead of AWS EKS (see also doc 5)

This is a cost decision that shapes the whole project. A managed EKS cluster's control plane alone costs **~$73/month while it exists, even completely idle** — before you add worker nodes, a load balancer, or a NAT Gateway. `k3s` is free software that runs *on* the EC2 instance you're already paying for, and gives you the same core Kubernetes experience (Deployments, Services, Ingress, Helm) for a portfolio/learning project. If this were a real company's production workload with a budget for it, EKS would likely be the better choice for its managed reliability — but for learning purposes on a personal budget, that tradeoff doesn't make sense.

## Reading a Terraform plan

`terraform plan` output uses three symbols:
- `+` — will be created
- `~` — will be changed in-place (usually safe, no downtime)
- `-` — will be destroyed

Before ever running `terraform apply`, always read the plan output and make sure nothing you care about shows a `-` unexpectedly.
