#!/usr/bin/env bash
set -euo pipefail

for name in nemo-demo-gateway nemo-demo-guardrails nemo-demo-model; do
  if podman container exists "$name"; then podman rm --force "$name" >/dev/null; fi
done
if podman network exists nemo-demo; then podman network rm nemo-demo >/dev/null; fi
echo "Demo containers stopped. Cached Hugging Face classifier weights remain in a Podman volume."
