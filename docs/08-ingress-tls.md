# Ingress & TLS

## The problem: getting a real `https://` URL usually costs money and setup

Normally, HTTPS requires: (1) owning a domain name (~$10-15/year), (2) pointing DNS at your server, (3) obtaining and continually renewing a TLS certificate. We got all the benefits of this — a real, browser-trusted `https://` URL — for **zero cost**, using three pieces working together.

## Piece 1: `nip.io` — DNS without owning a domain

`nip.io` is a free public DNS service with one trick: `13.203.126.12.nip.io` automatically resolves to the IP address `13.203.126.12` — no configuration, no signup, it works for *any* IP address embedded in the hostname like that. This only makes sense to rely on because our IP is now an **Elastic IP** ([doc 2](02-terraform-aws.md)) that never changes — if the server's IP still churned, the "domain" would silently change out from under us too.

## Piece 2: ingress-nginx — the traffic router

An **Ingress** is a Kubernetes rule that says "requests for this hostname should go to that Service" (see [doc 5](05-kubernetes-k3s.md) for what a Service is). `ingress-nginx` is the actual software that reads those rules and does the routing — it's the thing sitting at the front door of the cluster.

**A deliberate config choice**: ingress-nginx normally exposes itself via a `NodePort` (a high, randomly-numbered port like 30080). We instead bound it directly to the host's ports 80 and 443 (`hostPort`), for two reasons: (1) those ports were already open in our Security Group since the very first Terraform apply, so no new firewall rule was needed, and (2) Let's Encrypt's domain-ownership check (below) specifically requires port 80 — it won't accept a random NodePort.

## Piece 3: cert-manager + Let's Encrypt — the actual certificate

**Let's Encrypt** is a free, automated certificate authority — the same kind of organization that issues certificates for real commercial websites, just free and automatable. **cert-manager** is the Kubernetes add-on that talks to Let's Encrypt on your behalf: it requests a certificate, proves you actually control the domain, and automatically renews it before expiry (real Let's Encrypt certs expire every 90 days).

### How "proving you own the domain" works here (HTTP-01 challenge)

1. cert-manager asks Let's Encrypt for a certificate for `13.203.126.12.nip.io`
2. Let's Encrypt says "prove it — put this specific random file at `http://13.203.126.12.nip.io/.well-known/acme-challenge/<token>` and I'll check"
3. cert-manager automatically creates a temporary Ingress rule serving exactly that file
4. Let's Encrypt fetches it over plain HTTP (port 80 — this is *why* port 80 specifically has to be reachable), confirms the token matches, and issues the real certificate
5. cert-manager stores the certificate as a Kubernetes Secret, and ingress-nginx starts using it for HTTPS

This entire exchange happened automatically, in under a minute, the one time we set it up — you never had to click anything on Let's Encrypt's own site.

## Where this is configured

- `ansible/roles/ingress/` — installs ingress-nginx and cert-manager, and creates the `letsencrypt-prod` `ClusterIssuer` (the object that tells cert-manager *which* certificate authority and account to use)
- `ONline_testing_app_django/helm/ots-django-app/templates/ingress.yaml` — the actual Ingress rule for our app, with one annotation (`cert-manager.io/cluster-issuer: letsencrypt-prod`) that's all it takes to get automatic HTTPS for a new app

## How to verify a certificate is real (not just "looks fine in a browser")

```bash
curl -v https://13.203.126.12.nip.io/ 2>&1 | grep -E "subject:|issuer:|SSL certificate verify"
```
Look for `issuer: ... O=Let's Encrypt` and `SSL certificate verify ok` — this is `curl` doing real certificate chain validation, the same check a browser does, with no `-k`/insecure flag needed.

## A cost/rate-limit note worth knowing

Let's Encrypt's production certificate authority (what we're using) rate-limits to 5 certificates per exact domain per week. Fine for normal use (certs auto-renew well before that), but if you're experimenting a lot and hit the limit, Let's Encrypt also has a **staging** environment with much higher limits — the tradeoff is staging certificates aren't trusted by real browsers (you'd see a security warning), so it's only useful for testing that the *mechanism* works, not for anything you want to actually show off.
