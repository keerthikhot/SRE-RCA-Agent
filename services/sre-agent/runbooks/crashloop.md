# CrashLoopBackOff
Check `get_pod_logs previous=true`. Common causes: missing env var/secret, bad config, failed DB connection,
exit code 1 on startup. Fix: correct config in the gitops repo; do not patch the live object (ArgoCD self-heal reverts it).
