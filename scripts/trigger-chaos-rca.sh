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
AGENT_HOST="${AGENT_HOST:-localhost:30080}"
ORDER_HOST="${ORDER_HOST:-localhost:30081}"
PRODUCT_HOST="${PRODUCT_HOST:-localhost:30082}"

echo "=========================================================="
echo " RCA Chaos Injection & Diagnostic Engine"
echo " Scenario: $SCENARIO"
echo "=========================================================="

case "$SCENARIO" in
  crash-order)
    echo "==> Injecting Fatal Crash into Order Service (os._exit)..."
    curl -s -X POST "http://${ORDER_HOST}/chaos/crash" || true
    echo "==> Crash injected. Kubernetes will detect failure and enter CrashLoopBackOff."
    ;;
  oom-product)
    echo "==> Injecting Memory Exhaustion into Product Service (/chaos/oom)..."
    curl -s -X POST "http://${PRODUCT_HOST}/chaos/oom" || true
    echo "==> Memory spike injected. Cgroup killer will issue SIGKILL 137 (OOMKilled)."
    ;;
  db-exhaustion)
    echo "==> Simulating DB Connection Pool Exhaustion in Order Service..."
    curl -s -X POST "http://${ORDER_HOST}/chaos/db-error" || true
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

RCA_RESPONSE=$(curl -s -X POST "http://${AGENT_HOST}/rca" \
  -H "Content-Type: application/json" \
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

