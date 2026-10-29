#!/bin/bash
###############################################################################
# trigger-chaos-rca.sh
#
# Simulates failure in microservices and triggers automated RCA with email!
#
# Usage:
#   ./scripts/trigger-chaos-rca.sh crash-order   [EMAIL]
#   ./scripts/trigger-chaos-rca.sh oom-product   [EMAIL]
#   ./scripts/trigger-chaos-rca.sh db-exhaustion [EMAIL]
###############################################################################
set -euo pipefail

# Ensure correct kubeconfig is loaded
if [ -z "${KUBECONFIG:-}" ] && [ -f "$HOME/.kube/ai-sre-agent-prod.yaml" ]; then
    export KUBECONFIG="$HOME/.kube/ai-sre-agent-prod.yaml"
fi

SCENARIO="${1:-crash-order}"
RECIPIENT_EMAIL="${2:-}"

# Auto-detect cluster public IP from kubeconfig if not explicitly set
CLUSTER_IP=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null | sed -E 's|https?://([^:]+):.*|\1|' || true)
if [ -z "$CLUSTER_IP" ] || [ "$CLUSTER_IP" = "kubernetes.default.svc" ]; then
    CLUSTER_IP="localhost"
fi

AGENT_HOST="${AGENT_HOST:-${CLUSTER_IP}:30080}"
ORDER_HOST="${ORDER_HOST:-${CLUSTER_IP}:30081}"
PRODUCT_HOST="${PRODUCT_HOST:-${CLUSTER_IP}:30082}"

# Auto-fetch agent_api_key from Kubernetes secret if not exported
AGENT_API_KEY="${AGENT_API_KEY:-}"
if [ -z "$AGENT_API_KEY" ]; then
    AGENT_API_KEY=$(kubectl -n ai-agent get secret agent-secrets -o jsonpath='{.data.agent_api_key}' 2>/dev/null | base64 -d 2>/dev/null || true)
fi

echo "=========================================================="
echo " RCA Chaos Injection & Diagnostic Engine"
echo " Scenario:    $SCENARIO"
echo " Order Host:  http://${ORDER_HOST}"
echo " Product Host: http://${PRODUCT_HOST}"
echo " Agent Host:  http://${AGENT_HOST}"
echo "=========================================================="

case "$SCENARIO" in
  crash-order)
    echo "==> Injecting Fatal Crash into Order Service (os._exit)..."
    curl -s -m 5 -X POST "http://${ORDER_HOST}/chaos/crash" || true
    echo "==> Crash injected. Kubernetes will detect failure and enter CrashLoopBackOff."
    ;;
  oom-product)
    echo "==> Injecting Memory Exhaustion into Product Service (/chaos/oom)..."
    curl -s -m 5 -X POST "http://${PRODUCT_HOST}/chaos/oom" || true
    echo "==> Memory spike injected. Cgroup killer will issue SIGKILL 137 (OOMKilled)."
    ;;
  db-exhaustion)
    echo "==> Simulating DB Connection Pool Exhaustion in Order Service..."
    curl -s -m 5 -X POST "http://${ORDER_HOST}/chaos/db-error" || true
    echo "==> Simulated database connection timeout."
    ;;
  *)
    echo "Unknown scenario: $SCENARIO"
    echo "Options: crash-order | oom-product | db-exhaustion"
    exit 1
    ;;
esac

echo "==> Waiting 10 seconds for Kubernetes events and logs to update..."
sleep 10

echo "==> Invoking AI SRE Agent RCA Endpoint..."
EMAIL_PAYLOAD=""
if [ -n "$RECIPIENT_EMAIL" ]; then
  EMAIL_PAYLOAD="\"email_to\": [\"$RECIPIENT_EMAIL\"],"
fi

AUTH_HEADER=()
if [ -n "$AGENT_API_KEY" ]; then
  AUTH_HEADER=(-H "x-api-key: ${AGENT_API_KEY}")
fi

RCA_RESPONSE=$(curl -s -X POST "http://${AGENT_HOST}/rca" \
  -H "Content-Type: application/json" \
  "${AUTH_HEADER[@]}" \
  -d "{
    ${EMAIL_PAYLOAD}
    \"question\": \"Investigate recent anomalies or failing pods in the apps namespace and generate an incident RCA.\"
  }")

echo ""
echo "=========================================================="
echo " Root Cause Analysis (RCA) Result"
echo "=========================================================="
echo "$RCA_RESPONSE" | jq -r '
  "Title:       " + .rca.title + "\n" +
  "Severity:    " + .rca.severity + "\n" +
  "Confidence:  " + .rca.confidence + "\n" +
  "Root Cause:  " + .rca.root_cause + "\n" +
  "Report File: " + .report_file + "\n" +
  "Emailed:     " + (.emailed | tostring)
' 2>/dev/null || echo "$RCA_RESPONSE"

echo "=========================================================="
echo "View full HTML report in browser at: http://${AGENT_HOST}/rca/latest"
echo "=========================================================="
