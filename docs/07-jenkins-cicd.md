# Jenkins & CI/CD

## What "CI/CD" means

**Continuous Integration**: every time code changes, automatically run tests/checks against it — catch problems immediately, not days later. **Continuous Deployment**: if those checks pass, automatically ship the change to production. Jenkins is the tool that runs this checklist for us, defined as code in a `Jenkinsfile`.

## Where the Jenkinsfile actually lives (important, and non-obvious)

The **real, executing** `Jenkinsfile` is in the **app repo** (`ONline_testing_app_django/Jenkinsfile`), not this infra repo. Jenkins is configured as "Pipeline script from SCM" — meaning it always reads the Jenkinsfile from whatever repo it's currently building, at whatever commit it just checked out. `OTS-devops/jenkins/Jenkinsfile` is a manually-kept-in-sync reference copy so you can read it without SSHing into the server.

## Every stage, what it does, and why

```groovy
pipeline {
    stages {
        stage("Checkout") { ... }
```

**1. Checkout** — clones the app repo via an SSH deploy key (a repo-scoped key, so if it ever leaked, only *this one repo* is at risk — not your whole GitHub account).

**2. Install dependencies** — creates a Python virtual environment and `pip install`s everything in `requirements.txt`. Deliberately created **outside** the checked-out code (`/tmp/jenkins-venv-...`) — if it lived inside the repo folder, later stages that scan "all the code" (lint, security scanners) would also scan every third-party library inside the venv and produce a wall of irrelevant findings. This was a real bug we hit and fixed.

**3. Run Django unit tests** (`manage.py test`) — **blocking**: if tests fail, the pipeline stops here. No broken code reaches deployment.

**4. Lint** (`flake8`) — checks code style/quality. Also blocking.

**5. Security scans** (Bandit + Gitleaks, run in parallel) — **advisory, not blocking** (wrapped in `catchError`). Findings are reported but don't stop the pipeline. This was a deliberate choice: gating on every pre-existing style/security issue in a codebase that's *just* adopting these tools would fail nearly every build. The plan is to tighten this to blocking later, once existing issues are cleaned up.
   - **Bandit** scans Python code for common security mistakes (see [doc 10](10-security-scanning.md))
   - **Gitleaks** scans for accidentally-committed secrets (API keys, passwords) in the code

**6. Build Docker image** — `docker build`, tagged with the Jenkins build number (so every build produces a distinct, traceable image: `ots-django-app:10`, `:11`, etc.)

**7. Trivy image scan** — scans the built image for known vulnerabilities, `--ignore-unfixed` so it only flags CVEs with an actual available patch (see [doc 10](10-security-scanning.md) for why that flag matters).

**8. Load image into k3s** — see [doc 4](04-docker.md) for why there's no registry push step here.

**9. Deploy** — `helm upgrade --install ... --rollback-on-failure` (see [doc 6](06-helm.md)).

**10. Health check** — after deploying, actually `curl`s the app's URL and fails the build if it doesn't get a real response. Catches the case where the deploy *technically* succeeded (pod is "Running") but the app itself is broken internally.

## Credentials — how Jenkins authenticates without exposing secrets

Jenkins has its own **Credentials** store (separate from any file in the repo). The GitHub deploy key is stored there once, referenced in the Jenkinsfile only by an ID (`credentialsId: "github-deploy-key"`) — the actual private key content never appears in any file you can read, and never gets printed in build logs.

## Real bugs we hit setting this up (all fixed, but worth knowing about)

- **Jenkins's signing key rotates periodically** (from Jenkins project maintainers, not us) — an install can suddenly fail with `NO_PUBKEY` if the apt repo's key changed since the setup script was written.
- **Jenkins runs as its own Linux user** (`jenkins`), separate from your normal `ubuntu` login — it needed its own SSH trust for GitHub, its own Kubernetes credentials, and (after being added to the `docker` group) an actual service restart before that group membership took effect. See [doc 3](03-ansible.md) for more on this.
- **`db.sqlite3` was accidentally committed to git early on**, before `.gitignore` had a rule for it — adding the rule *afterward* doesn't retroactively untrack an already-committed file; that needed an explicit `git rm --cached`.

## How to actually watch it run

Jenkins → your job → click a build number → **Console Output**. Every `sh` step's exact command and output is printed, in order — the single best way to understand what a pipeline is really doing, stage by stage.
