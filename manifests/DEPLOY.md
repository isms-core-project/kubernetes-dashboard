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
kubectl apply -f 03-ai-secret.yaml       # Optional — AI assistant (see below)
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

The dashboard is served by the Kong proxy LoadBalancer. Get the assigned IP:

```bash
kubectl get svc kubernetes-dashboard-kong-proxy -n kubernetes-dashboard
```

### LoadBalancer Options

See `50-services.yaml` for the full options (A/B/C). The recommended approach for self-hosted clusters is MetalLB.

#### MetalLB Setup (recommended for bare-metal / on-prem)

**1. Install MetalLB (latest release):**
```bash
MetalLB_RTAG=$(curl -s https://api.github.com/repos/metallb/metallb/releases/latest \
  | grep tag_name | cut -d '"' -f 4 | sed 's/v//')
curl -s https://raw.githubusercontent.com/metallb/metallb/v${MetalLB_RTAG}/config/manifests/metallb-native.yaml \
  | kubectl apply -f -
```

**2. Configure an IP pool** (adjust the range to suit your network):
```bash
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: production
  namespace: metallb-system
spec:
  addresses:
    - 192.168.1.200-192.168.1.220
  autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
    - production
EOF
```

**3. Uncomment and set your IP** in `50-services.yaml`:
```yaml
annotations:
  metallb.io/loadBalancerIPs: "192.168.1.200"
```

#### Cloud LoadBalancer (AWS / GCP / Azure)

No annotation needed — leave the `annotations` block commented out. The cloud provider assigns an IP automatically when `type: LoadBalancer` is applied.

#### NodePort (no LoadBalancer controller)

Change `type: LoadBalancer` to `type: NodePort` in `50-services.yaml`. Access via `http://<any-node-ip>:<nodePort>` — the port is assigned by Kubernetes and visible in `kubectl get svc -n kubernetes-dashboard`.

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
