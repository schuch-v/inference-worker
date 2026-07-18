#!/bin/bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

MODEL_ID="Owner/MixedCase-GGUF"
MODEL_FILE="model.gguf"
MMPROJ_FILE="mmproj-f16.gguf"
SNAPSHOT_DIR="$TEST_ROOT/cache/models--Owner--MixedCase-GGUF/snapshots/commit"
mkdir -p "$SNAPSHOT_DIR"
touch "$SNAPSHOT_DIR/$MODEL_FILE" "$SNAPSHOT_DIR/$MMPROJ_FILE"

cat > "$TEST_ROOT/fake-llama-server" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$ARGS_OUTPUT"
echo "listening"
sleep 1
EOF
chmod +x "$TEST_ROOT/fake-llama-server"

cat > "$TEST_ROOT/fake-handler.py" <<'EOF'
print("handler-ready")
EOF

run_worker() {
    (
        cd "$REPO_ROOT/src"
        RUNPOD_HF_CACHE_DIR="$TEST_ROOT/cache" \
        LLAMA_SERVER_BIN="$TEST_ROOT/fake-llama-server" \
        RUNPOD_HANDLER_SCRIPT="$TEST_ROOT/fake-handler.py" \
        ARGS_OUTPUT="$TEST_ROOT/args" \
        LLAMA_CACHED_MODEL="$MODEL_ID" \
        LLAMA_CACHED_GGUF_PATH="$MODEL_FILE" \
        LLAMA_CACHED_MMPROJ_PATH="${1:-}" \
        LLAMA_SERVER_CMD_ARGS="${2:---ctx-size 4096 --jinja -ngl 999}" \
        LLAMA_SERVER_START_TIMEOUT_SECONDS=10 \
        bash ./start.sh
    )
}

run_worker "$MMPROJ_FILE"
grep -Fx -- "-m" "$TEST_ROOT/args"
grep -E "[/\\\\]${MODEL_FILE}$" "$TEST_ROOT/args"
grep -Fx -- "--mmproj" "$TEST_ROOT/args"
grep -E "[/\\\\]${MMPROJ_FILE}$" "$TEST_ROOT/args"
grep -Fx -- "--port" "$TEST_ROOT/args"
grep -Fx -- "3098" "$TEST_ROOT/args"

run_worker ""
if grep -Fxq -- "--mmproj" "$TEST_ROOT/args"; then
    echo "text-only startup unexpectedly added --mmproj" >&2
    exit 1
fi

if run_worker "$MMPROJ_FILE" "--ctx-size 4096 --mmproj duplicate.gguf"; then
    echo "duplicate mmproj configuration unexpectedly succeeded" >&2
    exit 1
fi
