# Ansible

## What Ansible is

Terraform creates *infrastructure* (a VPC, a server, a firewall rule) but has no idea how to install software *onto* that server. That's Ansible's job: it connects over SSH and runs a checklist of setup steps — install this package, start this service, write this config file. The checklist is written in YAML ("playbooks" made of "roles"), not a shell script, which gives you one crucial property: **idempotency**.

## Idempotency — the most important Ansible concept

An idempotent operation gives the same end result no matter how many times you run it. `apt install docker` run twice doesn't install Docker twice — the second run just confirms it's already there and does nothing. This matters enormously in practice: it means you can re-run the *entire* setup playbook any time (after a reboot, after adding a new role, after fixing a bug) without worrying it'll break something that already works.

**We learned this the hard way, twice**, from bugs that broke idempotency:
1. A task checking "did removing this Docker volume fail because it doesn't exist?" compared against the string `'No such volume'` — but Docker's real message uses lowercase `'no such volume'`. The mismatch made a harmless "already removed" case look like a real failure on every re-run.
2. A task waited for Jenkins's *initial setup password file* to appear — but that file only exists before you've completed the setup wizard once. Every re-run after that legitimately has no such file, and the task failed instead of just skipping gracefully.

Both got fixed by making the tasks properly check "has this already happened?" instead of assuming a fresh install every time.

## The roles we wrote (`ansible/roles/`)

Each role is a self-contained checklist for one piece of software. `ansible/playbooks/site.yml` runs them all, in this order:

| Role | Installs | Why this order |
|---|---|---|
| `docker` | Docker Engine + Compose | Needed before Jenkins can build/run containers |
| `jenkins` | Jenkins, Java, security scan tools (Bandit's deps, Gitleaks, Trivy) | The CI/CD server |
| `k3s` | k3s itself, kubeconfig for both the `ubuntu` and `jenkins` users | The Kubernetes cluster — needs Docker's group membership already set up |
| `helm` | The `helm` CLI | Needed to deploy anything onto k3s |
| `ingress` | ingress-nginx, cert-manager, the Let's Encrypt ClusterIssuer | Needs Helm and k3s already running |
| `monitoring` | Prometheus/Grafana (`kube-prometheus-stack`) + Loki/Promtail (`loki-stack`) | Same — needs Helm and k3s |

## A subtlety that caused real bugs: two separate Linux users

Jenkins doesn't run as your `ubuntu` user — it runs as its own system user, literally called `jenkins`, for security isolation (so a compromised Jenkins job can't automatically do everything your own login could). This tripped us up twice:

- `jenkins` has its **own** `~/.ssh/known_hosts` file, completely separate from `ubuntu`'s. Trusting GitHub's SSH key as `ubuntu` does nothing for Jenkins — it had to be added again, explicitly, for the `jenkins` user.
- Adding `jenkins` to the `docker` group via `usermod` doesn't take effect on an *already-running* Jenkins process — Linux only reads a process's group memberships when it starts. We had to explicitly restart the Jenkins service after changing its groups.

## Why this project uses Ansible *and* Terraform, not just one

They solve different problems and deliberately don't overlap: Terraform only touches AWS-level resources (VPC, EC2, security groups) and is never allowed to install software or run app code. Ansible only touches the *inside* of the already-existing server and is never allowed to create/destroy AWS resources. This separation means you always know which tool to look in for a given kind of change.

## How to actually run it

```bash
cd ansible
eval $(ssh-agent -s)
ssh-add ~/.ssh/ots-devops
ansible-playbook playbooks/site.yml
```

Safe to run any time, even if nothing changed — idempotency means it'll just confirm everything's already correct and report `changed=0` for anything that didn't need touching.
