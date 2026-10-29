#!/bin/bash
###############################################################################
# install-argocd.sh
#
# Installs ArgoCD into the k3s cluster, exposes the server via NodePort 30443,
# and retrieves the initial admin password.
###############################################################################
set -euo pipefail

# Ensure correct kubeconfig is loaded
if [ -z "${KUBECONFIG:-}" ] && [ -f "$HOME/.kube/ai-sre-agent-prod.yaml" ]; then
    export KUBECONFIG="$HOME/.kube/ai-sre-agent-prod.yaml"
fi

echo "=========================================================="
echo "Installing ArgoCD on k3s Cluster"
echo "=========================================================="

# 1. Create argocd namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# 2. Apply ArgoCD manifest (server-side apply avoids the 256KB annotation limit on CRDs)
echo "==> Applying official ArgoCD manifests..."
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. Expose argocd-server via NodePort 30443
echo "==> Patching argocd-server service to NodePort (port 30443)..."
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"port": 443, "targetPort": 8080, "nodePort": 30443, "name": "https"}]}}'

# 4. Wait for pods
echo "==> Waiting for ArgoCD server components to become ready..."
kubectl -n argocd rollout status deployment/argocd-server --timeout=180s

# 5. Retrieve Admin Password
echo "==> Retrieving initial admin credentials..."
ADMIN_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# 6. Retrieve Cluster Public IP (if running locally with kubeconfig)
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || true)
if [ -z "$NODE_IP" ]; then
    NODE_IP="<EC2_PUBLIC_IP>"
fi

echo ""
echo "=========================================================="
echo " ArgoCD Installation Complete! 🎉"
echo "=========================================================="
echo " Access URL: https://${NODE_IP}:30443"
echo " Username:   admin"
echo " Password:   ${ADMIN_PWD}"
echo "=========================================================="
echo ""
echo "To sync all platform applications via ArgoCD App-of-Apps:"
echo "  1. Update REPLACE_WITH_GITHUB_REPO in gitops/argocd/*.yaml with your repo URL"
echo "  2. Run: kubectl apply -f gitops/argocd/root-application.yaml"
echo "=========================================================="

