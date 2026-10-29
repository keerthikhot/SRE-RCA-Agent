# OOMKilled (exit code 137)
Container exceeded its memory limit. Compare `top_pods` usage with limits. Fix: raise the memory limit in the
gitops manifest if usage is legitimate, or fix the leak. Check whether a recent deploy changed memory behaviour.
