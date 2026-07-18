# Security Scanning: Bandit, Gitleaks, Trivy

Three tools, three completely different jobs — all run automatically in the Jenkins pipeline (see [doc 7](07-jenkins-cicd.md)).

## Bandit — finds risky patterns in your Python code

Bandit reads your actual Python source and flags known-dangerous *patterns*, not spelling mistakes. Examples of what it catches:
- Using `assert` for something that matters at runtime (asserts get silently stripped out in optimized Python builds — `python -O`)
- Using Python's built-in `random` module for anything security-sensitive (it's not cryptographically secure — use `secrets` instead)
- Unpickling data from an untrusted source (Python's `pickle` can execute arbitrary code during deserialization)
- SQL queries built with string concatenation instead of parameterized queries (SQL injection risk)

It's a **static** analysis tool — it never actually runs your code, just reads it.

## Gitleaks — finds secrets that shouldn't be in your repo

Scans your codebase for things that look like credentials — API keys, private keys, tokens, password-looking strings — using pattern matching against known formats (AWS keys, GitHub tokens, generic high-entropy strings, etc.). The goal: catch a secret *before* it's pushed and permanently baked into git history (removing something from git history after the fact is a much bigger, more disruptive operation than never committing it).

**Directly relevant to this project**: earlier in development, a private SSH key got accidentally pasted into a chat conversation multiple times — the same class of mistake Gitleaks exists to catch, just in a different location (chat vs. git). The fix in both cases is the same: rotate the exposed credential immediately, treat it as compromised the moment it's been exposed anywhere it shouldn't have been, regardless of whether it "still works."

## Trivy — finds known vulnerabilities in your built image

Different again from the other two: Trivy inspects the **final built Docker image**, not source code — every OS package (`bsdutils`, `perl`, `libc`, whatever the base image includes) and every Python library your `requirements.txt` pulled in, checking each one's exact version against public vulnerability databases (CVEs).

### Why `--ignore-unfixed` matters

A Debian-based image (ours uses `python:3.12-slim`, which is Debian-based) will almost always have *some* HIGH/CRITICAL findings in its OS packages simply because Debian hasn't shipped a patch for every CVE yet — these are things you fundamentally cannot fix by changing anything in *your* project. Scanning without `--ignore-unfixed` means your build fails on CVEs you have zero ability to act on, which trains you to ignore the tool entirely. Adding `--ignore-unfixed` filters the report down to only vulnerabilities that **do** have an available fix — which, for this project, turned out to be two real, actionable findings: `Django` and `PyJWT` were pinned to versions with genuine security patches available, so we bumped both in `requirements.txt`.

## Why these are "advisory" (non-blocking) in our pipeline, except Trivy

Bandit and Gitleaks are wrapped in `catchError` in the Jenkinsfile — they report findings but don't fail the build. This was a deliberate call, not an oversight: gating on every pre-existing issue the moment you turn a scanner on tends to fail nearly every build in a codebase that wasn't written with that scanner in mind, which just trains people to ignore red builds entirely. The plan is to tighten these to blocking once existing findings are actually cleaned up. Trivy is still allowed to fail the build (with `--ignore-unfixed` filtering out the noise) since its remaining findings are genuinely actionable.

## Where to see results

Bandit/Gitleaks: Jenkins → your build → Console Output, in the "Security scans" stage section (runs in parallel, so both appear interleaved). Trivy: same console output, "Trivy image scan" stage — prints a full table of any HIGH/CRITICAL findings with fixed versions if `--ignore-unfixed` still leaves any.
