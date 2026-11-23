#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
command -v podman >/dev/null || { echo "podman is required" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }

for name in genai-model ibm-guardian-model nvidia-nemo-guardrails; do
  if podman container exists "$name"; then
    echo "Container $name already exists. Run ./podman-down.sh before starting again." >&2
    exit 1
  fi
done

echo "Building NeMo image..."
podman build -f "$SCRIPT_DIR/guardrails/Containerfile" -t localhost/nvidia-nemo-guardrails:local "$SCRIPT_DIR/guardrails"

podman network exists ai-guardrails || podman network create ai-guardrails >/dev/null
podman volume exists ai-guardrails-hf || podman volume create ai-guardrails-hf >/dev/null

echo "Starting oBeaver ONNX model service..."
podman run --detach --name genai-model --network ai-guardrails \
  --publish 127.0.0.1:8087:8080 \
  docker.io/moosestack/onnx-obeaver_qwen3-0.6b_cpu-x86-64:latest >/dev/null

echo "Waiting for oBeaver..."
for attempt in $(seq 1 120); do
  if curl --fail --silent http://127.0.0.1:8087/health >/dev/null; then break; fi
  if [ "$attempt" -eq 120 ]; then echo "oBeaver did not start; inspect podman logs genai-model" >&2; exit 1; fi
  sleep 2
done

echo "Starting Granite Guardian model service..."
podman run --detach --name ibm-guardian-model --network ai-guardrails \
  --publish 127.0.0.1:8086:8080 \
  docker.io/moosestack/llama-cpp_granite-guardian-4.1-8b_cpu-x86-64:latest >/dev/null

echo "Waiting for Granite Guardian..."
for attempt in $(seq 1 120); do
  if curl --fail --silent http://127.0.0.1:8086/health >/dev/null; then break; fi
  if [ "$attempt" -eq 120 ]; then echo "Granite Guardian did not start; inspect podman logs ibm-guardian-model" >&2; exit 1; fi
  sleep 2
done

echo "Starting NeMo guardrail service..."
podman run --detach --name nvidia-nemo-guardrails --network ai-guardrails \
  --publish 127.0.0.1:8001:8000 \
  --volume ai-guardrails-hf:/models:Z \
  localhost/nvidia-nemo-guardrails:local >/dev/null

for attempt in $(seq 1 90); do
  if curl --fail --silent http://127.0.0.1:8001/v1/rails/configs >/dev/null; then break; fi
  if [ "$attempt" -eq 90 ]; then echo "NeMo did not start; inspect podman logs nvidia-nemo-guardrails" >&2; exit 1; fi
  sleep 2
done

echo "Guardrailed chat: http://127.0.0.1:8001/v1/chat/completions"
echo "Raw model: http://127.0.0.1:8087/v1/chat/completions"
echo "Guardian model: http://127.0.0.1:8086/v1/chat/completions"
