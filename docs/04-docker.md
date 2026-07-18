# Docker

## What a container actually is

A container packages your application together with everything it needs to run (Python, your dependencies, your code) into one portable unit. The key idea: it runs the **same way everywhere** — your laptop, the EC2 server, anywhere — because it doesn't depend on whatever happens to already be installed on the host machine. It's not a full virtual machine (much lighter weight, starts in ~seconds), but it is isolated from the host's own filesystem and processes.

**Image vs. container** — a distinction that trips a lot of people up: an **image** is the packaged, frozen blueprint (built once by `docker build`). A **container** is a running instance of that image (started by `docker run`, or in our case, by Kubernetes). You can start many containers from the same image.

## Our Dockerfile (`ONline_testing_app_django/Dockerfile`)

```dockerfile
FROM python:3.12-slim              # Start from a minimal official Python image
RUN apt-get install build-essential gcc   # Needed to compile some Python packages
COPY requirements.txt .
RUN pip install -r requirements.txt       # Install Django and everything else
COPY . .                            # Copy in your actual application code
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]   # What runs when the container starts
```

`python:3.12-slim` (rather than the full `python:3.12` image) was already a good choice before we touched it — "slim" variants strip out anything not needed to run Python, which means fewer packages Trivy can find vulnerabilities in and a smaller image to move around.

## `.dockerignore` — what NOT to put in the image

Same idea as `.gitignore`, but for Docker: `db.sqlite3`, `.env`, `.git`, `venv` are all excluded from what gets copied into the image. This matters for two reasons — you don't want to bake a stale/dev database or a secrets file into a Docker image that might get shared or scanned, and it keeps the image smaller.

## Jenkins builds the image — but where does it end up?

Normally, after `docker build`, you'd `docker push` the image to a **registry** (Docker Hub, AWS ECR) so other machines can `docker pull` it. We deliberately skipped this: since Jenkins and the Kubernetes cluster (`k3s`) run on the exact same EC2 instance, there's no "other machine" that needs to pull anything. Instead:

```bash
docker save ots-django-app:10 | sudo k3s ctr images import -
```

This exports the image Docker just built and imports it directly into k3s's own internal image store, entirely locally — no network round-trip, no registry account, no cost. The tradeoff: this only works because everything's on one box. A multi-server setup would need a real registry.

**Why `imagePullPolicy: Never`** in our Kubernetes config (see doc 6): this tells Kubernetes "don't ever try to download this image from anywhere — it must already be sitting on this machine." Combined with the local import step above, that's exactly true, and it fails fast/clearly if the image name/tag typo'd rather than hanging on a pull that was never going to succeed.

## Trivy — scanning the image for vulnerabilities

Covered in depth in [doc 10](10-security-scanning.md), but the short version: after building, Jenkins runs `trivy image` against it, which checks every OS package and every Python library inside the image against known-vulnerability databases.
