#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Deploy the Kubernetes Dashboard
#
# Required:
#   REGISTRY   Your image registry + namespace
#
# Optional:
#   TAG        Image tag (default: latest)
#
# Examples:
#   REGISTRY=ghcr.io/myorg/kubernetes-dashboard ./deploy.sh
#   REGISTRY=myregistry:5000/kubernetes-dashboard TAG=v1.2.0 ./deploy.sh
#   REGISTRY=docker.io/myuser/kubernetes-dashboard ./deploy.sh
# =============================================================================
set -euo pipefail

: "${REGISTRY:?REGISTRY is required. Example: REGISTRY=ghcr.io/myorg/kubernetes-dashboard ./deploy.sh}"
export REGISTRY
export TAG="${TAG:-latest}"

# Auto-generate CSRF key if not provided — print it so you can save it
if [ -z "${CSRF_KEY:-}" ]; then
  CSRF_KEY="$(openssl rand 256 | base64 | tr -d '\n')"
  echo "==> Generated CSRF key (save this for future deploys):"
  echo "    export CSRF_KEY=${CSRF_KEY}"
  echo ""
fi
export CSRF_KEY

MANIFESTS="$(cd "$(dirname "$0")/manifests" && pwd)"

echo "==> Kubernetes Dashboard"
echo "    Registry: $REGISTRY"
echo "    Tag:      $TAG"
echo ""

apply() {
  envsubst < "$1" | kubectl apply -f -
}

apply_plain() {
  kubectl apply -f "$1"
}

apply_plain "$MANIFESTS/00-namespace.yaml"
apply      "$MANIFESTS/01-secrets.yaml"
apply_plain "$MANIFESTS/02-configmap.yaml"
apply_plain "$MANIFESTS/10-rbac.yaml"
apply      "$MANIFESTS/20-deployments-hardened.yaml"
apply_plain "$MANIFESTS/50-services.yaml"
apply_plain "$MANIFESTS/60-admin-user.yaml"
apply_plain "$MANIFESTS/99-network-policy.yaml"

echo ""
echo "==> Waiting for pods..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/part-of=kubernetes-dashboard \
  -n kubernetes-dashboard \
  --timeout=120s || true

echo ""
echo "==> Login token:"
kubectl get secret admin-user -n kubernetes-dashboard \
  -o jsonpath='{.data.token}' | base64 -d
echo ""
echo ""
kubectl get svc -n kubernetes-dashboard | grep -E "NAME|LoadBalancer"
