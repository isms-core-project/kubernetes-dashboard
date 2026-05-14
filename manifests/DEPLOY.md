# Kubernetes Dashboard — Raw Manifest Deployment

No Helm. Apply files in order and wait between stages.

## Prerequisites

metrics-server must be running in `kube-system` for the dashboard's CPU/memory current-usage data to work.
K3s includes it by default — skip this on K3s. On native Kubernetes (kubeadm, Talos, etc.) apply it first:

```bash
kubectl apply -f 00-prereqs-metrics-server.yaml
kubectl rollout status deployment/metrics-server -n kube-system
```

Safe to run on clusters that already have metrics-server — `kubectl apply` will no-op unchanged resources.

---

## Deploy (Standard)

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-secrets.yaml
kubectl apply -f 02-configmap.yaml
kubectl apply -f 03-ai-secret.yaml       # Optional — AI assistant (see below)
kubectl apply -f 10-rbac.yaml
kubectl apply -f 20-deployments.yaml
kubectl apply -f 50-services.yaml
kubectl apply -f 60-admin-user.yaml
```

## Deploy (Hardened)

Use `20-deployments-hardened.yaml` instead of `20-deployments.yaml`, and apply the NetworkPolicy last:

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-secrets.yaml
kubectl apply -f 02-configmap.yaml
kubectl apply -f 03-ai-secret.yaml            # Optional — AI assistant (see below)
kubectl apply -f 04-notifications-secret.yaml # Optional — email notifications (see below)
kubectl apply -f 10-rbac.yaml
kubectl apply -f 20-deployments-hardened.yaml
kubectl apply -f 50-services.yaml
kubectl apply -f 60-admin-user.yaml
kubectl apply -f 99-network-policy.yaml
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
| victoriametrics | api + metrics-scraper (8428) | none |

To apply or remove independently:
```bash
kubectl apply -f 99-network-policy.yaml
kubectl delete -f 99-network-policy.yaml
```

---

## VictoriaMetrics (Optional — Historical Metrics + Sparklines)

VictoriaMetrics is an **opt-in** time-series backend. When deployed, the pod detail page gains
CPU and memory sparklines with a 1h/6h/24h/7d time range selector. Without it, the dashboard
works exactly as before — no UI difference.

### Deploy VictoriaMetrics

If you also want the Network Traffic graph, deploy node-exporter first (it creates the ServiceAccount VM needs):

```bash
kubectl apply -f 25-node-exporter.yaml   # creates vm-sd ServiceAccount + scrape ConfigMap
kubectl apply -f 26-victoriametrics.yaml
kubectl rollout status statefulset/kubernetes-dashboard-victoriametrics -n kubernetes-dashboard
```

Node-exporter only is also fine — VM without node-exporter still works for pod CPU/memory sparklines:

```bash
kubectl apply -f 26-victoriametrics.yaml
kubectl rollout status statefulset/kubernetes-dashboard-victoriametrics -n kubernetes-dashboard
```

This creates a StatefulSet with a **2Gi Longhorn PVC** and a ClusterIP Service. Data is retained
for 30 days by default (configurable via `-retentionPeriod` in the StatefulSet args).

### Enable the feature

`VM_ENDPOINT` env var is already set in `20-deployments-hardened.yaml`:

```yaml
- name: VM_ENDPOINT
  value: "http://kubernetes-dashboard-victoriametrics:8428"
```

It is present on both the **api** and **metrics-scraper** containers. If VictoriaMetrics is not
deployed, simply remove or blank this env var — the dashboard falls back to SQLite with no change.

After applying the deployment manifest, restart both pods to pick up the env var:

```bash
kubectl rollout restart deployment/kubernetes-dashboard-api -n kubernetes-dashboard
kubectl rollout restart deployment/kubernetes-dashboard-metrics-scraper -n kubernetes-dashboard  # wait for this before data appears
```

### Verify data is flowing

Give the scraper one full cycle (~60 seconds), then:

```bash
# List metric names ingested — should show dashboard_pod_* and dashboard_node_*
curl http://<victoriametrics-pod-ip>:8428/api/v1/label/__name__/values

# Or via kubectl port-forward:
kubectl port-forward svc/kubernetes-dashboard-victoriametrics 8428:8428 -n kubernetes-dashboard
curl http://localhost:8428/api/v1/label/__name__/values
```

### Disable / remove VictoriaMetrics

Remove `VM_ENDPOINT` from `20-deployments-hardened.yaml`, apply, then restart api and metrics-scraper.
The StatefulSet and PVC can be deleted independently when you're ready:

```bash
kubectl delete -f 26-victoriametrics.yaml
kubectl delete pvc storage-kubernetes-dashboard-victoriametrics-0 -n kubernetes-dashboard
```

## Node Exporter (Optional — Network Traffic Graph)

Deploys Prometheus `node_exporter` as a DaemonSet so VictoriaMetrics can scrape
per-node network metrics. Required for the **Network Traffic** graph on the Overview page.

Deploy **before** VictoriaMetrics — `25-node-exporter.yaml` creates the `kubernetes-dashboard-vm-sd`
ServiceAccount that `26-victoriametrics.yaml` depends on.

```bash
kubectl apply -f 25-node-exporter.yaml
kubectl rollout status daemonset/kubernetes-dashboard-node-exporter -n kubernetes-dashboard
```

The manifest includes:
- `kubernetes-dashboard-vm-sd` ServiceAccount + ClusterRole for VM kubernetes_sd pod discovery
- VM scrape ConfigMap (`kubernetes-dashboard-vm-scrape`) with `kubernetes_sd`, label relabelling, and virtual interface exclusion
- Selective collector list (cpu, meminfo, diskstats, filesystem, netdev, uname, loadavg)
- Talos-compatible: `--path.rootfs=/host` with host root mounted read-only
- `hostNetwork: true`, `hostPID: true`, non-root, `readOnlyRootFilesystem`
- Tolerations for control-plane nodes

`26-victoriametrics.yaml` already references the `kubernetes-dashboard-vm-scrape` ConfigMap
and the `kubernetes-dashboard-vm-sd` ServiceAccount — no manual patching required.

After ~60 seconds of first scrape, the Overview page Zone 3 (Network Traffic) auto-detects
physical NICs via VictoriaMetrics label values and shows live rx/tx bytes/s with a 1h/6h/24h/7d
range toggle. Virtual interfaces (lo, veth, cni, flannel, etc.) are filtered out automatically.

---

## Verify

```bash
kubectl get all -n kubernetes-dashboard
```

All 5 pods (auth, api, web, metrics-scraper, kong) should reach Running.
With node-exporter: 5 dashboard pods + one node-exporter pod per node.

## Access

Dashboard is at `http://<YOUR-IP>` — MetalLB assigns the IP to the Kong proxy LoadBalancer.
The landing page is `/overview` — a PRTG-style cluster health summary with stat tiles, donut charts,
and (when VictoriaMetrics + node-exporter are deployed) a live network traffic graph.

### Pages

| Page | Path | Notes |
|---|---|---|
| Cluster Overview | `/overview` | Stat tiles, donut charts, network traffic graph |
| Workloads | `/workloads` | Pods, Deployments, DaemonSets, StatefulSets, ReplicaSets, Jobs |
| Services | `/services` | Services, Ingresses, Gateway API |
| Config | `/config` | ConfigMaps, Secrets |
| Storage | `/storage` | PVCs with real-time usage via kubelet stats proxy |
| Projects | `/projects` | Namespace health cards (pods, CPU/mem, health) |
| Security | `/security` | Kubescape Config Scan + Vulnerabilities (operator required) |
| RBAC | `/rbac` | ClusterRoles, Roles, Bindings |
| Registries | `/registries` | Docker registry secrets cross-referenced with pod imagePullSecrets |
| Certificates | `/certs` | TLS cert expiry tracker across all namespaces |
| Efficiency | `/efficiency` | Goldilocks-style CPU/memory right-sizing report |
| Audit | `/audit` | Polaris-style policy compliance report |
| Settings | `/settings` | Global config, notifications, event alert preferences |

## Get Login Token

```bash
kubectl get secret admin-user -n kubernetes-dashboard \
  -o jsonpath='{.data.token}' | base64 -d
```

## AI Assistant Setup

The AI Assistant (SmartToy icon in AppBar) requires an Anthropic API key.
The API pod starts fine without it — the feature returns 503 until the key is configured.

**First time:**
```bash
kubectl create secret generic kubernetes-dashboard-ai \
  --namespace kubernetes-dashboard \
  --from-literal=api-key=sk-ant-api03-... \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Rotate key:**
```bash
kubectl patch secret kubernetes-dashboard-ai \
  -n kubernetes-dashboard \
  -p '{"stringData": {"api-key": "sk-ant-api03-NEW..."}}'
kubectl rollout restart deployment/kubernetes-dashboard-api -n kubernetes-dashboard
```

Model: `claude-sonnet-4-6`. Pod context is automatically injected when the drawer is opened from a pod detail page (`/workloads/pods/:namespace/:name`).

## Rollback History

DaemonSets and StatefulSets show a **Rollback** button on their detail pages.
The dashboard reads `ControllerRevision` history from the API and lets you roll back to any
previous revision without leaving the UI. No extra config required — RBAC for `controllerrevisions`
is included in `10-rbac.yaml`.

## Shell / Exec Access

The **Exec** button on pod detail pages is RBAC-aware. It performs a `SelfSubjectAccessReview`
for `pods/exec` before rendering — users without `create` permission on that subresource see
a disabled button with a tooltip instead of a runtime error.

## Health Digest + Event Alert Notifications

Sends cluster health digest emails (daily) and real-time event alerts via the **Microsoft Graph API**.
All fields are optional — the feature is a graceful no-op if `GRAPH_TENANT_ID` is not set.

**Azure App Registration requirements:**
- API permission: `Mail.Send` (Application, not Delegated)
- `MAIL_FROM` must be a licensed mailbox in the tenant

Edit `04-notifications-secret.yaml` with real credentials, then:

```bash
kubectl apply -f 04-notifications-secret.yaml
kubectl rollout restart deployment/kubernetes-dashboard-api -n kubernetes-dashboard
```

The Settings → Notifications tab shows config status and a **Send test email** button.
Toggle individual event alert types under **Event Alerts** in the same tab.

| Alert type | Default |
|---|---|
| Pod Crash / CrashLoopBackOff | ON |
| OOM Kill | ON |
| Node Not Ready | ON |
| Image Pull Failure | OFF |
| Storage Issue (PVC) | OFF |

Each alert is deduplicated — one email per hour per affected workload.

## Global Settings

Settings → Global tab persists: cluster name, default namespace, items per page, auto-refresh interval.
Stored in the `kubernetes-dashboard-web-settings` ConfigMap — no pod restart required.


## Kubescape Integration (Optional — Security Scanning)

Detection-gated: the entire Security section (nav, workload cards, scan pages) appears automatically when
Kubescape Operator is present. No dashboard config needed.

### Deploy Kubescape Operator

```bash
helm repo add kubescape https://kubescape.github.io/helm-charts/
helm install kubescape kubescape/kubescape-operator \
  -n kubescape --create-namespace \
  --set capabilities.relevancy=enable \
  --set capabilities.networkPolicyService=enable
```

`relevancy` enables image vulnerability scanning scoped to running containers.
`networkPolicyService` generates NetworkPolicy YAML from eBPF-observed traffic.

First scan completes within a few minutes of operator startup.

**Optional — continuous scan:** trigger scans on workload changes instead of waiting for the nightly cron:

```bash
helm upgrade kubescape kubescape/kubescape-operator \
  -n kubescape \
  --set capabilities.relevancy=enable \
  --set capabilities.networkPolicyService=enable \
  --set capabilities.continuousScan=enable
```

### What it provides

| Feature | Location |
|---|---|
| Compliance score per workload | Security → Config Scan + workload detail cards |
| CVE findings per workload | Security → Vulnerabilities + workload detail cards |
| eBPF NetworkPolicy generator | Workload detail → Security card → Preview & Apply |

### RBAC

`10-rbac.yaml` already includes the permissions required for Kubescape:

```yaml
# Kubescape CRD reads (spdx.softwarecomposition.kubescape.io)
- apiGroups: ["spdx.softwarecomposition.kubescape.io"]
  resources: ["workloadconfigurationscansummaries", "workloadconfigurationscans",
              "vulnerabilitymanifestsummaries", "vulnerabilitymanifests",
              "generatednetworkpolicies"]
  verbs: ["get", "list"]
# NetworkPolicy apply (for Preview & Apply button)
- apiGroups: ["networking.k8s.io"]
  resources: ["networkpolicies"]
  verbs: ["get", "create", "patch"]
```

### Remove Kubescape

```bash
helm uninstall kubescape -n kubescape
kubectl delete namespace kubescape
```

The Security section disappears from the dashboard automatically.

> **Note:** Trivy Operator is explicitly excluded. Do not substitute `aquasecurity.github.io` CRDs.

---

## Tear Down

```bash
kubectl delete namespace kubernetes-dashboard
kubectl delete clusterrole kubernetes-dashboard-metrics-scraper
kubectl delete clusterrolebinding kubernetes-dashboard-metrics-scraper
kubectl delete clusterrolebinding admin-user
```

Note: ClusterRole and ClusterRoleBindings are cluster-scoped — deleting the namespace does not remove them.
