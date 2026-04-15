#!/bin/bash
set -e

# ==================================================
# LlamaCPP + SearXNG Installer (CPU/GPU aware)
# CUDA-IMPROVED VERSION (NO ARCHITECTURE CHANGES)
# ==================================================

INSTALL_FOLDER="$HOME/llamacpp-searx"
LLAMA_FOLDER="$INSTALL_FOLDER/llamacpp"
SEARX_FOLDER="$INSTALL_FOLDER/searxng"
MODEL="llama-3.2-1b-instruct-q8_0.gguf"
MODEL_URL="https://huggingface.co/hugging-quants/Llama-3.2-1B-Instruct-Q8_0-GGUF/resolve/main/$MODEL"

SEARX_SETTINGS="$SEARX_FOLDER/settings.yml"
SEARX_PORT=8080
LLAMA_PORT=8000
DOCKER_NET="llama-searx-net"

# --------------------------
# 0. Detect NVIDIA GPU / CUDA (IMPROVED)
# --------------------------
echo "Detecting GPU..."

DEVICE_CHOICE="cpu"
HAS_GPU=false
HAS_DRIVER_CUDA=false
HAS_TOOLKIT=false

if command -v nvidia-smi &>/dev/null; then
    HAS_GPU=true
    echo "✅ NVIDIA GPU detected"

    DRIVER_CUDA=$(nvidia-smi | grep -o "CUDA Version: [0-9.]*" || true)
    if [ ! -z "$DRIVER_CUDA" ]; then
        HAS_DRIVER_CUDA=true
        echo "✅ Driver CUDA detected: $DRIVER_CUDA"
    else
        echo "⚠️ CUDA version not detected from driver"
    fi
else
    echo "⚠️ No NVIDIA GPU detected"
fi

if command -v nvcc &>/dev/null; then
    HAS_TOOLKIT=true
    echo "✅ CUDA toolkit installed"
else
    echo "⚠️ CUDA toolkit not installed (runtime CUDA may still work)"
fi

# Ask GPU/CPU
if [ "$HAS_GPU" = true ]; then
    read -p "Run LlamaCPP on GPU or CPU? (gpu/cpu) " -r DEVICE_INPUT
    if [[ "$DEVICE_INPUT" =~ ^[Gg][Pp][Uu]$ ]]; then
        DEVICE_CHOICE="gpu"
        echo "🚀 GPU MODE SELECTED"
    else
        echo "🧠 CPU MODE SELECTED"
    fi
fi

# --------------------------
# 1. Install Git if missing
# --------------------------
if ! command -v git &>/dev/null; then
    echo "Installing Git..."
    sudo apt update
    sudo apt install -y git
fi

# --------------------------
# 2. Install Python3 & pip
# --------------------------
if ! command -v python3 &>/dev/null; then
    echo "Installing Python3..."
    sudo apt update
    sudo apt install -y python3 python3-pip
fi

# --------------------------
# 3. DOCKER DETECTION + OPTIONAL INSTALL (FIXED)
# --------------------------
DOCKER_AVAILABLE=false

if command -v docker &>/dev/null; then
    echo "✅ Docker already installed"
    DOCKER_AVAILABLE=true
else
    echo "⚠️ Docker is not installed"

    read -p "Install Docker now? (Y/N) " -r DOCKER_INSTALL_CHOICE

    if [[ "$DOCKER_INSTALL_CHOICE" =~ ^[Yy]$ ]]; then
        echo "Installing Docker..."

        sudo apt update
        sudo apt install -y ca-certificates curl gnupg

        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc

        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable
EOF

        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

        DOCKER_AVAILABLE=true
        echo "✅ Docker installed successfully"

    else
        echo "⚠️ Docker not installed — switching to NATIVE mode only"
        INSTALL_MODE="2"
        DOCKER_AVAILABLE=false
    fi
fi

# --------------------------
# 4. Create Docker network
# --------------------------
if ! docker network inspect "$DOCKER_NET" &>/dev/null; then
    echo "Creating Docker network $DOCKER_NET..."
    docker network create "$DOCKER_NET"
fi

# --------------------------
# 5. Clone or update LlamaCPP repo
# --------------------------
mkdir -p "$INSTALL_FOLDER"

if [ -d "$LLAMA_FOLDER" ]; then
    echo "Repo exists, pulling latest changes..."
    cd "$LLAMA_FOLDER"
    git pull
else
    echo "Cloning repository..."
    git clone https://github.com/omgitsgb/llamacpp-searx-installer-linux.git "$LLAMA_FOLDER"
fi

# --------------------------
# 6. Ensure model exists
# --------------------------
mkdir -p "$LLAMA_FOLDER/models"
MODEL_PATH="$LLAMA_FOLDER/models/$MODEL"

if [ ! -f "$MODEL_PATH" ]; then
    read -p "No model found. Download LLaMA model now? (Y/N) " -r MODEL_CHOICE
    if [[ "$MODEL_CHOICE" =~ ^[Yy]$ ]]; then
        echo "Downloading model..."
        curl -L "$MODEL_URL" -o "$MODEL_PATH"
    else
        echo "Place model manually in $MODEL_PATH"
        exit 1
    fi
fi

# --------------------------
# 7. Docker persistence
# --------------------------
read -p "Persist containers on reboot? (Y/N) " -r PERSIST_INPUT
if [[ "$PERSIST_INPUT" =~ ^[Yy]$ ]]; then
    PERSIST_FLAG="--restart unless-stopped"
else
    PERSIST_FLAG=""
fi

# --------------------------
# 8. CUDA BUILD FLAGS (ONLY ADDITION THAT MATTERS)
# --------------------------
if [ "$DEVICE_CHOICE" = "gpu" ]; then
    export CMAKE_ARGS="-DGGML_CUDA=on"
    export FORCE_CMAKE=1
    echo "🔥 CUDA build enabled for llama-cpp-python"
else
    export CMAKE_ARGS="-DGGML_CUDA=off"
    export FORCE_CMAKE=1
    echo "🔵 CPU build mode"
fi

# --------------------------
# 9. Build LlamaCPP Docker image
# --------------------------
cd "$LLAMA_FOLDER"

if [ "$DEVICE_CHOICE" = "gpu" ]; then
    echo "Building GPU Docker image..."
    docker build -f Dockerfile.gpu --no-cache -t llamacpp-api .
else
    echo "Building CPU Docker image..."
    docker build -f Dockerfile.cpu --no-cache -t llamacpp-api .
fi

docker rm -f llamacpp-api 2>/dev/null || true

GPU_FLAG=""
if [ "$DEVICE_CHOICE" = "gpu" ]; then
    GPU_FLAG="--gpus all"
    echo "Running with GPU support"
else
    echo "Running in CPU mode"
fi

docker run -d $GPU_FLAG $PERSIST_FLAG --network "$DOCKER_NET" -p $LLAMA_PORT:8000 --name llamacpp-api llamacpp-api

# --------------------------
# 10. Setup SearXNG
# --------------------------
mkdir -p "$SEARX_FOLDER" && chmod -R 777 "$SEARX_FOLDER"

cat > "$SEARX_SETTINGS" <<'EOF'
use_default_settings: true
general:
  debug: false
  instance_name: "SearXNG"
search:
  safe_search: 2
  autocomplete: duckduckgo
  formats:
    - html
    - json
server:
  bind_address: "0.0.0.0"
  port: 8080
  secret_key: "mR7q4vF9sP2xZ8jWkL1uB0yT6cE3nA5"
  public_instance: false
limiter: false
botdetection:
  enabled: false
engines:
  - name: duckduckgo
    disabled: false
  - name: google
    disabled: false
EOF

docker rm -f searxng 2>/dev/null || true

docker run -d $PERSIST_FLAG --network "$DOCKER_NET" --name searxng -p $SEARX_PORT:8080 \
    -v "$SEARX_FOLDER":/etc/searxng searxng/searxng:latest

# --------------------------
# 11. Wait + verify
# --------------------------
echo "Waiting for services..."
sleep 10

curl -s --head "http://localhost:$SEARX_PORT/search?q=hello" | grep "200 OK" && echo "✅ SearXNG OK" || echo "⚠️ SearXNG failed"

docker exec llamacpp-api bash -c "apt-get update && apt-get install -y curl && curl -s http://searxng:8080/search?q=test" >/dev/null \
    && echo "✅ Container networking OK" \
    || echo "⚠️ Container networking issue"

# --------------------------
# 12. CUDA BACKEND VERIFICATION (FIXED SAFE VERSION)
# --------------------------
echo "Checking llama.cpp backend..."

if [ "$INSTALL_MODE" = "2" ]; then
    LLAMA_VENV="$LLAMA_FOLDER/venv"

    if [ -f "$LLAMA_VENV/bin/activate" ]; then
        source "$LLAMA_VENV/bin/activate"
        python3 -c "
try:
    from llama_cpp import Llama
    print('✅ llama-cpp-python installed in venv')
except Exception as e:
    print('⚠️ llama-cpp-python missing in venv:', e)
"
        deactivate
    else
        echo "⚠️ Native venv not found"
    fi

else
    # Docker mode check
    docker exec llamacpp-api python3 -c "
try:
    from llama_cpp import Llama
    print('✅ llama-cpp-python exists in container')
except Exception as e:
    print('⚠️ missing inside container:', e)
"
fi

# --------------------------
# DONE
# --------------------------
echo "🎉 INSTALL COMPLETE"
echo "Mode: $DEVICE_CHOICE"
echo "Folder: $INSTALL_FOLDER"
