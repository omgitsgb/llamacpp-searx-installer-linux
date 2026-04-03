#!/bin/bash
set -e

# ==================================================
# LlamaCPP + SearXNG Full Installer for Linux (Networked)
# ==================================================

# --------------------------
# Configuration
# --------------------------
LLAMA_REPO="https://github.com/omgitsgb/llamacpp-searx-installer-linux.git"
LLAMA_FOLDER="llamacpp-searx-installer-linux"
MODEL="llama-3.2-1b-instruct-q8_0.gguf"
MODEL_URL="https://huggingface.co/hugging-quants/Llama-3.2-1B-Instruct-Q8_0-GGUF/resolve/main/$MODEL"

SEARX_FOLDER="/home/gb/searxng"
SEARX_SETTINGS="$SEARX_FOLDER/settings.yml"
SEARX_PORT=8080
LLAMA_PORT=8000
DOCKER_NET="llama-searx-net"

# --------------------------
# 1. Install Git if missing
# --------------------------
if ! command -v git &>/dev/null; then
    echo "Installing Git..."
    sudo apt update
    sudo apt install -y git
fi

# --------------------------
# 2. Remove old Docker / Podman remnants
# --------------------------
sudo apt remove -y $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc | cut -f1) || true
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || true
sudo apt-get autoremove -y || true
sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker /etc/apt/keyrings/docker* /etc/apt/sources.list.d/docker*

# --------------------------
# 3. Install Docker
# --------------------------
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

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
if [ -d "$LLAMA_FOLDER" ]; then
    echo "Repo exists, pulling latest changes..."
    cd "$LLAMA_FOLDER"
    git pull
    cd ..
else
    echo "Cloning repository..."
    git clone "$LLAMA_REPO"
fi

# --------------------------
# 6. Ensure models folder and download model
# --------------------------
mkdir -p "$LLAMA_FOLDER/models"
if [ ! -f "$LLAMA_FOLDER/models/$MODEL" ]; then
    echo "Downloading model..."
    curl -L "$MODEL_URL" -o "$LLAMA_FOLDER/models/$MODEL"
else
    echo "Model already exists."
fi

# --------------------------
# 7. Build and run LlamaCPP container
# --------------------------
echo "Building LlamaCPP Docker image..."
docker build -t llamacpp-api "$LLAMA_FOLDER"

docker rm -f llamacpp-api 2>/dev/null || true

echo "Starting LlamaCPP container on network $DOCKER_NET..."
docker run -d --network "$DOCKER_NET" -p $LLAMA_PORT:8000 --name llamacpp-api \
    llamacpp-api uvicorn llama_api:app --host 0.0.0.0 --port 8000

# --------------------------
# 8. Create SearXNG folder and settings
# --------------------------
mkdir -p "$SEARX_FOLDER" && chmod 755 "$SEARX_FOLDER"
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
  - name: bing
    disabled: false
  - name: yahoo
    disabled: false
  - name: qwant
    disabled: false
  - name: ecosia
    disabled: false
  - name: yandex
    disabled: false
  - name: searxng
    disabled: false
EOF
chmod 644 "$SEARX_SETTINGS"

# --------------------------
# 9. Run SearXNG container
# --------------------------
docker rm -f searxng 2>/dev/null || true
docker run -d --network "$DOCKER_NET" --name searxng \
    -p $SEARX_PORT:8080 -v "$SEARX_SETTINGS":/etc/searxng/settings.yml:ro searxng/searxng:latest

echo "Waiting 10 seconds for SearXNG to start..."
sleep 10

if curl -s --head "http://localhost:$SEARX_PORT/search?q=hello" | grep "200 OK" >/dev/null; then
    echo "✅ SearXNG installed and running at http://localhost:$SEARX_PORT"
else
    echo "⚠️ SearXNG did not respond. Check logs with: docker logs searxng"
fi

echo "✅ LlamaCPP installed and running at http://localhost:$LLAMA_PORT"
echo "✅ Setup complete! Both containers are on network $DOCKER_NET"
echo "Inside LlamaCPP, SearXNG is reachable at http://searxng:8080"

# --------------------------
# 10. Run end-to-end API tests
# --------------------------
echo ""
echo "🔹 Running end-to-end API tests..."

sleep 5  # wait for LLaMA to be ready
API_URL="http://localhost:$LLAMA_PORT/generate?prompt="

# Test 1: SearXNG search only
echo ""
echo "Test 1: SearXNG search only"
curl -s "http://localhost:$SEARX_PORT/search?q=latest+news&format=json" | jq

# Test 2: LLaMA without search trigger
echo ""
echo "Test 2: LLaMA only"
curl -s "${API_URL}$(echo Hello world | sed 's/ /+/g')" | jq

# Test 3: LLaMA with search trigger
echo ""
echo "Test 3: LLaMA with search trigger"
curl -s "${API_URL}$(echo 'What is the latest news today?' | sed 's/ /+/g')" | jq

echo ""
echo "✅ End-to-end API tests completed!"
