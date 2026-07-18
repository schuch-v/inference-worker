#!/bin/bash

set -e -o pipefail

cleanup() {
    echo "start.sh: Cleaning up..."
    pkill -P $$ 2>/dev/null || true
    exit 0
}

CACHED_MODEL_ARGS=()
CACHED_MMPROJ_ARGS=()
PYTHON_BIN="${PYTHON_BIN:-python}"
LLAMA_SERVER_BIN="${LLAMA_SERVER_BIN:-/app/llama-server}"
RUNPOD_HANDLER_SCRIPT="${RUNPOD_HANDLER_SCRIPT:-handler.py}"

resolve_cached_file() {
    local repo_path="$1"
    local resolved_path

    if ! resolved_path=$("$PYTHON_BIN" ./find_cached.py "$LLAMA_CACHED_MODEL" "$repo_path"); then
        return 1
    fi
    if [ -z "$resolved_path" ] || [ ! -f "$resolved_path" ]; then
        return 1
    fi
    printf '%s' "$resolved_path"
}

configure_cached_model() {
    local model_path
    local mmproj_path

    if [ -z "${LLAMA_CACHED_GGUF_PATH:-}" ]; then
        echo "start.sh: Error: LLAMA_CACHED_GGUF_PATH is required when LLAMA_CACHED_MODEL is set."
        exit 1
    fi

    if ! model_path=$(resolve_cached_file "$LLAMA_CACHED_GGUF_PATH"); then
        echo "start.sh: Error: Could not resolve cached model file '$LLAMA_CACHED_GGUF_PATH'."
        exit 1
    fi
    CACHED_MODEL_ARGS=(-m "$model_path")

    if [ -n "${LLAMA_CACHED_MMPROJ_PATH:-}" ]; then
        if [[ " ${LLAMA_SERVER_CMD_ARGS:-} " =~ [[:space:]](--mmproj|-mm)(=|[[:space:]]) ]]; then
            echo "start.sh: Error: Configure mmproj with either LLAMA_CACHED_MMPROJ_PATH or LLAMA_SERVER_CMD_ARGS, not both."
            exit 1
        fi
        if ! mmproj_path=$(resolve_cached_file "$LLAMA_CACHED_MMPROJ_PATH"); then
            echo "start.sh: Error: Could not resolve cached mmproj file '$LLAMA_CACHED_MMPROJ_PATH'."
            exit 1
        fi
        CACHED_MMPROJ_ARGS=(--mmproj "$mmproj_path")
    fi
}

if [ -n "${LLAMA_CACHED_MODEL:-}" ]; then
    echo "start.sh: Caching is enabled. Resolving cached files..."
    configure_cached_model
    echo "start.sh: Cached model file resolved."
    if [ ${#CACHED_MMPROJ_ARGS[@]} -gt 0 ]; then
        echo "start.sh: Cached multimodal projector resolved."
    fi
elif [ -n "${LLAMA_CACHED_MMPROJ_PATH:-}" ]; then
    echo "start.sh: Error: LLAMA_CACHED_MODEL is required when LLAMA_CACHED_MMPROJ_PATH is set."
    exit 1
else
    echo "start.sh: WARNING: Caching is disabled."
fi

if [ -z "${LLAMA_SERVER_CMD_ARGS:-}" ]; then
    echo "start.sh: Warning: LLAMA_SERVER_CMD_ARGS is not set. Using the default model."
    LLAMA_SERVER_CMD_ARGS="-hf unsloth/gemma-3-270m-it-GGUF:IQ2_XXS --ctx-size 512 -ngl 999"
fi

if [[ " $LLAMA_SERVER_CMD_ARGS " =~ [[:space:]]--port(=|[[:space:]]) ]]; then
    echo "start.sh: Error: Do not define --port in LLAMA_SERVER_CMD_ARGS; port 3098 is reserved."
    exit 1
fi

trap cleanup SIGINT SIGTERM

echo "start.sh: Stopping existing llama-server instances (if any)..."
pkill llama-server 2>/dev/null || echo "start.sh: No llama-server running"

echo "start.sh: Starting llama-server on port 3098."
touch llama.server.log

# LLAMA_SERVER_CMD_ARGS intentionally uses the worker's existing shell-style
# argument interface. Cached paths use arrays so spaces cannot split them.
LD_LIBRARY_PATH=/app "$LLAMA_SERVER_BIN" \
    "${CACHED_MODEL_ARGS[@]}" \
    "${CACHED_MMPROJ_ARGS[@]}" \
    $LLAMA_SERVER_CMD_ARGS \
    --port 3098 2>&1 | tee llama.server.log &

LLAMA_SERVER_PID=$!
START_TIMEOUT_SECONDS="${LLAMA_SERVER_START_TIMEOUT_SECONDS:-600}"
STARTED_AT=$SECONDS

echo "start.sh: Waiting for llama-server to initialize..."
while ! grep -q "listening" llama.server.log; do
    if ! kill -0 "$LLAMA_SERVER_PID" 2>/dev/null; then
        echo "start.sh: Error: llama-server exited during initialization."
        exit 1
    fi
    if [ $((SECONDS - STARTED_AT)) -ge "$START_TIMEOUT_SECONDS" ]; then
        echo "start.sh: Error: llama-server did not start within ${START_TIMEOUT_SECONDS} seconds."
        exit 1
    fi
    sleep 0.5
done

echo "start.sh: llama-server is ready; starting the RunPod handler."
"$PYTHON_BIN" -u "$RUNPOD_HANDLER_SCRIPT" "${1:-}"
