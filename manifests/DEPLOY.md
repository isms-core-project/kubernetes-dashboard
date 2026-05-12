# Kubernetes Dashboard — Raw Manifest Deployment

No Helm. Apply files in order and wait between stages.

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

`99-network-policy.yaml` enforces least-privilege traffic for all five pods:

| Pod | Ingress | Egress |
|---|---|---|
| kong | anywhere (LoadBalancer) | auth, api, web pods + DNS |
| web | kong only | DNS only |
| auth | kong only | k8s API server (443/6443) + DNS |
| api | kong only | metrics-scraper + k8s API server (443/6443) + DNS |
| metrics-scraper | api only | everywhere (must scrape all namespaces) |

To apply or remove independently:
```bash
kubectl apply -f 99-network-policy.yaml
kubectl delete -f 99-network-policy.yaml
```

## Verify

```bash
kubectl get all -n kubernetes-dashboard
```

All 5 pods (auth, api, web, metrics-scraper, kong) should reach Running.

## Access

Dashboard is at `http://10.0.0.60` — MetalLB assigns the IP to the Kong proxy LoadBalancer.

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

## Update Images

After a new build (`./build.sh --hub --api --web` etc.):

```bash
kubectl rollout restart deployment/kubernetes-dashboard-api     -n kubernetes-dashboard
kubectl rollout restart deployment/kubernetes-dashboard-web     -n kubernetes-dashboard
kubectl rollout restart deployment/kubernetes-dashboard-auth    -n kubernetes-dashboard
kubectl rollout restart deployment/kubernetes-dashboard-metrics-scraper -n kubernetes-dashboard
```

All images use `imagePullPolicy: Always` so a restart picks up the latest tag.

## Tear Down

```bash
kubectl delete namespace kubernetes-dashboard
kubectl delete clusterrole kubernetes-dashboard-metrics-scraper
kubectl delete clusterrolebinding kubernetes-dashboard-metrics-scraper
kubectl delete clusterrolebinding admin-user
```

Note: ClusterRole and ClusterRoleBindings are cluster-scoped — deleting the namespace does not remove them.
