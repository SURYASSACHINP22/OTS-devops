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

## How `ansible-playbook playbooks/site.yml` actually executes, step by step

It's not magic — four files cooperate, and it's worth knowing exactly how:

**1. `ansible.cfg`** — the settings Ansible reads before anything else:
```ini
[defaults]
inventory = inventory.ini      # where to find the list of target servers
roles_path = roles              # where to find role definitions
remote_user = ubuntu            # log in as this user
private_key_file = ~/.ssh/ots-devops   # using this SSH key
```

**2. `inventory.ini`** — the actual list of servers, grouped by name:
```ini
[ots_devops]
13.203.126.12 ansible_user=ubuntu
```
This is why the group name `ots_devops` shows up in the playbook next — it's how Ansible knows *which* servers a playbook applies to. (Since our Elastic IP means this address never changes anymore, this file basically never needs touching again — see [doc 2](02-terraform-aws.md).)

**3. `playbooks/site.yml`** — the actual playbook:
```yaml
- name: Configure OTS DevOps server
  hosts: ots_devops          # <- matches the [ots_devops] group above
  roles:
    - docker
    - jenkins
    - k3s
    - helm
    - ingress
    - monitoring
```
`hosts: ots_devops` tells Ansible "run everything below against every server in that inventory group." `roles:` is just a list, run top-to-bottom — this is *why* the order in that list matters (Docker has to exist before Jenkins can use it, k3s has to exist before Helm can deploy to it, etc.).

**4. For each role name in that list**, Ansible looks for `roles/<name>/tasks/main.yml` and runs every task in it, in order, top to bottom. For example, `roles/docker/tasks/main.yml` starts with:
```yaml
- name: Update apt cache
  apt:
    update_cache: true
  become: true
```
`apt:` here is a **module** — a pre-built, reusable unit of work Ansible ships with (there are hundreds: `apt`, `copy`, `command`, `service`, `file`...). You're not writing shell script — you're declaring "I want the apt cache updated," and the `apt` module knows how to check whether that's already true and only act if it isn't (this is where idempotency, from earlier in this doc, actually comes from — it's built into the modules, not something you have to implement yourself).

`become: true` means "run *this specific task* with `sudo`" — most tasks need it (installing packages, writing system files); a few don't (like copying a file into your own home directory).

Every single task connects over **SSH**, using the credentials from `ansible.cfg` — under the hood, Ansible is doing the equivalent of `ssh ubuntu@13.203.126.12 "sudo apt update"` for that one task, then moving to the next. Some roles' tasks also use `delegate_to: localhost` (see `roles/jenkins/tasks/main.yml`'s password-fetching step) — that means "run this one task on *your* laptop instead of the remote server," used for copying a file (like the Grafana password) back to your machine.

A role can also have a `roles/<name>/defaults/main.yml` (default values for variables that role's tasks use — e.g. `roles/jenkins/defaults/main.yml` sets `gitleaks_version`, so bumping to a newer Gitleaks release later is a one-line change, not a hunt through the tasks file) and a `roles/<name>/files/` directory (static files that get copied to the server as-is, like our Helm values files and the Let's Encrypt ClusterIssuer manifest).

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
