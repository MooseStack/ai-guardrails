#!/usr/bin/env bash
set -euo pipefail

for name in nvidia-nemo-guardrails ibm-guardian-model genai-model nemo-demo-gateway nemo-demo-guardrails nemo-demo-guardian nemo-demo-model; do
  if podman container exists "$name"; then podman rm --force "$name" >/dev/null; fi
done
for network in ai-guardrails nemo-demo; do
  if podman network exists "$network"; then podman network rm "$network" >/dev/null; fi
done
echo "Guardrails containers stopped. Cached Hugging Face classifier weights remain in a Podman volume."
