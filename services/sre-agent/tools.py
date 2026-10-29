"""Read-only Kubernetes tools the agent can call. Every tool is namespace-allowlisted,
logs are redacted, and all output is wrapped as untrusted data before the LLM sees it."""
import os, re, glob, json, logging
from datetime import datetime, timezone
from kubernetes import client, config

logger = logging.getLogger("sre-agent.tools")

def init_k8s_client():
    try:
        config.load_incluster_config()
        logger.info("Loaded in-cluster kubernetes configuration")
    except config.ConfigException:
        try:
            config.load_kube_config()
            logger.info("Loaded local kubeconfig")
        except Exception as e:
            logger.warning("Could not load in-cluster or local kubeconfig: %s. Kubernetes calls will fail if not configured.", e)

init_k8s_client()

core = client.CoreV1Api()
apps = client.AppsV1Api()
custom = client.CustomObjectsApi()

ALLOWED_RAW = os.getenv("ALLOWED_NAMESPACES", "default,apps,ai-agent,argocd,kube-system")
ALLOWED = {n.strip() for n in ALLOWED_RAW.split(",") if n.strip()}
RUNBOOK_DIR = os.getenv("RUNBOOK_DIR", "runbooks")
ARGO_NS = os.getenv("ARGOCD_NAMESPACE", "argocd")

_KV = re.compile(r"(?i)(password|passwd|secret|token|api[_-]?key|authorization)(\"?\s*[:=]\s*\"?)([^\s\",;]+)")
_OTHER = [re.compile(r"AKIA[0-9A-Z]{16}"),
          re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")]

def redact(text: str) -> str:
    if not text:
        return ""
    text = _KV.sub(r"\1\2[REDACTED]", text)
    for p in _OTHER:
        text = p.sub("[REDACTED]", text)
    return text

def _ns(ns: str):
    if "*" not in ALLOWED and ns not in ALLOWED:
        raise ValueError(f"namespace '{ns}' not allowed; allowed: {sorted(ALLOWED)}")

def _state(s):
    if s is None: return None
    if s.waiting: return {"waiting": s.waiting.reason, "message": s.waiting.message}
    if s.terminated: return {"terminated": s.terminated.reason, "exit_code": s.terminated.exit_code}
    if s.running: return {"running_since": str(s.running.started_at)}

def list_pods(namespace):
    _ns(namespace)
    now = datetime.now(timezone.utc)
    out = []
    pods = core.list_namespaced_pod(namespace).items
    for p in pods:
        cs = p.status.container_statuses or []
        out.append({
            "name": p.metadata.name,
            "phase": p.status.phase,
            "ready": f"{sum(1 for c in cs if c.ready)}/{len(cs)}",
            "restarts": sum(c.restart_count for c in cs),
            "waiting": [c.state.waiting.reason for c in cs if c.state and c.state.waiting],
            "age_min": int((now - p.metadata.creation_timestamp).total_seconds() / 60) if p.metadata.creation_timestamp else 0
        })
    return out

def describe_pod(namespace, pod):
    _ns(namespace)
    p = core.read_namespaced_pod(pod, namespace)
    spec = {c.name: c for c in p.spec.containers}
    cons = []
    for c in p.status.container_statuses or []:
        last = c.last_state.terminated if c.last_state else None
        res = spec[c.name].resources if c.name in spec else None
        cons.append({
            "name": c.name,
            "image": c.image,
            "ready": c.ready,
            "restarts": c.restart_count,
            "state": _state(c.state),
            "last_terminated": {
                "reason": last.reason,
                "exit_code": last.exit_code,
                "finished_at": str(last.finished_at)
            } if last else None,
            "requests": res.requests if res else {},
            "limits": res.limits if res else {}
        })
    return {
        "phase": p.status.phase,
        "node": p.spec.node_name,
        "containers": cons,
        "conditions": [{"type": c.type, "status": c.status, "reason": c.reason}
                       for c in (p.status.conditions or [])]
    }

def get_events(namespace, limit=30):
    _ns(namespace)
    evs = core.list_namespaced_event(namespace).items
    key = lambda e: e.last_timestamp or e.event_time or e.metadata.creation_timestamp or datetime.now(timezone.utc)
    evs.sort(key=key, reverse=True)
    return [{
        "time": str(key(e)),
        "type": e.type,
        "reason": e.reason,
        "count": e.count,
        "object": f"{e.involved_object.kind}/{e.involved_object.name}" if e.involved_object else "",
        "message": e.message
    } for e in evs[:min(int(limit), 60)]]

def get_pod_logs(namespace, pod, container=None, tail_lines=100, previous=False):
    _ns(namespace)
    try:
        logs = core.read_namespaced_pod_log(
            pod, namespace, container=container, previous=bool(previous),
            tail_lines=min(int(tail_lines), 300), timestamps=True
        )
    except client.ApiException as e:
        return f"log fetch failed: {e.status} {e.reason}"
    return redact(logs)[-12000:]

def get_deployment(namespace, name):
    _ns(namespace)
    d = apps.read_namespaced_deployment(name, namespace)
    sel = ",".join(f"{k}={v}" for k, v in (d.spec.selector.match_labels or {}).items())
    rs = apps.list_namespaced_replica_set(namespace, label_selector=sel).items
    hist = sorted(({
        "revision": r.metadata.annotations.get("deployment.kubernetes.io/revision") if r.metadata.annotations else "unknown",
        "images": [c.image for c in r.spec.template.spec.containers],
        "created": str(r.metadata.creation_timestamp),
        "replicas": r.status.replicas
    } for r in rs), key=lambda x: x["created"], reverse=True)[:5]
    return {
        "desired": d.spec.replicas,
        "ready": d.status.ready_replicas,
        "available": d.status.available_replicas,
        "conditions": [{"type": c.type, "status": c.status, "reason": c.reason, "message": c.message}
                       for c in (d.status.conditions or [])],
        "rollout_history": hist
    }

def top_pods(namespace):
    _ns(namespace)
    try:
        m = custom.list_namespaced_custom_object("metrics.k8s.io", "v1beta1", namespace, "pods")
    except Exception as e:
        return f"metrics unavailable: {e}"
    return [{
        "pod": i["metadata"]["name"],
        "containers": [{"name": c["name"], "cpu": c["usage"]["cpu"], "memory": c["usage"]["memory"]}
                       for c in i["containers"]]
    } for i in m.get("items", [])]

def list_argocd_apps():
    try:
        items = custom.list_namespaced_custom_object("argoproj.io", "v1alpha1", ARGO_NS, "applications")["items"]
        return [{
            "name": a["metadata"]["name"],
            "sync": a.get("status", {}).get("sync", {}).get("status"),
            "health": a.get("status", {}).get("health", {}).get("status")
        } for a in items]
    except Exception as e:
        return f"argocd not installed or unreachable in {ARGO_NS}: {e}"

def get_argocd_app(name):
    try:
        a = custom.get_namespaced_custom_object("argoproj.io", "v1alpha1", ARGO_NS, "applications", name)
        st = a.get("status", {})
        return {
            "sync": st.get("sync", {}).get("status"),
            "health": st.get("health", {}).get("status"),
            "revision": st.get("sync", {}).get("revision"),
            "recent_deploys": [{"deployedAt": h.get("deployedAt"), "revision": h.get("revision")}
                               for h in st.get("history", [])[-5:]],
            "conditions": st.get("conditions")
        }
    except Exception as e:
        return f"argocd app '{name}' not found: {e}"

def search_runbooks(query):
    terms = [t for t in re.findall(r"\w+", query.lower()) if len(t) > 2]
    scored = []
    for path in glob.glob(f"{RUNBOOK_DIR}/*.md"):
        try:
            text = open(path, encoding="utf-8").read()
            score = sum(text.lower().count(t) for t in terms)
            if score:
                scored.append((score, path, text[:3000]))
        except Exception:
            pass
    scored.sort(reverse=True)
    return [{"file": p, "content": t} for _, p, t in scored[:2]] or "no matching runbook"

def scan_cluster_for_issues():
    """Scans all allowed namespaces and identifies any pods in CrashLoopBackOff, Error, OOMKilled, or high restart count."""
    issues = []
    namespaces_to_check = [ns for ns in ALLOWED if ns != "*"]
    for ns in namespaces_to_check:
        try:
            pods = core.list_namespaced_pod(ns).items
            for p in pods:
                cs = p.status.container_statuses or []
                total_restarts = sum(c.restart_count for c in cs)
                reasons = []
                last_reason = None
                last_exit = None

                for c in cs:
                    if c.state and c.state.waiting:
                        reasons.append(c.state.waiting.reason)
                    if c.last_state and c.last_state.terminated:
                        last_reason = c.last_state.terminated.reason
                        last_exit = c.last_state.terminated.exit_code

                is_problematic = (
                    p.status.phase in ["Failed", "Pending"] or
                    total_restarts > 0 or
                    any(r in ["CrashLoopBackOff", "Error", "OOMKilled", "ImagePullBackOff", "CreateContainerConfigError"] for r in reasons) or
                    last_reason in ["OOMKilled", "Error"]
                )

                if is_problematic:
                    issues.append({
                        "namespace": ns,
                        "pod": p.metadata.name,
                        "phase": p.status.phase,
                        "restarts": total_restarts,
                        "waiting_reasons": reasons,
                        "last_termination_reason": last_reason,
                        "last_exit_code": last_exit
                    })
        except Exception as e:
            logger.warning("Could not list pods in %s: %s", ns, e)
    return issues

def _schema(props, required):
    return {"type": "object", "properties": props, "required": required}

NS = {"namespace": {"type": "string"}}
POD = {**NS, "pod": {"type": "string"}}

TOOLS = {
    "list_pods": (list_pods, "List pods with phase, readiness, restarts, waiting reasons.", _schema(NS, ["namespace"])),
    "describe_pod": (describe_pod, "Container states, last termination reason/exit code (e.g. OOMKilled), resources.", _schema(POD, ["namespace", "pod"])),
    "get_events": (get_events, "Recent Kubernetes events in a namespace (newest first).", _schema({**NS, "limit": {"type": "integer"}}, ["namespace"])),
    "get_pod_logs": (get_pod_logs, "Tail logs of a pod. Set previous=true for the last crashed container.",
                     _schema({**POD, "container": {"type": "string"}, "tail_lines": {"type": "integer"}, "previous": {"type": "boolean"}}, ["namespace", "pod"])),
    "get_deployment": (get_deployment, "Deployment status, conditions and rollout history (images per revision).",
                       _schema({**NS, "name": {"type": "string"}}, ["namespace", "name"])),
    "top_pods": (top_pods, "Current CPU/memory usage per pod.", _schema(NS, ["namespace"])),
    "list_argocd_apps": (list_argocd_apps, "List ArgoCD applications with sync/health status.", _schema({}, [])),
    "get_argocd_app": (get_argocd_app, "ArgoCD app sync status and recent deploy revisions (correlate failures with deploys).",
                       _schema({"name": {"type": "string"}}, ["name"])),
    "search_runbooks": (search_runbooks, "Keyword search of internal runbooks for known fixes.", _schema({"query": {"type": "string"}}, ["query"])),
    "scan_cluster_for_issues": (scan_cluster_for_issues, "Scan all allowlisted namespaces for failed/restarting pods.", _schema({}, [])),
}

TOOL_SCHEMAS = [{"name": n, "description": d, "input_schema": s} for n, (_, d, s) in TOOLS.items()]

def call_tool(name: str, args: dict) -> str:
    try:
        result = TOOLS[name][0](**args)
    except Exception as e:
        result = {"error": f"{type(e).__name__}: {e}"}
    text = result if isinstance(result, str) else json.dumps(result, default=str)
    return f"<untrusted_data>\n{text[:15000]}\n</untrusted_data>"
