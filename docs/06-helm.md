# Helm

## What Helm is

Kubernetes objects (Deployment, Service, PVC, Ingress...) are each just a YAML file. A real app usually needs several of these working together, and copy-pasting/hand-editing raw YAML for every deploy gets messy fast — especially when you want the *same* set of objects with slightly different settings each time (a different image tag on every build, for instance). Helm is Kubernetes' package manager: you define a reusable **chart** (a template for a group of related objects), and `helm install`/`helm upgrade` fills in the current values and applies everything as one atomic unit called a **release**.

Think of it like the difference between writing a fresh email every time vs. using a mail-merge template — the chart is the template, the "release" is one filled-in, sent copy.

## Our chart: `ONline_testing_app_django/helm/ots-django-app/`

```
Chart.yaml              # name + version metadata
values.yaml              # the "fill in the blanks" — image tag, ports, hostname, etc.
templates/
  deployment.yaml         # the Pod spec: image, env vars, volume mounts, health checks
  service.yaml             # stable internal address
  pvc.yaml                  # persistent storage request
  ingress.yaml               # external routing + TLS
```

`values.yaml` holds the things that change between deploys or environments — most importantly `image.tag`, which Jenkins overrides on every build:

```bash
helm upgrade --install ots-django-app helm/ots-django-app \
    --set image.tag=10 \
    --rollback-on-failure --wait --timeout 5m
```

`--set image.tag=10` overrides just that one value from `values.yaml` for this specific release, without editing the file.

## `--rollback-on-failure` — Helm's safety net

If `helm upgrade` fails (image doesn't exist, the new Pod never becomes healthy, whatever the reason), this flag makes Helm **automatically revert** to the last release that was actually working — no manual intervention needed. This is what makes our pipeline's "Deploy" stage safe to run unattended: a bad deploy self-heals instead of leaving the app broken.

We proved this works by deliberately deploying with a nonexistent image tag and watching Helm catch it and roll back on its own, with zero downtime for the app the whole time (see [doc 5](05-kubernetes-k3s.md) for the details of *why* zero downtime happened).

## A subtlety we hit: an interrupted install leaves a "stuck" release

If a `helm install --wait` gets killed mid-flight (which happened to us once, when the EC2 box itself crashed under memory pressure — see [doc 2](02-terraform-aws.md)), Helm can be left thinking an install is still "in progress," and it'll then refuse to do *anything else* with that release ("another operation is in progress"). The fix is `helm uninstall` followed by a clean re-`install` — safe for something like our monitoring stack (no data worth preserving at that layer), and worth knowing about before panicking if you ever see that exact error.

## A subtlety in a chart we depend on, not our own: `loki-stack`'s default datasource

The `grafana/loki-stack` community chart, even with its bundled Grafana explicitly turned off, still creates its own Grafana "datasource" configuration by default — which collided with `kube-prometheus-stack`'s own default datasource ("only one datasource per org can be marked as default") and crashed Grafana. The fix was one extra values setting (`grafana.sidecar.datasources.enabled: false`) once we found the actual chart option controlling it. Lesson: a chart working on day one doesn't guarantee its *defaults* are all compatible with everything else you're running — this bug was latent from the very first install and only surfaced later when Grafana happened to restart.

## Useful commands

```bash
helm list -n ots                 # what releases exist in this namespace, and their status
helm status ots-django-app -n ots  # detailed info on one release
helm rollback ots-django-app 3 -n ots  # manually go back to a specific earlier revision
helm template helm/ots-django-app  # render the chart to plain YAML WITHOUT installing anything -- great for checking your templates are valid before deploying
```
