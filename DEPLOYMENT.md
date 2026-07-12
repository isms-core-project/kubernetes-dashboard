# Deploy — Angular + Angular Material

Full runbook for the Angular flavor of the Kubernetes Dashboard.

Namespace: `kubernetes-dashboard`  
Web image: `ghcr.io/isms-core-project/kubernetes-dashboard:dashboard-web-angular-latest`

---

## Prerequisites

### metrics-server

metrics-server must be running in `kube-system` for CPU/memory current-usage data to work.
K3s includes it by default. On native Kubernetes (kubeadm, Talos, etc.) apply it first:

```bash
kubectl apply -f manifests/00-prereqs-metrics-server.yaml
kubectl rollout status deployment/metrics-server -n kube-system
```

Safe to run on clusters that already have metrics-server — `kubectl apply` will no-op unchanged resources.

---

## Deploy (Standard)

```bash
kubectl apply -f manifests/00-namespace.yaml
kubectl apply -f manifests/01-secrets.yaml
kubectl apply -f manifests/02-configmap.yaml
kubectl apply -f manifests/03-ai-secret.yaml       # Optional — AI assistant (see below)
kubectl apply -f manifests/10-rbac.yaml
kubectl apply -f manifests/20-deployments.yaml
kubectl apply -f manifests/50-services.yaml
kubectl apply -f manifests/60-admin-user.yaml
```

## Deploy (Hardened)

Use `20-deployments-hardened.yaml` and apply the NetworkPolicy last:

```bash
kubectl apply -f manifests/00-namespace.yaml
kubectl apply -f manifests/01-secrets.yaml
kubectl apply -f manifests/02-configmap.yaml
kubectl apply -f manifests/03-ai-secret.yaml            # Optional — AI assistant
kubectl apply -f manifests/04-notifications-secret.yaml # Optional — email alerts
kubectl apply -f manifests/10-rbac.yaml
kubectl apply -f manifests/20-deployments-hardened.yaml
kubectl apply -f manifests/50-services.yaml
kubectl apply -f manifests/60-admin-user.yaml
kubectl apply -f manifests/99-network-policy.yaml
```

Hardened variant adds: `readOnlyRootFilesystem`, `runAsNonRoot`, `drop ALL` capabilities,
`priorityClassName: system-cluster-critical`, liveness/readiness probes on all containers.

Verify all pods reach Running:

```bash
kubectl get all -n kubernetes-dashboard
```

---

## Access

Dashboard is at `http://<node-ip>:30080` — Kong NodePort is fixed at port 30080 (HTTP) and 30443 (HTTPS).

**MetalLB (optional):** Edit `50-services.yaml` — change `type: NodePort` to `type: LoadBalancer`, remove the `nodePort` fields, and optionally pin an IP via `metallb.io/loadBalancerIPs: "<YOUR-IP>"`. Full setup instructions are in the comments at the top of that file.

---

## Login Accounts

Three manifest options are provided:

| Manifest | Account | Permissions | Use case |
|---|---|---|---|
| `60-admin-user.yaml` | `admin-user` | `cluster-admin` (full cluster) | Homelab, local dev, initial setup |
| `61-readonly-user.yaml` | `readonly-user` | Built-in `view` (read-only, no Secrets) | Monitoring users, auditors |
| `62-namespace-user.yaml` | `namespace-user` | Built-in `admin` scoped to one namespace | Team leads, namespace owners |

> **Production note:** `60-admin-user.yaml` grants unrestricted cluster-admin access.
> For shared or production clusters use `61-readonly-user.yaml` or `62-namespace-user.yaml`.

Get the login token (replace `admin-user` with the account name you applied):

```bash
kubectl get secret admin-user -n kubernetes-dashboard \
  -o jsonpath='{.data.token}' | base64 -d
```

---

## VictoriaMetrics — Historical Metrics and Sparklines (Optional)

When deployed, pod detail pages gain CPU and memory sparklines with a 1h/6h/24h/7d time range
selector. The Cluster Overview page also shows a live Network Traffic graph.

```bash
kubectl apply -f manifests/25-alloy.yaml            # Network Traffic graph
kubectl apply -f manifests/26-victoriametrics.yaml  # sparklines + trend arrows
```

Or, if you already run **kube-prometheus-stack**, skip the VictoriaMetrics manifest and set
`PROMETHEUS_ENDPOINT` in `20-deployments-hardened.yaml` instead.

---

## Grafana Alloy — Network Traffic Graph (Optional)

Alloy is the metrics push agent. It scrapes node network interface stats and pushes them to
VictoriaMetrics, enabling the live Network Traffic graph on the Cluster Overview page.

```bash
kubectl apply -f manifests/25-alloy.yaml
```

Requires VictoriaMetrics to be running. The graph does not appear without both.

---

## AI Assistant (Optional)

The AI assistant uses Claude Sonnet via SSE streaming. When opened from a pod detail page, the
current pod spec and recent events are automatically injected as context.

Create the secret with your Anthropic API key:

```bash
kubectl -n kubernetes-dashboard create secret generic kubernetes-dashboard-ai \
  --from-literal=api-key="sk-ant-..."
```

Or apply `03-ai-secret.yaml` after editing it with your key.

The AI icon appears in the top AppBar once the secret is present and the pod restarts.

---

## Event Alerts (Optional)

Real-time email notifications on:

- CrashLoopBackOff
- OOMKilled
- ImagePullBackOff
- NodeNotReady
- PVC issues

Alerts are deduplicated per workload with a 1-hour window. Each alert type can be enabled or
disabled from the dashboard Settings page.

Requires a Microsoft Graph API application registration (used for sending mail):

```bash
kubectl -n kubernetes-dashboard create secret generic kubernetes-dashboard-notifications \
  --from-literal=tenant-id="..." \
  --from-literal=client-id="..." \
  --from-literal=client-secret="..." \
  --from-literal=sender-email="alerts@yourdomain.com" \
  --from-literal=recipient-email="oncall@yourdomain.com"
```

Or apply `04-notifications-secret.yaml` after editing it with your values.

---

## Auto-Detected Integrations

The following UI sections appear automatically when the corresponding CRDs are detected on the
cluster — no configuration required:

| Integration | CRD group | UI section |
|---|---|---|
| cert-manager | `cert-manager.io` | Certificate Manager (Certificates, Issuers, ClusterIssuers) |
| MetalLB | `metallb.io` | MetalLB (IP Address Pools, L2 Advertisements) |
| Kubescape | `spdx.softwarecomposition.kubescape.io` | Kubescape (compliance scores, CVE findings) |
| Gateway API | `gateway.networking.k8s.io` | Gateway API (GatewayClasses, Gateways, HTTPRoutes) |

---

## Tear Down

```bash
kubectl delete namespace kubernetes-dashboard
```

This removes all dashboard resources. Persistent data (configmaps, secrets) is deleted with the namespace.

---

## Images

All images are public on GitHub Container Registry — no pull credentials needed for public clusters.

| Component | Image |
|---|---|
| Web (Angular) | `ghcr.io/isms-core-project/kubernetes-dashboard:dashboard-web-angular-latest` |
| API | `ghcr.io/isms-core-project/kubernetes-dashboard:dashboard-api-latest` |
| Auth | `ghcr.io/isms-core-project/kubernetes-dashboard:dashboard-auth-latest` |
| Metrics scraper | `ghcr.io/isms-core-project/kubernetes-dashboard:dashboard-metrics-scraper-latest` |
| Kong | `kong:3.9.3` |
