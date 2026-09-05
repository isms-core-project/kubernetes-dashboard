# Security Policy

This project takes security seriously. If you discover a vulnerability in the manifests
or documentation in this repository, or in the running Kubernetes Dashboard itself (the
images this repo's manifests deploy, built from
[kubernetes-dashboard-factory](https://github.com/isms-core-project/kubernetes-dashboard-factory)),
please report it responsibly.

## Reporting a Vulnerability

Please email: **info@kubernetes-dashboard.com**
Subject: **Kubernetes Dashboard Security — Vulnerability Report**

Include:
- A clear description of the issue and potential impact
- Reproduction steps (proof-of-concept if available)
- Affected files/manifests (component name if relevant: `api`, `auth`,
  `metrics-scraper`, `web`)
- Any suggested remediation

If you prefer encrypted reporting, request a PGP key via email and we will provide one.

## What to Expect

We will:
- Acknowledge receipt within **3 business days**
- Provide a status update within **10 business days**
- Work with you on a coordinated disclosure timeline when appropriate

## Scope

**In scope:**
- The Kubernetes Dashboard itself — the Go backend (`api`, `auth`, `metrics-scraper`) and
  Angular frontend (`web`) shipped in the images this repo's manifests reference,
  including authentication, CSRF protection, and RBAC enforcement
- The Kubernetes manifests in [`manifests/`](manifests/) — NetworkPolicy, RBAC bindings,
  Secret handling, container hardening (`readOnlyRootFilesystem`, `runAsNonRoot`, dropped
  capabilities)
- The Dockerfiles and build pipeline that produce the published images (source lives in
  the private [kubernetes-dashboard-factory](https://github.com/isms-core-project/kubernetes-dashboard-factory) repo — reports about it are still welcome here)
- Supply-chain risks introduced by dependencies (Go modules, npm packages, base images)

**Out of scope:**
- Vulnerabilities in third-party operators this dashboard auto-detects but doesn't ship
  (cert-manager, MetalLB, Kubescape, Gateway API)
- Vulnerabilities in the underlying Kubernetes cluster, container runtime, or CNI itself
- Social engineering, spam, or physical attacks

## Deployment Security

This dashboard runs with real cluster privileges. We recommend:
- Applying the hardened manifest set (`20-deployments-hardened.yaml` +
  `99-network-policy.yaml`) rather than the standard one, so only Kong's ingress can
  reach the backend Services
- Scoping the token you actually use day-to-day to a least-privilege ServiceAccount
  (`dashboard-user` / a namespace-scoped user) rather than always logging in as
  `admin-user`
- Generating your own `kubernetes-dashboard-csrf` secret per deployment
  (`openssl rand 256 | base64`) rather than reusing a value from documentation or a
  shared example
- Rotating that CSRF key, and any long-lived tokens created with
  `kubectl create token --duration=...`, on a schedule that matches your own risk
  tolerance
- Pinning image tags to a specific release rather than tracking `latest` in production

## Proactive Security Reviews

Beyond responding to external reports, we periodically run the source codebase through
[Visa's Vulnerability Agentic Harness (VVAH)](https://github.com/visa/visa-vulnerability-agentic-harness),
an open-source agentic SAST tool, and fix every independently-verified finding before
shipping. The most recent full pass — backend and frontend, 53 findings plus one
finding surfaced only by checking the live deployment directly (the `web` module had no
CSRF protection at all) — landed in **v1.1**. See the
[release notes](https://github.com/isms-core-project/kubernetes-dashboard/releases) and
[blog](https://kubernetes-dashboard.com/blog/) for the summary.

## Safe Handling

- Do not include secrets, tokens, private keys, or real cluster data in vulnerability
  reports.
- Treat any exported manifest, log, or config you attach as potentially sensitive until
  reviewed.

Thank you for helping improve Kubernetes Dashboard.
