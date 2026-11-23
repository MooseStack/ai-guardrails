#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
command -v podman >/dev/null || { echo "podman is required" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }

for name in nemo-demo-model nemo-demo-guardrails; do
  if podman container exists "$name"; then
    echo "Container $name already exists. Run ./podman-down.sh before starting again." >&2
    exit 1
  fi
done

echo "Building NeMo image..."
podman build -f "$SCRIPT_DIR/guardrails/Containerfile" -t localhost/nemo-demo-guardrails:local "$SCRIPT_DIR/guardrails"

podman network exists nemo-demo || podman network create nemo-demo >/dev/null
podman volume exists nemo-demo-hf || podman volume create nemo-demo-hf >/dev/null

echo "Starting oBeaver ONNX model service..."
podman run --detach --name nemo-demo-model --network nemo-demo \
  --publish 127.0.0.1:11435:8080 \
  docker.io/moosestack/onnx-obeaver_qwen3-0.6b_cpu-x86-64:latest >/dev/null

echo "Waiting for oBeaver..."
for attempt in $(seq 1 120); do
  if curl --fail --silent http://127.0.0.1:11435/health >/dev/null; then break; fi
  if [ "$attempt" -eq 120 ]; then echo "oBeaver did not start; inspect podman logs nemo-demo-model" >&2; exit 1; fi
  sleep 2
done

echo "Starting NeMo guardrail service..."
podman run --detach --name nemo-demo-guardrails --network nemo-demo \
  --publish 127.0.0.1:8001:8000 \
  --volume nemo-demo-hf:/models:Z \
  localhost/nemo-demo-guardrails:local >/dev/null

for attempt in $(seq 1 90); do
  if curl --fail --silent http://127.0.0.1:8001/v1/rails/configs >/dev/null; then break; fi
  if [ "$attempt" -eq 90 ]; then echo "NeMo did not start; inspect podman logs nemo-demo-guardrails" >&2; exit 1; fi
  sleep 2
done

echo "Guardrailed chat: http://127.0.0.1:8001/v1/chat/completions"
echo "Raw model: http://127.0.0.1:11435/v1/chat/completions"
