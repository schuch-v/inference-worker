<p align="center">
    <img src="https://raw.githubusercontent.com/ggml-org/llama.cpp/master/media/llama1-icon-transparent.png" alt="llama.cpp logo" width="128">
</p>

# Serverless llama.cpp inference worker for RunPod

This repository contains a serverless inference worker for running llama.cpp models on RunPod. It uses the `llama-server` image to provide an API for interacting with the models.
The following OpenAI API endpoints are supported:

- `v1/models`
- `v1/chat/completions`
- `v1/completions`

Streaming responses is also supported.

**Important!** This project is still relatively new. Please [open a new issue](https://github.com/Jacob-ML/inference-worker/issues/new) if you encounter any problems in order to get help.

**This is a fork of [SvenBrnn's `runpod-worker-ollama`](https://github.com/SvenBrnn/runpod-worker-ollama).**

## Setup

To get the best performance out of this worker, it is recommended to use cached models. Please see the [cached models documentation](./docs/cached.md) for more information, this is **highly recommended and will save many resources**.

## Configuration

The worker can be configured via environment variables set in the RunPod hub configuration:

- `LLAMA_SERVER_CMD_ARGS`: Command line arguments (argv) for the `llama-server` binary. Example: `-hf /path/to/model.gguf:Q4_K_M --ctx-size 4096`. **IMPORTANT**: Please do not define the port argument here, as the worker will always use port `3098` automatically.
- `LLAMA_CACHED_MODEL`: Hugging Face repository ID for a model attached through RunPod model caching.
- `LLAMA_CACHED_GGUF_PATH`: Main GGUF path inside the cached Hugging Face repository.
- `LLAMA_CACHED_MMPROJ_PATH`: Optional multimodal projector path inside the same cached repository. When set, the worker resolves it and starts llama.cpp with `--mmproj` automatically.
- `LLAMA_SERVER_START_TIMEOUT_SECONDS`: Maximum time to wait for llama.cpp initialization. Default is `600` seconds.
- `MAX_CONCURRENCY`: Maximum number of concurrent requests the worker can handle. Default is `8`.

### Cached multimodal example

Attach the Hugging Face repository to the endpoint as a cached model, then set:

```text
LLAMA_CACHED_MODEL=owner/model-GGUF
LLAMA_CACHED_GGUF_PATH=model-Q4_K_M.gguf
LLAMA_CACHED_MMPROJ_PATH=mmproj-model-f16.gguf
LLAMA_SERVER_CMD_ARGS=--ctx-size 32768 --jinja -ngl 999
```

Do not also put `--mmproj` in `LLAMA_SERVER_CMD_ARGS`; the worker rejects
duplicate projector configuration. Leave `LLAMA_CACHED_MMPROJ_PATH` unset for
normal text-only models.

## License

Please see the [LICENSE](./LICENSE) file for more information.

[![Runpod badge](https://api.runpod.io/badge/Jacob-ML/inference-worker)](https://console.runpod.io/hub/Jacob-ML/inference-worker)
