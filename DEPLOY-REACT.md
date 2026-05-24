# Deploy — React + Material UI

Full runbook for the React + Material UI flavor of the Kubernetes Dashboard.

Namespace: `kubernetes-dashboard`  
Web image: `ghcr.io/isms-core-project/kubernetes-dashboard:dashboard-web-react-mui-latest`

---

## Prerequisites

### metrics-server

metrics-server must be running in `kube-system` for CPU/memory current-usage data to work.
K3s includes it by default. On native Kubernetes (kubeadm, Talos, etc.) apply it first:

```bash
kubectl apply -f manifests_webui_react+mui/manifests/00-prereqs-metrics-server.yaml
kubectl rollout status deployment/metrics-server -n kube-system
```

Safe to run on clusters that already have metrics-server — `kubectl apply` will no-op unchanged resources.

---

## Deploy (Standard)

```bash
kubectl apply -f manifests_webui_react+mui/manifests/00-namespace.yaml
kubectl apply -f manifests_webui_react+mui/manifests/01-secrets.yaml
kubectl apply -f manifests_webui_react+mui/manifests/02-configmap.yaml
kubectl apply -f manifests_webui_react+mui/manifests/03-ai-secret.yaml       # Optional — AI assistant
kubectl apply -f manifests_webui_react+mui/manifests/10-rbac.yaml
kubectl apply -f manifests_webui_react+mui/manifests/20-deployments.yaml
kubectl apply -f manifests_webui_react+mui/manifests/50-services.yaml
kubectl apply -f manifests_webui_react+mui/manifests/60-admin-user.yaml
```

## Deploy (Hardened)

Use `20-deployments-hardened.yaml` and apply the NetworkPolicy last:

```bash
kubectl apply -f manifests_webui_react+mui/manifests/00-namespace.yaml
kubectl apply -f manifests_webui_react+mui/manifests/01-secrets.yaml
kubectl apply -f manifests_webui_react+mui/manifests/02-configmap.yaml
kubectl apply -f manifests_webui_react+mui/manifests/03-ai-secret.yaml            # Optional — AI assistant
kubectl apply -f manifests_webui_react+mui/manifests/04-notifications-secret.yaml # Optional — email alerts
kubectl apply -f manifests_webui_react+mui/manifests/10-rbac.yaml
kubectl apply -f manifests_webui_react+mui/manifests/20-deployments-hardened.yaml
kubectl apply -f manifests_webui_react+mui/manifests/50-services.yaml
kubectl apply -f manifests_webui_react+mui/manifests/60-admin-user.yaml
kubectl apply -f manifests_webui_react+mui/manifests/99-network-policy.yaml
```

Hardened variant adds: `readOnlyRootFilesystem`, `runAsNonRoot`, `drop ALL` capabilities,
`priorityClassName: system-cluster-critical`, `topologySpreadConstraints`, liveness/readiness
probes on all containers. Kong cannot have `readOnlyRootFilesystem` (writes lua cache internally).

### NetworkPolicy

`99-network-policy.yaml` enforces least-privilege traffic for all pods:

| Pod | Ingress | Egress |
|---|---|---|
| kong | anywhere (LoadBalancer) | auth, api, web pods + DNS |
| web | kong only | DNS only |
| auth | kong only | k8s API server (443/6443) + DNS |
| api | kong only | metrics-scraper + victoriametrics (8428) + k8s API server (443/6443) + DNS |
| metrics-scraper | api only | everywhere (must scrape all namespaces; covers VM push) |
| victoriametrics | api + metrics-scraper + alloy (8428) | none |
| alloy | none | victoriametrics (8428) |

To apply or remove independently:

```bash
kubectl apply -f manifests_webui_react+mui/manifests/99-network-policy.yaml
kubectl delete -f manifests_webui_react+mui/manifests/99-network-policy.yaml
```

Verify all pods reach Running:

```bash
kubectl get all -n kubernetes-dashboard
```

---

## Access

Dashboard is at `http://<node-ip>:30080` — Kong NodePort is fixed at port 30080 (HTTP) and 30443 (HTTPS).
The landing page is `/overview` — a cluster health summary with stat tiles, donut charts, and (when VictoriaMetrics + Alloy are deployed) a live network traffic graph.

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
kubectl apply -f manifests_webui_react+mui/manifests/26-victoriametrics.yaml
kubectl rollout status statefulset/kubernetes-dashboard-victoriametrics -n kubernetes-dashboard
```

`VM_ENDPOINT` is already set in `20-deployments-hardened.yaml`. After applying, restart both pods:

```bash
kubectl rollout restart deployment/kubernetes-dashboard-api -n kubernetes-dashboard
kubectl rollout restart deployment/kubernetes-dashboard-metrics-scraper -n kubernetes-dashboard
```

Or, if you already run **kube-prometheus-stack**, skip the VictoriaMetrics manifest and set
`PROMETHEUS_ENDPOINT` in `20-deployments-hardened.yaml` instead.

### Verify data is flowing

```bash
kubectl port-forward svc/kubernetes-dashboard-victoriametrics 8428:8428 -n kubernetes-dashboard
curl http://localhost:8428/api/v1/label/__name__/values
```

Should show `dashboard_pod_*` and `dashboard_node_*` metric names after ~60 seconds.

### Remove VictoriaMetrics

```bash
kubectl delete -f manifests_webui_react+mui/manifests/26-victoriametrics.yaml
kubectl delete pvc storage-kubernetes-dashboard-victoriametrics-0 -n kubernetes-dashboard
```

---

## Grafana Alloy — Network Traffic Graph (Optional)

Deploys Alloy as a DaemonSet to scrape per-node network stats and push them to VictoriaMetrics.
Required for the live Network Traffic graph on the Overview page.

```bash
kubectl apply -f manifests_webui_react+mui/manifests/25-alloy.yaml
kubectl rollout status daemonset/kubernetes-dashboard-alloy -n kubernetes-dashboard
```

No dependency on VictoriaMetrics deploy order — Alloy retries `remote_write` until VM is ready.
After ~60 seconds, the Network Traffic graph auto-detects physical NICs and shows live rx/tx bytes/s.
Virtual interfaces (lo, veth, cni, flannel, docker, etc.) are filtered out automatically.

---

## AI Assistant (Optional)

The AI Assistant (SmartToy icon in AppBar) uses Claude Sonnet via SSE streaming. Pod spec and
recent events are automatically injected as context when opened from a pod detail page.

```bash
kubectl create secret generic kubernetes-dashboard-ai \
  --namespace kubernetes-dashboard \
  --from-literal=api-key="sk-ant-..." \
  --dry-run=client -o yaml | kubectl apply -f -
```

Or apply `03-ai-secret.yaml` after editing it with your key.

Rotate the key without a full secret recreation:

```bash
kubectl patch secret kubernetes-dashboard-ai \
  -n kubernetes-dashboard \
  -p '{"stringData": {"api-key": "sk-ant-...NEW"}}'
kubectl rollout restart deployment/kubernetes-dashboard-api -n kubernetes-dashboard
```

---

## Event Alerts (Optional)

Real-time email notifications on CrashLoopBackOff, OOMKilled, ImagePullBackOff, NodeNotReady,
and PVC issues. Each alert type is individually toggleable from the Settings page.
Alerts are deduplicated — one email per hour per affected workload.

Requires a Microsoft Graph API application registration with `Mail.Send` (Application permission):

```bash
# edit 04-notifications-secret.yaml with your tenant-id, client-id, client-secret,
# sender-email, recipient-email — then apply:
kubectl apply -f manifests_webui_react+mui/manifests/04-notifications-secret.yaml
kubectl rollout restart deployment/kubernetes-dashboard-api -n kubernetes-dashboard
```

The Settings → Notifications tab shows config status and a Send test email button.

| Alert type | Default |
|---|---|
| Pod Crash / CrashLoopBackOff | ON |
| OOM Kill | ON |
| Node Not Ready | ON |
| Image Pull Failure | OFF |
| Storage Issue (PVC) | OFF |

---

## Auto-Detected Integrations

These UI sections appear automatically when the corresponding CRDs are detected — no config needed:

| Integration | CRD group | UI section |
|---|---|---|
| Kubescape | `spdx.softwarecomposition.kubescape.io` | Security (compliance scores, CVE findings, NetworkPolicy generator) |
| cert-manager | `cert-manager.io` | Certificates in standard resource views |
| Gateway API | `gateway.networking.k8s.io` | Gateway API (GatewayClasses, Gateways, HTTPRoutes) |

### Deploy Kubescape Operator

```bash
helm repo add kubescape https://kubescape.github.io/helm-charts/ && \
helm repo update && \
helm upgrade --install kubescape kubescape/kubescape-operator \
  -n kubescape --create-namespace \
  --set clusterName=$(kubectl config current-context) \
  --set capabilities.relevancy=enable \
  --set capabilities.networkPolicyService=enable
```

The Security section appears automatically within a few minutes of operator startup.

---

## Global Settings

Settings → Global tab persists: cluster name, default namespace, items per page, auto-refresh
interval. Stored in the `kubernetes-dashboard-web-settings` ConfigMap — no pod restart required.

---

## Tear Down

```bash
kubectl delete namespace kubernetes-dashboard
kubectl delete clusterrole kubernetes-dashboard-metrics-scraper
kubectl delete clusterrolebinding kubernetes-dashboard-metrics-scraper
kubectl delete clusterrolebinding admin-user
```

ClusterRole and ClusterRoleBindings are cluster-scoped — deleting the namespace does not remove them.

---

## Images

All images are public on GitHub Container Registry — no pull credentials needed for public clusters.

| Component | Image |
|---|---|
| Web (React) | `ghcr.io/isms-core-project/kubernetes-dashboard:dashboard-web-react-mui-latest` |
| API | `ghcr.io/isms-core-project/kubernetes-dashboard:dashboard-api-latest` |
| Auth | `ghcr.io/isms-core-project/kubernetes-dashboard:dashboard-auth-latest` |
| Metrics scraper | `ghcr.io/isms-core-project/kubernetes-dashboard:dashboard-metrics-scraper-latest` |
| Kong | `kong:3.9.1` |
