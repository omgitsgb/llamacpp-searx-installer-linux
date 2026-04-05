#!/bin/bash
set -e

# ==================================================
# LlamaCPP + SearXNG Installer with CUDA detection
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
# 0. Detect NVIDIA GPU / CUDA
# --------------------------
echo "Detecting GPU..."
HAS_GPU=false
HAS_CUDA=false
DEVICE_CHOICE="cpu"

if command -v nvidia-smi &>/dev/null; then
    HAS_GPU=true
    echo "✅ NVIDIA GPU detected"
    if command -v nvcc &>/dev/null; then
        HAS_CUDA=true
        echo "✅ CUDA toolkit installed"
    else
        echo "⚠️ CUDA toolkit not found"
    fi
else
    echo "⚠️ No NVIDIA GPU detected"
fi

# Ask user to install CUDA if GPU exists but CUDA missing
if [ "$HAS_GPU" = true ] && [ "$HAS_CUDA" = false ]; then
    read -p "CUDA toolkit not found. Install CUDA 13.1 now? (Y/N) " -r CUDA_CHOICE
    if [[ "$CUDA_CHOICE" =~ ^[Yy]$ ]]; then
        echo "Installing CUDA..."
        sudo apt update
        sudo apt install -y nvidia-cuda-toolkit
        HAS_CUDA=true
    else
        echo "Continuing without CUDA (CPU mode)"
    fi
fi

# Ask user which device to use if GPU + CUDA available
if [ "$HAS_GPU" = true ] && [ "$HAS_CUDA" = true ]; then
    read -p "Run LlamaCPP on GPU or CPU? (gpu/cpu) " -r DEVICE_INPUT
    if [[ "$DEVICE_INPUT" =~ ^[Gg][Pp][Uu]$ ]]; then
        DEVICE_CHOICE="gpu"
        echo "✅ LlamaCPP will use GPU"
    else
        DEVICE_CHOICE="cpu"
        echo "⚠️ LlamaCPP will run in CPU mode"
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
# 3. Install Docker
# --------------------------
if ! command -v docker &>/dev/null; then
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
    read -p "No model found. Download LLaMA 3.2 1B model now? (Y/N) " -r MODEL_CHOICE
    if [[ "$MODEL_CHOICE" =~ ^[Yy]$ ]]; then
        echo "Downloading model..."
        curl -L "$MODEL_URL" -o "$MODEL_PATH"
    else
        echo "Place '$MODEL' in '$LLAMA_FOLDER/models/' and rerun installer."
        exit 1
    fi
fi

# --------------------------
# 7. Ask for container persistence
# --------------------------
read -p "Persist Docker containers on reboot? (Y/N) " -r PERSIST_INPUT
if [[ "$PERSIST_INPUT" =~ ^[Yy]$ ]]; then
    PERSIST_FLAG="--restart unless-stopped"
else
    PERSIST_FLAG=""
fi

# --------------------------
# 8. Build and run LlamaCPP container
# --------------------------
echo "Building LlamaCPP Docker image..."
cd "$LLAMA_FOLDER"
docker build --no-cache -t llamacpp-api .

docker rm -f llamacpp-api 2>/dev/null || true

# GPU flag
GPU_FLAG=""
if [ "$DEVICE_CHOICE" = "gpu" ]; then
    GPU_FLAG="--gpus all"
    echo "Running container with GPU support"
else
    echo "Running container in CPU mode"
fi

docker run -d $GPU_FLAG $PERSIST_FLAG --network "$DOCKER_NET" -p $LLAMA_PORT:8000 --name llamacpp-api llamacpp-api

# --------------------------
# 9. Setup SearXNG
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
    disabled: false
EOF
chmod -R 777 "$SEARX_SETTINGS"

docker rm -f searxng 2>/dev/null || true
docker run -d $PERSIST_FLAG --network "$DOCKER_NET" --name searxng -p $SEARX_PORT:8080 \
    -v "$SEARX_FOLDER":/etc/searxng searxng/searxng:latest

# --------------------------
# 10. Wait and verify
# --------------------------
echo "Waiting 10 seconds for SearXNG..."
sleep 10
curl -s --head "http://localhost:$SEARX_PORT/search?q=hello" | grep "200 OK" && echo "✅ SearXNG OK" || echo "⚠️ SearXNG failed"

docker exec llamacpp-api bash -c "apt-get update && apt-get install -y curl && curl -s http://searxng:8080/search?q=test" >/dev/null \
    && echo "✅ LlamaCPP can reach SearXNG by container name" \
    || echo "⚠️ LlamaCPP cannot reach SearXNG"

# --------------------------
# 11. End-to-end test
# --------------------------
echo "End-to-end LlamaCPP test"
API_URL="http://localhost:$LLAMA_PORT/generate?prompt="
curl -s "${API_URL}$(echo Hello world | sed 's/ /+/g')" | jq

echo "🎉 Setup complete! Everything is under $INSTALL_FOLDER"
