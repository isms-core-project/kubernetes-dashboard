# Kubernetes Dashboard

Production deployment manifests for the Kubernetes Dashboard — a maintained continuation of the archived [kubernetes-retired/dashboard](https://github.com/kubernetes-retired/dashboard), rebuilt with React 19 and Material UI v6.

**Source repository:** [isms-core-project/kubernetes-dashboard-factory](https://github.com/isms-core-project/kubernetes-dashboard-factory)

---

## Architecture

Five pods in the `kubernetes-dashboard` namespace, fronted by a Kong API gateway:

```
Browser
  └── Kong 3.6 (DBless, LoadBalancer)
        ├── /api/v1/login, /csrftoken, /me   → dashboard-auth
        ├── /api/*                            → dashboard-api
        │     └── sidecar: dashboard-metrics-scraper
        └── /                                 → dashboard-web (React SPA)
```

---

## Deploy

Apply manifests in order:

```bash
kubectl apply -f manifests/00-namespace.yaml
kubectl apply -f manifests/01-secrets.yaml
kubectl apply -f manifests/02-configmap.yaml
kubectl apply -f manifests/03-ai-secret.yaml    # optional — AI assistant
kubectl apply -f manifests/10-rbac.yaml
kubectl apply -f manifests/20-deployments-hardened.yaml
kubectl apply -f manifests/50-services.yaml
kubectl apply -f manifests/60-admin-user.yaml
kubectl apply -f manifests/99-network-policy.yaml
```

Verify all five pods reach Running:

```bash
kubectl get all -n kubernetes-dashboard
```

See [manifests/DEPLOY.md](manifests/DEPLOY.md) for the full runbook including AI assistant setup, image updates, and tear-down.

---

## Access

The dashboard is served via a Kong LoadBalancer service. Get the assigned IP:

```bash
kubectl get svc kubernetes-dashboard-kong -n kubernetes-dashboard
```

### Login Token

```bash
kubectl get secret admin-user -n kubernetes-dashboard \
  -o jsonpath='{.data.token}' | base64 -d
```

---

## Features

- Workloads, Service, Config & Storage, Cluster resources — full CRUD and detail views
- Pod log streaming and interactive shell (xterm.js)
- Cluster Map, Policy Audit, Resource Efficiency, RBAC Viewer, Certificate Tracker, Event Timeline
- AI Assistant (Claude, SSE streaming — requires Anthropic API key)

---

## License

Copyright 2017 The Kubernetes Authors  
Copyright 2026 The ISMS Core Project

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full text.
