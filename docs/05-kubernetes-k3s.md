# Kubernetes & k3s

## The problem Kubernetes solves

Docker runs one container. But real apps need: restarting a crashed container automatically, replacing a container with a new version *without downtime*, giving it persistent storage that survives a restart, and controlling exactly what network traffic can reach it. Kubernetes ("k8s" — the "8" replaces 8 letters between the K and the s) is the system that manages all of that, following rules you write down rather than commands you run by hand.

**k3s** is a lightweight, single-binary distribution of real Kubernetes, built by Rancher specifically for resource-constrained environments (edge devices, small servers, exactly our single-EC2-instance situation). It's not a "toy" or a simulation — it's the genuine Kubernetes API, just packaged smaller. See [doc 2](02-terraform-aws.md) for why we chose it over AWS's managed EKS.

## The core building blocks, explained through our actual objects

### Pod
The smallest unit Kubernetes runs — one or more containers that always live and move together. Ours is one container (the Django app). You never create a Pod directly in a real setup; something else manages it for you (see Deployment, below).

```bash
kubectl get pods -n ots
# ots-django-app-5b47c9d98c-6c4n7   1/1   Running
```

### Namespace
A way to keep groups of objects separate within one cluster — like folders. We use four: `ots` (the app), `monitoring` (Prometheus/Grafana/Loki), `ingress-nginx`, `cert-manager`. Nothing technical stops them from all being in one namespace — it's purely for organization and so `kubectl get pods -n ots` shows just what you care about.

### Deployment
You almost never manage Pods directly — you describe a Deployment ("I want 1 replica of this image running"), and Kubernetes creates and manages the Pod(s) for you. Critically, a Deployment is what makes **rolling updates** possible:

When Jenkins deploys a new image tag, the Deployment doesn't kill the old Pod and start a new one — it starts the **new** Pod *first*, waits until it reports healthy, and only *then* removes the old one. Our chart sets `maxUnavailable: 0`, meaning "never let the number of healthy pods drop below what I already have" — i.e., zero tolerance for downtime during a deploy.

**We didn't just configure this and hope** — we proved it, by deliberately deploying a broken image while polling the live app every second. Every single request still succeeded, because Kubernetes correctly refused to remove the old healthy Pod until a replacement was ready (which, since the new image was broken, never happened — so it rolled back instead).

### Service
Pods get replaced constantly (crashes, deploys) and each one gets a new internal IP address every time. A Service gives you one **stable** address that always routes to whichever Pod is currently healthy — like a phone number that always reaches "whoever's on call" rather than one specific person. Our `ots-django-app` Service always points at the current, healthy Pod, however many times it's been replaced.

### PersistentVolumeClaim (PVC)
By default, anything a container writes to disk vanishes the moment that container is replaced — which would be disastrous for a SQLite database. A PVC requests real, durable storage from the cluster that survives Pod restarts/replacements. k3s ships with a default storage backend (`local-path-provisioner`) that just uses a folder on the EC2 instance's own disk. Our chart mounts a PVC at `/app/data`, and the Django app's SQLite file lives there.

**We verified this for real**, not just by reading the YAML: deleted the running pod outright, waited for its replacement, and confirmed a test database record was still there.

### Ingress
Covered fully in [doc 8](08-ingress-tls.md) — the rule that says "traffic for this hostname should go to this Service," plus (via cert-manager) automatic HTTPS.

## A bug we hit that's worth understanding: `subPath` and file-vs-directory ambiguity

Early on, we considered mounting the PVC as a single file (`subPath: db.sqlite3`) directly where Django expects its database. We backed off this approach: if that exact path doesn't already exist inside the volume, Kubernetes has to *guess* whether to create a file or a directory there, and it isn't reliable. Instead we mount the PVC as a whole **directory** (`/app/data`) and made Django's database path configurable via an environment variable (`SQLITE_DB_PATH`) — Django itself then creates the actual file the first time it connects, which is unambiguous.

## A bug we hit that looks like a Kubernetes problem but is actually a Django one: `ALLOWED_HOSTS`

After deploying, the app kept crash-looping even though the container logs showed it starting up fine. The cause: Kubernetes's health checks (`readinessProbe`/`livenessProbe`) hit the Pod via its **internal Pod IP**, not any real hostname — and Django's `ALLOWED_HOSTS` setting rejects requests whose `Host` header doesn't match an approved list, returning `HTTP 400`. Kubernetes read the repeated 400s as "this container is unhealthy" and kept killing/restarting it. Fixed by setting `DJANGO_ALLOWED_HOSTS=*` for this internal, cluster-only context — a good reminder that Kubernetes failures are sometimes actually application-config failures wearing a Kubernetes costume.

## Handy commands

```bash
export KUBECONFIG=/home/ubuntu/.kube/config     # already set for the ubuntu user

kubectl get pods -n ots                          # what's running
kubectl logs -n ots deploy/ots-django-app        # see its output
kubectl describe pod -n ots <pod-name>           # deep diagnostic info, incl. recent events
kubectl exec -n ots deploy/ots-django-app -- bash   # get a shell inside the running container
```
