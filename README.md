# Kubernetes Dashboard

The original [kubernetes/dashboard](https://github.com/kubernetes-retired/dashboard) was archived in 2024 with this message:

> *"This project is now archived and no longer maintained due to lack of active maintainers and contributors. Thank you to everyone who used, starred, or contributed to this project! Feel free to fork this repository if you want to continue development yourself. Please consider using Headlamp instead."*

We took up the challenge.

The Go API backend was solid and worth keeping. The Angular WebUI was Angular 16 — already one major version behind at archive time, and drifting further every month. Rather than let it rot, we forked it and got to work.

**First attempt:** jump the Angular WebUI straight from v16 to v21. That failed — four compounding blockers mean a direct jump is impossible (abandoned flex-layout, deleted SCSS entrypoints, a builder that no longer exists). So we built a **React + Material UI** WebUI from scratch on the same Go backend, shipping something production-ready while we worked out the proper incremental upgrade path.

**Second attempt:** step through every Angular major version one at a time — 16 → 17 → 18 → 19 → 20 → 21 — fixing all 44 catalogued breaking changes along the way. That worked. See [ANGULAR-UPGRADE.md](ANGULAR-UPGRADE.md) for the full story.

The result is two production-grade WebUI flavors on a shared Go backend, both actively maintained.

Two WebUI flavors — deploy the one that fits your stack.

---

## Flavors

| | React + Material UI | Angular + Angular Material |
|---|---|---|
| **Framework** | React 19, MUI v6 | Angular 21, Angular Material |
| **Namespace** | `kubernetes-dashboard` | `k8s-dash-angular` |
| **Web image** | `dashboard-web-react-mui-latest` | `dashboard-web-angular-latest` |
| **Manifests** | `manifests_webui_react+mui/manifests/` | `manifests_webui_angular/` |
| **Deploy guide** | [DEPLOY-REACT.md](DEPLOY-REACT.md) | [DEPLOY-ANGULAR.md](DEPLOY-ANGULAR.md) |
| **Cert Manager UI** | ✅ | ✅ |
| **MetalLB UI** | ✅ | ✅ |
| **Pod Security / Network** | ✅ | ✅ |

Both flavors use the same Go images: `dashboard-api`, `dashboard-auth`, `dashboard-metrics-scraper`, and Kong 3.6. All images pull from `ghcr.io/isms-core-project/kubernetes-dashboard`.

---

## Shared Features

- **Cluster Health Overview** — stat tiles, donut charts, live Network Traffic graph (Grafana Alloy)
- **Workloads** — full list + detail for Deployments, DaemonSets, StatefulSets, Jobs, Cron Jobs, Replica Sets
- **Workload Actions** — edit YAML, restart, scale, rollback, pause/resume, exec shell — all RBAC-aware
- **Cluster Map** — namespace-scoped topology view with health filter and zoom
- **Application Projects** — per-namespace cards with pod health and resource totals
- **Policy Audit** — Polaris-native security scoring (0–100) per workload
- **Resource Efficiency** — Goldilocks-style CPU/memory request vs limit vs actual; trend arrows via VictoriaMetrics
- **RBAC Viewer** — cluster-wide role binding table with wildcard detection
- **Certificate Tracker** — TLS secrets parsed with `crypto/x509`; expiry countdown and status badges
- **Event Timeline** — live event feed with time-bucket grouping and warning highlight
- **Registry Manager** — docker pull secrets cross-referenced with pod `imagePullSecrets`
- **Historical Metrics** — pod CPU/memory sparklines with 1h/6h/24h/7d selector (VictoriaMetrics or Prometheus)
- **Cluster Shell** — interactive xterm.js terminal exec'd into the dashboard pod; kubectl runs as the user's JWT
- **AI Assistant** — Claude Sonnet via SSE streaming; pod spec and events auto-injected from detail pages
- **Event Alerts** — real-time email on CrashLoop/OOM/ImagePullBackOff/NodeNotReady; configurable per type
- **Pod Logs** — live streaming, timestamps, severity filter, text filter, download

---

## Screenshots — React + Material UI

### Sign In
![Sign in](screenshots_webui_react+mui/k8s_dashboard_logon.png)

### Overview
Stat tiles, donut charts, and live Network Traffic graph.

![Overview](screenshots_webui_react+mui/k8s_dashboard_overview.png)

### Workloads
Full workload list with status, restart count, and inline actions.

![Workloads](screenshots_webui_react+mui/k8s_dashboard_home.png)

### Cluster Map
Namespace-scoped topology with Error/Warning filter and zoom.

![Cluster map](screenshots_webui_react+mui/k8s_dashboard_map.png)

### Pods
Live CPU/Memory sparklines, restart count, node assignment, inline actions.

![Pods](screenshots_webui_react+mui/k8s_dashboard_pods.png)

### Policy Audit
Polaris security scoring per workload — expandable check details.

![Policy audit](screenshots_webui_react+mui/k8s_dashboard_policy_audit.png)

### Resource Efficiency
CPU/memory request vs limit vs actual — verdict chips, CSV export.

![Resource efficiency](screenshots_webui_react+mui/k8s_dashboard_resource_efficiency.png)

### Certificate Tracker
TLS secrets: common name, SANs, expiry, status badges.

![Certificate tracker](screenshots_webui_react+mui/k8s_dashboard_cert_tracker.png)

### Event Timeline
Live event feed with time-bucket grouping and warning highlight.

![Event timeline](screenshots_webui_react+mui/k8s_dashboard_events_timeline.png)

### Application Projects
Per-namespace project cards with pod health and resource totals.

![Projects](screenshots_webui_react+mui/k8s_dashboard_projects.png)

### Kubescape Security
Compliance scores and CVE findings — auto-detected when Kubescape Operator is running.

![Kubescape](screenshots_webui_react+mui/k8s_dashboard_kubescape.png)

### VictoriaMetrics Sparklines
Pod CPU/memory sparklines with 1h/6h/24h/7d selector.

![VictoriaMetrics](screenshots_webui_react+mui/k8s_dashboard_victoriametrics.png)

### PVC Storage Usage
Live usage bars from the kubelet stats API.

![PVC storage](screenshots_webui_react+mui/k8s_dashboard_pvc.png)

### RBAC Viewer
All role bindings with resolved rules and wildcard detection.

![RBAC viewer](screenshots_webui_react+mui/k8s_dashboard_rbac_viewer.png)

### Cluster Shell
Full interactive bash terminal — kubectl runs as the logged-in user.

![Cluster Shell](screenshots_webui_react+mui/k8s_dashboard_shell.png)

---

## Screenshots — Angular + Angular Material

### Sign In
![Sign in](screenshots_webui_angular/k8s_dashboard_logon.png)

### Overview
Stat tiles, donut charts, and Network Traffic graph.

![Overview](screenshots_webui_angular/k8s_dashboard_overview.png)

### Workloads
Full workload list with status, restart count, and inline actions.

![Workloads](screenshots_webui_angular/k8s_dashboard_home.png)

### Cluster Map
Namespace-scoped topology with health filter and zoom.

![Cluster map](screenshots_webui_angular/k8s_dashboard_map.png)

### Pods
Live CPU/Memory sparklines, restart count, node assignment.

![Pods](screenshots_webui_angular/k8s_dashboard_pods.png)

### Nodes
Per-node CPU and memory request percentages and pod capacity.

![Nodes](screenshots_webui_angular/k8s_dashboard_nodes.png)

### Policy Audit
Polaris security scoring per workload.

![Policy audit](screenshots_webui_angular/k8s_dashboard_policy_audit.png)

### Resource Efficiency
Goldilocks-style CPU/memory comparison with trend arrows.

![Resource efficiency](screenshots_webui_angular/k8s_dashboard_resource_efficiency.png)

### Certificate Manager
cert-manager Certificates, Issuers, and ClusterIssuers — auto-detected.

![Certificate Manager](screenshots_webui_angular/k8s_dashboard_cert_manager.png)

### Certificate Tracker
TLS secrets scanned with `crypto/x509` — expiry countdown and status badges.

![Certificate tracker](screenshots_webui_angular/k8s_dashboard_cert_tracker.png)

### MetalLB
IP Address Pools and L2 Advertisements — auto-detected when MetalLB CRDs are present.

![MetalLB](screenshots_webui_angular/k8s_dashboard_metallb.png)

### Pod Security / Network Policies
Pod Security Standards and NetworkPolicy visualisation.

![Pod security](screenshots_webui_angular/k8s_dashboard_pod_sec_net.png)

### Event Timeline
Live event feed with time-bucket grouping.

![Event timeline](screenshots_webui_angular/k8s_dashboard_events_timeline.png)

### Application Projects
Per-namespace project cards.

![Projects](screenshots_webui_angular/k8s_dashboard_projects.png)

### Kubescape Security
Compliance scores and CVE findings — auto-detected.

![Kubescape](screenshots_webui_angular/k8s_dashboard_kubescape.png)

### VictoriaMetrics Sparklines
Pod CPU/memory sparklines with 1h/6h/24h/7d selector.

![VictoriaMetrics](screenshots_webui_angular/k8s_dashboard_victoriametrics.png)

### PVC Storage Usage
Live usage bars from the kubelet stats API.

![PVC storage](screenshots_webui_angular/k8s_dashboard_pvc.png)

### RBAC Viewer
All role bindings with resolved rules and wildcard detection.

![RBAC viewer](screenshots_webui_angular/k8s_dashboard_rbac_viewer.png)

### Cluster Shell
Full interactive bash terminal.

![Cluster Shell](screenshots_webui_angular/k8s_dashboard_shell.png)

---

## Architecture

Five pods in the dashboard namespace, fronted by a Kong API gateway:

```
Browser
  └── Kong 3.6 (DBless, NodePort :30080)
        ├── /api/v1/login, /csrftoken, /me   → dashboard-auth
        ├── /api/*                            → dashboard-api
        │     └── sidecar: dashboard-metrics-scraper
        └── /                                 → dashboard-web (SPA)
```

Optional add-ons (all in the same namespace):

| Add-on | Manifest | Enables |
|---|---|---|
| Grafana Alloy | `25-alloy.yaml` | Network Traffic graph on Overview |
| VictoriaMetrics | `26-victoriametrics.yaml` | Pod CPU/memory sparklines, trend arrows, network graph |
| Prometheus | External (`kube-prometheus-stack`) | Same sparklines — set `PROMETHEUS_ENDPOINT` instead of `VM_ENDPOINT` |

---

## Deploy

See the flavor-specific guide for the full runbook:

- **React + Material UI:** [DEPLOY-REACT.md](DEPLOY-REACT.md)
- **Angular + Angular Material:** [DEPLOY-ANGULAR.md](DEPLOY-ANGULAR.md)

---

## License

Copyright 2017 The Kubernetes Authors  
Copyright 2026 The ISMS Core Project

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full text.
