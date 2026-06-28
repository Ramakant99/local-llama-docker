# Llama.cpp Docker Setup

A flexible Docker Compose setup for running [llama.cpp](https://github.com/ggerganov/llama.cpp) locally with support for both CPU and GPU (NVIDIA) acceleration. Run one or two models simultaneously with an OpenAI-compatible API, or launch a standalone custom instance optimized for large reasoning models.

## Features

- **Toggle CPU/GPU** — Switch between CPU-only and GPU-accelerated modes using Docker profiles.
- **Dual-Model Stack** — Run a Planner and an Agent model simultaneously on different ports.
- **Custom Runner** — Launch a standalone, expert-tuned GPU instance for any GGUF model via `run_custom.ps1`.
- **Configurable** — Fine-tune threads, GPU layers, context size, KV cache quantization, and more via a `.env` file.
- **Model Management** — Maps a local `models/` folder to the container for easy model switching.
- **OpenAI-Compatible API** — All endpoints follow the OpenAI API spec for drop-in SDK compatibility.
- **Built-in Web UI** — Includes a bundled web interface served from the `/webui` directory.

---

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running.
- For GPU support:
  - NVIDIA GPU with latest drivers.
  - [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) installed.
  - Docker Desktop configured to use the WSL 2 based engine.

---

## Quick Start

### 1. Clone & Configure

```bash
git clone https://github.com/Ramakant99/local-llama-docker.git
cd LLamaCppDocker
```

Copy the example environment file and edit it with your settings:

```powershell
Copy-Item .env.example .env
```

Open `.env` and set at minimum:

| Variable | Description |
| :--- | :--- |
| `PLANNER_MODEL` | Filename of your Planner GGUF model in the `models/` folder. |
| `AGENT_MODEL` | Filename of your Agent GGUF model in the `models/` folder. |
| `PLANNER_GPU_LAYERS` | `0` for CPU only, or a high number (e.g., `35`) for GPU offloading. |
| `PLANNER_THREADS` | Number of physical CPU cores to allocate to the Planner. |

> **Tip:** Place your `.gguf` model files in the `models/` directory before starting the server.

### 2. Start the Server (Dual-Model Stack)

Using the PowerShell helper script:

```powershell
# Start in CPU mode (default)
.\run.ps1 -Mode cpu

# Start in GPU mode
.\run.ps1 -Mode gpu

# Start only the Planner service
.\run.ps1 -Service planner

# Start only the Agent service
.\run.ps1 -Service agent

# Start with custom ports
.\run.ps1 -Mode cpu -PlannerPort 9000 -AgentPort 9001
```

Or using Docker Compose directly:

```bash
# CPU mode (both services)
docker compose --profile cpu up -d

# Start only Planner (CPU)
docker compose --profile cpu up -d planner-cpu
```

### 3. Access the Server

| Service | Default URL |
| :--- | :--- |
| **Planner** | [http://localhost:8080](http://localhost:8080) |
| **Agent** | [http://localhost:8081](http://localhost:8081) |

---

## Custom GPU Runner (`run_custom.ps1`)

This script provides a way to run a **standalone, highly-optimized** instance of `llama-server` for any GGUF model in your `models/` directory. It is specifically tuned for large reasoning models and uses `docker run` directly (not Docker Compose).

### Quick Start

```powershell
# Run any model with default optimized settings
.\run_custom.ps1 -ModelFile "gemma/gemma-4-12b-it-Q4_K_M.gguf"

# Run with a specific context size and reasoning budget
.\run_custom.ps1 -ModelFile "gemma/gemma-4-12b-it-Q4_K_M.gguf" -CtxSize 32768 -ReasoningBudget 1024

# Run a vision model with multimodal projector
.\run_custom.ps1 -ModelFile "phi/phi-3-gguf.q4_k_m.gguf" -MmProj "phi/mmproj-BF16.gguf"

# Stop the custom container
.\run_custom.ps1 -Stop
```

### Script Parameters

| Parameter | Default | Description |
| :--- | :--- | :--- |
| `-ModelFile` | *(Required)* | The filename of the model in your `./models` folder. |
| `-Port` | `8082` | The local port to expose the API on. |
| `-GpuLayers` | `41` | Number of layers to offload to GPU. |
| `-CtxSize` | `128000` | The context window size (`--ctx-size`). |
| `-ReasoningBudget` | `-1` | Max tokens for "thinking" (`--reasoning-budget`). `-1` = unlimited. |
| `-MmProj` | *(Optional)* | Filename of the vision projector (e.g., `mmproj-BF16.gguf`). |
| `-ImageMinTokens` | `0` | Minimum tokens for image processing (vision models). |
| `-ImageMaxTokens` | `0` | Maximum tokens for image processing (vision models). |
| `-Pooling` | *(Optional)* | Pooling strategy for embeddings (e.g., `mean`, `cls`). |
| `-NoFit` | Switch | Disable the dynamic context fitting/shifting. |
| `-NoFlashAttn` | Switch | Disable Flash Attention optimization. |
| `-Stop` | Switch | Stops and removes the custom container. |

### Under the Hood: Parameter Mapping

The script applies expert-level parameters for modern reasoning models:

**Performance & VRAM Optimizations:**
- **Flash Attention** (`--flash-attn`): Enabled by default. Speeds up inference.
- **KV Cache Quantization** (`-ctk q4_0`, `-ctv q4_0`): 4-bit quantization for both Keys and Values, significantly reducing VRAM at high context.
- **Batching** (`-b 2048`, `-ub 2048`): High-throughput prompt processing batch sizes.
- **Parallelism** (`-np 1`): Maximizes resources for a single request stream.
- **Offloading**: 41 layers by default (entire model + embeddings on GPU).
- **Memory**: `--mlock` and `--no-mmap` are configurable via `.env`.

**Reasoning & Intelligence:**
- **Reasoning Budget** (`--reasoning-budget`): `-1` allows the model to think as much as it needs.
- **Chat Template**: Hardcoded `{"preserve_thinking": true}` to keep `<thought>` blocks visible in the API response.
- **Sampling**: `temp=0.6`, `top-p=0.95`, `top-k=20`, `min-p=0.0`, `presence-penalty=0.0`, `repeat-penalty=1.0`.

**Advanced Context Management:**
- **Dynamic Context Fitting** (`--fit on`): Handles context overflow by shifting/compressing rather than hard-truncating.
- **Fit Target** (`--fit-target 256`): Preserves a minimum of 256 tokens during context shifting.

### Interaction with `.env`

The `run_custom.ps1` script reads the following from your `.env` file:

| `.env` Variable | Effect |
| :--- | :--- |
| `MODELS_DIR` | Host path where your `.gguf` files are stored. |
| `IMAGE_TAG_GPU` | Docker image to use (e.g., `server-cuda`). |
| `MLOCK` | Lock model in memory (`true`/`false`). |
| `NO_MMAP` | Disable memory mapping (`true`/`false`). |
| `EMBEDDINGS` | Enable/disable the `/v1/embeddings` endpoint. |

---

## Common Usage Examples

### Running Individual Services

If you only need one model to save resources:

```powershell
# Start only the Planner (GPU mode)
.\run.ps1 -Service planner -Mode gpu

# Start only the Agent (CPU mode)
.\run.ps1 -Service agent -Mode cpu
```

### Running Both Services

```powershell
# Default (CPU mode, both services)
.\run.ps1

# Both services in GPU mode with custom ports
.\run.ps1 -Mode gpu -PlannerPort 8090 -AgentPort 8091
```

### Changing Models

1. Stop the server: `.\run.ps1 -Stop`
2. Update model filenames in `.env`.
3. Start the server again: `.\run.ps1 -Mode [cpu|gpu]`

---

## API Reference

### Base URLs

Because the dual-model stack runs two models simultaneously, you have two distinct base URLs:

| Service | Model Purpose | Default URL |
| :--- | :--- | :--- |
| **Planner** | High-level planning | `http://localhost:8080` |
| **Agent** | Tool calling / Behavior | `http://localhost:8081` |

The custom runner (`run_custom.ps1`) defaults to `http://localhost:8082`.

### OpenAI-Compatible Endpoints

The server provides a compatibility layer for the OpenAI API, allowing you to use existing OpenAI-compatible SDKs.

#### Chat Completions

**Endpoint:** `POST /v1/chat/completions`

```json
{
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello!"}
  ],
  "temperature": 0.7,
  "stream": false
}
```

#### Text Completions

**Endpoint:** `POST /v1/completions`

#### Embeddings

*(Requires `EMBEDDINGS=true` in `.env`)*

**Endpoint:** `POST /v1/embeddings`

```json
{
  "input": "The food was delicious and the service was excellent."
}
```

### Native Llama.cpp Endpoints

For more granular control, you can use the native endpoints:

| Endpoint | Method | Description |
| :--- | :--- | :--- |
| `/completion` | POST | Original llama.cpp completion endpoint |
| `/tokenize` | POST | Convert text to token IDs |
| `/detokenize` | POST | Convert token IDs back to text |
| `/health` | GET | Check server status |

### Integration Examples

#### Python (using OpenAI SDK)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8080/v1",
    api_key="sk-no-key-required"  # Or your API_KEY from .env
)

completion = client.chat.completions.create(
    model="local-model",
    messages=[
        {"role": "user", "content": "Write a python function to sort a list."}
    ]
)

print(completion.choices[0].message.content)
```

#### JavaScript / Node.js (using Fetch)

```javascript
const response = await fetch("http://localhost:8080/v1/chat/completions", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    messages: [{ role: "user", content: "What is Docker?" }],
    temperature: 0.7
  })
});

const data = await response.json();
console.log(data.choices[0].message.content);
```

#### cURL

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hi there!"}],
    "temperature": 0.2
  }'
```

---

## Environment Variables Reference

All configuration is done via the `.env` file. See [.env.example](./.env.example) for a ready-to-use template.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `MODELS_DIR` | `./models` | Path to your models folder on the host. |
| `PLANNER_MODEL` | — | GGUF filename for the Planner service. |
| `PLANNER_PORT` | `8080` | Port for the Planner API. |
| `PLANNER_THREADS` | `8` | CPU threads for Planner. |
| `PLANNER_GPU_LAYERS` | `35` | GPU layers to offload for Planner. |
| `PLANNER_CTX` | `4096` | Context window size for Planner. |
| `AGENT_MODEL` | — | GGUF filename for the Agent service. |
| `AGENT_PORT` | `8081` | Port for the Agent API. |
| `AGENT_THREADS` | `4` | CPU threads for Agent. |
| `AGENT_GPU_LAYERS` | `0` | GPU layers to offload for Agent. |
| `AGENT_CTX` | `4096` | Context window size for Agent. |
| `EMBEDDINGS` | `true` | Enable the `/v1/embeddings` endpoint. |
| `MLOCK` | `false` | Lock model in memory (prevent swapping). |
| `NO_MMAP` | `false` | Disable memory mapping (force full load). |
| `API_KEY` | *(empty)* | Optional API key for authentication. |
| `FLASH_ATTN` | `true` | Enable Flash Attention (GPU only). |
| `KV_CACHE_QUANT` | `q8_0` | KV cache quantization type. |
| `BATCH_SIZE` | `2048` | Batch size for prompt processing. |
| `REASONING_BUDGET` | `-1` | Reasoning token budget (`-1` = unlimited). |
| `PRESERVE_THINKING` | `true` | Keep `<thought>` blocks in API responses. |
| `IMAGE_TAG_CPU` | `server` | Docker image tag for CPU mode. |
| `IMAGE_TAG_GPU` | `server-cuda` | Docker image tag for GPU mode. |

---

## Operating Details

### `run.ps1` — Selective Execution

The `-Service` parameter controls what gets launched:

| Value | Behavior |
| :--- | :--- |
| `both` *(default)* | Launches both the Planner and Agent. |
| `planner` | Launches only the Planner service. |
| `agent` | Launches only the Agent service. |

The script dynamically manages environment variables and console output:
- **Environment Management**: Sets `PLANNER_PORT` and `AGENT_PORT` before starting Docker Compose.
- **Selective Logging**: Only the URLs for services actually started will be displayed.
- **Cleanup**: Every run performs `down --remove-orphans` to ensure a clean state.

---

## Troubleshooting

| Problem | Solution |
| :--- | :--- |
| **GPU not detected** | Ensure [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) is installed and Docker is configured to use it. |
| **Out of Memory** | Reduce `N_GPU_LAYERS` or context size (`PLANNER_CTX` / `AGENT_CTX` / `-CtxSize`) in your config. |
| **Container won't start** | Run `docker logs llama-planner-cpu` (or the relevant container name) to see the error. |
| **Model not found** | Ensure your `.gguf` file is placed in the `models/` directory and the filename in `.env` matches exactly. |

---

## License

This project provides Docker orchestration for [llama.cpp](https://github.com/ggerganov/llama.cpp). The llama.cpp project is licensed under the MIT License.
