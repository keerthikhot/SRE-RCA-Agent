# AI SRE Agent

## Run locally (uses your kubeconfig, e.g. the k3s cluster)
    python -m venv .venv && source .venv/bin/activate
    pip install -r requirements.txt
    export ANTHROPIC_API_KEY=...        # your LLM key
    export AGENT_API_KEY=devkey         # protects the HTTP API
    export ALLOWED_NAMESPACES=default
    uvicorn app:app --reload

    curl -s localhost:8000/chat -H 'x-api-key: devkey' -H 'content-type: application/json' \
      -d '{"message":"Is everything healthy in default?"}'
    curl -s localhost:8000/rca  -H 'x-api-key: devkey' -H 'content-type: application/json' \
      -d '{"question":"orders-api keeps restarting, find the root cause","email_to":[]}'
    # HTML report is written to /tmp/reports (REPORT_DIR)

## Email (AWS SES)
Verify SES_SENDER (and recipients while in sandbox), then pass "email_to": ["you@example.com"].
Needs ses:SendRawEmail via instance profile (IMDS hop limit 2) or a Secret with keys.

## Deploy in-cluster
    docker build -t ghcr.io/YOU/ai-sre-agent:<sha> . && docker push ...
    kubectl apply -f k8s/rbac.yaml
    kubectl -n ai-agent create secret generic agent-secrets \
      --from-literal=anthropic_api_key=... --from-literal=agent_api_key=...
    # put k8s/deployment.yaml in your gitops repo so ArgoCD manages it
