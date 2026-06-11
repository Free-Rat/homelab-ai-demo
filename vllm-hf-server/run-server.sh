#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODEL_PRESET="${VLLM_MODEL_PRESET:-gemma}"
HOST="${VLLM_SERVER_HOST:-0.0.0.0}"
PORT="${VLLM_SERVER_PORT:-8000}"
CLIENT_BASE_URL="${VLLM_SERVER_URL:-http://127.0.0.1:$PORT}"
MAX_MODEL_LEN="${VLLM_MAX_MODEL_LEN:-4096}"
GPU_MEMORY_UTILIZATION="${VLLM_GPU_MEMORY_UTILIZATION:-0.90}"
DTYPE="${VLLM_DTYPE:-auto}"
ENABLE_AUTO_TOOL_CHOICE="${VLLM_ENABLE_AUTO_TOOL_CHOICE:-0}"
TOOL_CALL_PARSER="${VLLM_TOOL_CALL_PARSER:-}"
PROMPT="${VLLM_DEMO_PROMPT:-Napisz jedno zdanie po polsku: kiedy warto użyć vLLM zamiast llama.cpp?}"
MAX_TOKENS="${VLLM_DEMO_MAX_TOKENS:-96}"

export PYTHONPATH="$SCRIPT_DIR/compat${PYTHONPATH:+:$PYTHONPATH}"

usage() {
  cat <<EOF
Usage: ./run-server.sh [--setup] [--check] [--serve] [--health] [--request] [--smoke-test] [--pi] [--pi-smoke-test] [--pi-tool-test] [--status] [--stop]

Options:
  --setup       Verify vLLM from nixpkgs is available.
  --check       Validate tools, Python client syntax, and resolved model path.
  --serve       Start vLLM OpenAI-compatible server.
  --health      Verify /v1/models on an already running server.
  --request     Send one chat request to an already running server.
  --smoke-test  Start vLLM, send one request, then stop it.
  --pi          Launch pi configured to use this vLLM server.
  --pi-smoke-test Send one plain non-interactive pi request to vLLM.
  --pi-tool-test Try one pi tool-calling request against vLLM.
  --status      Show whether something is listening on VLLM_SERVER_PORT.
  --stop        Stop the process listening on VLLM_SERVER_PORT.
  --model NAME  Select model preset: gemma or any HF model/path.

Environment:
  VLLM_MODEL_PRESET=$MODEL_PRESET
  VLLM_MODEL=${VLLM_MODEL:-auto-resolved}
  VLLM_SERVED_MODEL_NAME=${VLLM_SERVED_MODEL_NAME:-auto-derived}
  VLLM_SERVER_HOST=$HOST
  VLLM_SERVER_PORT=$PORT
  VLLM_SERVER_URL=$CLIENT_BASE_URL
  VLLM_MAX_MODEL_LEN=$MAX_MODEL_LEN
  VLLM_GPU_MEMORY_UTILIZATION=$GPU_MEMORY_UTILIZATION
  VLLM_DTYPE=$DTYPE
  VLLM_ENABLE_AUTO_TOOL_CHOICE=$ENABLE_AUTO_TOOL_CHOICE
  VLLM_TOOL_CALL_PARSER=$TOOL_CALL_PARSER
  HIP_VISIBLE_DEVICES=${HIP_VISIBLE_DEVICES:-0}
  ROCR_VISIBLE_DEVICES=${ROCR_VISIBLE_DEVICES:-0}
EOF
}

pi_cmd() {
  if command -v pi >/dev/null; then
    printf '%s\0' pi
  else
    command -v npx >/dev/null || { echo "pi is missing and npx is unavailable. Enter nix develop first." >&2; return 1; }
    printf '%s\0' npx --yes @earendil-works/pi-coding-agent@0.77.0
  fi
}

latest_snapshot() {
  local repo_cache="$1"
  local snapshot_dir="$repo_cache/snapshots"

  [ -d "$snapshot_dir" ] || return 1
  find "$snapshot_dir" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr \
    | sed -n '1s/^[^ ]* //p'
}

model_for() {
  case "$1" in
    gemma)
      latest_snapshot "$HOME/.cache/huggingface/hub/models--google--gemma-4-E4B-it" \
        || echo "google/gemma-4-E4B-it"
      ;;
    *) echo "$1" ;;
  esac
}

served_model_name_for() {
  case "$1" in
    gemma) echo "gemma" ;;
    */*) basename "$1" ;;
    *) basename "$1" ;;
  esac
}

MODEL="${VLLM_MODEL:-$(model_for "$MODEL_PRESET")}"
SERVED_MODEL_NAME="${VLLM_SERVED_MODEL_NAME:-$(served_model_name_for "$MODEL_PRESET")}"

venv_python() {
  command -v python3
}

vllm_cmd() {
  command -v vllm
}

setup_demo() {
  if vllm_cmd >/dev/null 2>&1; then
    echo "vLLM OK: $(vllm_cmd)"
    echo "vLLM is provided by nixpkgs in this demo. No pip setup is needed."
    python3 - <<'PY'
from mistral_common.protocol.instruct.request import ReasoningEffort

print("mistral-common compatibility shim OK:", ReasoningEffort.high.value)
PY
    return 0
  fi

  echo "vLLM missing. Enter this demo shell first: nix develop" >&2
  return 1
}

port_pid() {
  local line
  line="$(ss -ltnp "sport = :$PORT" 2>/dev/null | grep 'pid=' || true)"
  if [[ "$line" =~ pid=([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

status_server() {
  local pid
  pid="$(port_pid)"
  if [ -z "$pid" ]; then
    echo "No process is listening on port $PORT."
    return 1
  fi

  echo "Port $PORT is used by PID $pid:"
  tr '\0' ' ' <"/proc/$pid/cmdline" || true
  echo
}

stop_server() {
  local pid
  pid="$(port_pid)"
  if [ -z "$pid" ]; then
    echo "No process is listening on port $PORT."
    return 0
  fi

  echo "Stopping PID $pid on port $PORT."
  kill "$pid"
}

check_demo() {
  python3 -m py_compile "$SCRIPT_DIR/client.py"

  if vllm_cmd >/dev/null 2>&1; then
    echo "vLLM OK: $(vllm_cmd)"
  else
    echo "vLLM missing. Enter this demo shell first: nix develop" >&2
  fi
  python3 - <<'PY'
from mistral_common.protocol.instruct.request import ReasoningEffort

print("mistral-common compatibility shim OK:", ReasoningEffort.high.value)
PY

  echo "model preset: $MODEL_PRESET"
  echo "model: $MODEL"
  echo "served model name: $SERVED_MODEL_NAME"
  echo "auto tool choice: $ENABLE_AUTO_TOOL_CHOICE"
  echo "tool call parser: $TOOL_CALL_PARSER"
  if [ -d "$MODEL" ]; then
    echo "local HF snapshot OK: $MODEL"
  elif [ -f "$MODEL" ]; then
    echo "local model file OK: $MODEL"
  else
    echo "model will be resolved/downloaded by vLLM/Hugging Face if accessible."
  fi
}

serve() {
  local vllm_bin
  vllm_bin="$(vllm_cmd)" || { echo "vLLM missing. Enter this demo shell first: nix develop" >&2; exit 1; }

  if status_server >/dev/null; then
    status_server >&2
    echo "Use --request to query it, --stop to stop it, or VLLM_SERVER_PORT=<port> --serve to start another one." >&2
    exit 1
  fi

  export HIP_VISIBLE_DEVICES="${HIP_VISIBLE_DEVICES:-0}"
  export ROCR_VISIBLE_DEVICES="${ROCR_VISIBLE_DEVICES:-0}"
  export HSA_OVERRIDE_GFX_VERSION="${HSA_OVERRIDE_GFX_VERSION:-11.0.0}"

  echo "Starting vLLM on $HOST:$PORT"
  echo "Model: $MODEL"
  echo "Served model name: $SERVED_MODEL_NAME"
  if [ "$ENABLE_AUTO_TOOL_CHOICE" = "1" ]; then
    [ -n "$TOOL_CALL_PARSER" ] || { echo "VLLM_TOOL_CALL_PARSER is required when VLLM_ENABLE_AUTO_TOOL_CHOICE=1" >&2; exit 1; }
    echo "Tool calls: auto tool choice enabled with parser $TOOL_CALL_PARSER"
  else
    echo "Tool calls: auto tool choice disabled"
  fi
  echo "ROCm devices: HIP_VISIBLE_DEVICES=$HIP_VISIBLE_DEVICES ROCR_VISIBLE_DEVICES=$ROCR_VISIBLE_DEVICES"
  echo "If vLLM startup fails on this GPU, try a lower VLLM_MAX_MODEL_LEN or use ../llmfit-llama-server."

  local tool_args=()
  if [ "$ENABLE_AUTO_TOOL_CHOICE" = "1" ]; then
    tool_args=(--enable-auto-tool-choice --tool-call-parser "$TOOL_CALL_PARSER")
  fi

  exec "$vllm_bin" serve "$MODEL" \
    --host "$HOST" \
    --port "$PORT" \
    --served-model-name "$SERVED_MODEL_NAME" \
    --dtype "$DTYPE" \
    --max-model-len "$MAX_MODEL_LEN" \
    --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" \
    "${tool_args[@]}"
}

wait_for_server() {
  local python_bin
  python_bin="$(venv_python)"
  for _ in $(seq 1 240); do
    if "$python_bin" "$SCRIPT_DIR/client.py" --base-url "$CLIENT_BASE_URL" --health >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "vLLM did not become ready at $CLIENT_BASE_URL" >&2
  return 1
}

health_server() {
  "$(venv_python)" "$SCRIPT_DIR/client.py" --base-url "$CLIENT_BASE_URL" --health
}

request_server() {
  local model_id
  model_id="$(first_served_model)"

  echo "Request: $PROMPT"
  echo "Model: $model_id"
  echo "Response:"
  "$(venv_python)" "$SCRIPT_DIR/client.py" \
    --base-url "$CLIENT_BASE_URL" \
    --model "$model_id" \
    --prompt "$PROMPT" \
    --max-tokens "$MAX_TOKENS"
}

first_served_model() {
  local model_id
  model_id="$($(venv_python) "$SCRIPT_DIR/client.py" --base-url "$CLIENT_BASE_URL" --health | sed -n 's/^models: //p' | cut -d, -f1)"
  if [ -z "$model_id" ] || [ "$model_id" = "(none reported)" ]; then
    model_id="$SERVED_MODEL_NAME"
  fi
  echo "$model_id"
}

run_pi() {
  wait_for_server

  local model_id
  model_id="$(first_served_model)"

  export VLLM_OPENAI_BASE_URL="$CLIENT_BASE_URL/v1"
  export VLLM_API_KEY="${VLLM_API_KEY:-local-no-key}"
  export VLLM_PI_MODEL_ID="$model_id"
  export VLLM_PI_MODEL_NAME="$model_id via vLLM"
  export VLLM_PI_CONTEXT_WINDOW="$MAX_MODEL_LEN"
  export PI_OFFLINE="${PI_OFFLINE:-1}"
  export PI_TELEMETRY="${PI_TELEMETRY:-0}"
  export PI_SKIP_VERSION_CHECK="${PI_SKIP_VERSION_CHECK:-1}"

  local -a cmd=()
  while IFS= read -r -d '' part; do
    cmd+=("$part")
  done < <(pi_cmd)

  echo "Pi provider URL: $VLLM_OPENAI_BASE_URL"
  echo "Pi model: vllm/$model_id"
  echo "Experimental: vLLM may work as an API server, but model/tool-call behavior still depends on the checkpoint."
  exec "${cmd[@]}" \
    --extension "$SCRIPT_DIR/.pi/extensions/vllm-provider.ts" \
    --model "vllm/$model_id"
}

pi_smoke_test() {
  wait_for_server

  local model_id
  model_id="$(first_served_model)"

  export VLLM_OPENAI_BASE_URL="$CLIENT_BASE_URL/v1"
  export VLLM_API_KEY="${VLLM_API_KEY:-local-no-key}"
  export VLLM_PI_MODEL_ID="$model_id"
  export VLLM_PI_MODEL_NAME="$model_id via vLLM"
  export VLLM_PI_CONTEXT_WINDOW="$MAX_MODEL_LEN"
  export PI_OFFLINE="${PI_OFFLINE:-1}"
  export PI_TELEMETRY="${PI_TELEMETRY:-0}"
  export PI_SKIP_VERSION_CHECK="${PI_SKIP_VERSION_CHECK:-1}"

  local -a cmd=()
  while IFS= read -r -d '' part; do
    cmd+=("$part")
  done < <(pi_cmd)

  "${cmd[@]}" \
    --extension "$SCRIPT_DIR/.pi/extensions/vllm-provider.ts" \
    --model "vllm/$model_id" \
    --thinking off \
    --no-session \
    --no-tools \
    -p 'Odpowiedz dokładnie jednym słowem: DZIALA'
}

pi_tool_test() {
  wait_for_server

  local model_id
  model_id="$(first_served_model)"

  export VLLM_OPENAI_BASE_URL="$CLIENT_BASE_URL/v1"
  export VLLM_API_KEY="${VLLM_API_KEY:-local-no-key}"
  export VLLM_PI_MODEL_ID="$model_id"
  export VLLM_PI_MODEL_NAME="$model_id via vLLM"
  export VLLM_PI_CONTEXT_WINDOW="$MAX_MODEL_LEN"
  export PI_OFFLINE="${PI_OFFLINE:-1}"
  export PI_TELEMETRY="${PI_TELEMETRY:-0}"
  export PI_SKIP_VERSION_CHECK="${PI_SKIP_VERSION_CHECK:-1}"

  local -a cmd=()
  while IFS= read -r -d '' part; do
    cmd+=("$part")
  done < <(pi_cmd)

  echo "Experimental: this tests Pi tool calling. vLLM transport can work while the current model may still ignore or misformat tools."
  "${cmd[@]}" \
    --extension "$SCRIPT_DIR/.pi/extensions/vllm-provider.ts" \
    --model "vllm/$model_id" \
    --thinking off \
    --no-session \
    --tools bash,ls \
    -p 'Run `ls -la` and return only the command output.'
}

smoke_test() {
  local log_file="${VLLM_SERVER_LOG:-/tmp/homelab-vllm-demo.log}"

  if "$(venv_python)" "$SCRIPT_DIR/client.py" --base-url "$CLIENT_BASE_URL" --health >/dev/null 2>&1; then
    echo "Using already running vLLM at $CLIENT_BASE_URL"
    request_server
    return 0
  fi

  serve >"$log_file" 2>&1 &
  SMOKE_SERVER_PID=$!

  cleanup() {
    kill "$SMOKE_SERVER_PID" 2>/dev/null || true
    wait "$SMOKE_SERVER_PID" 2>/dev/null || true
  }
  trap cleanup EXIT

  for _ in $(seq 1 240); do
    if "$(venv_python)" "$SCRIPT_DIR/client.py" --base-url "$CLIENT_BASE_URL" --health >/dev/null 2>&1; then
      request_server
      cleanup
      trap - EXIT
      return 0
    fi

    if ! kill -0 "$SMOKE_SERVER_PID" 2>/dev/null; then
      echo "vLLM exited early; log follows:" >&2
      sed -n '1,180p' "$log_file" >&2
      trap - EXIT
      return 1
    fi

    sleep 2
  done

  echo "vLLM did not become ready at $CLIENT_BASE_URL; log follows:" >&2
  sed -n '1,180p' "$log_file" >&2
  cleanup
  trap - EXIT
  return 1
}

case "${1:---check}" in
  --model)
    shift
    [ $# -gt 0 ] || { echo "--model requires: gemma, HF model id, or local path" >&2; exit 2; }
    export VLLM_MODEL_PRESET="$1"
    export VLLM_MODEL="$(model_for "$1")"
    shift
    exec "$0" "${@:---check}"
    ;;
  --gemma)
    shift
    export VLLM_MODEL_PRESET="gemma"
    export VLLM_MODEL="$(model_for gemma)"
    exec "$0" "${@:---check}"
    ;;
  --setup) setup_demo ;;
  --check) check_demo ;;
  --serve) serve ;;
  --health) health_server ;;
  --request) wait_for_server; request_server ;;
  --smoke-test) smoke_test ;;
  --pi) run_pi ;;
  --pi-smoke-test) pi_smoke_test ;;
  --pi-tool-test) pi_tool_test ;;
  --status) status_server ;;
  --stop) stop_server ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
