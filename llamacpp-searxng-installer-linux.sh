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

SEARX_FOLDER="$HOME/searxng"
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
# 2. Clean old Docker remnants
# --------------------------
sudo apt remove -y docker.io docker-compose docker-compose-plugin containerd runc 2>/dev/null || true
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
echo "Building LlamaCPP Docker image (no cache)..."
docker build --no-cache -t llamacpp-api "$LLAMA_FOLDER"

docker rm -f llamacpp-api 2>/dev/null || true

echo "Starting LlamaCPP container on network $DOCKER_NET..."
docker run -d --network "$DOCKER_NET" -p $LLAMA_PORT:8000 --name llamacpp-api llamacpp-api

# Wait until LlamaCPP responds on localhost
echo "Waiting for LlamaCPP to be ready on localhost:$LLAMA_PORT..."
MAX_RETRIES=20
for i in $(seq 1 $MAX_RETRIES); do
    if curl -s "http://localhost:$LLAMA_PORT/health" >/dev/null 2>&1; then
        echo "✅ LlamaCPP is ready on localhost:$LLAMA_PORT"
        break
    else
        echo "⏳ Waiting... ($i/$MAX_RETRIES)"
        sleep 3
    fi
    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "❌ LlamaCPP did not start on localhost:$LLAMA_PORT"
        docker logs llamacpp-api
        exit 1
    fi
done

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
docker run -d --network "$DOCKER_NET" --name searxng -p $SEARX_PORT:8080 \
    -v "$SEARX_SETTINGS":/etc/searxng/settings.yml:ro searxng/searxng:latest

echo "Waiting 10 seconds for SearXNG to start..."
sleep 10

# --------------------------
# 10. Verify SearXNG connectivity from host
# --------------------------
if curl -s --head "http://localhost:$SEARX_PORT/search?q=hello" | grep "200 OK" >/dev/null; then
    echo "✅ SearXNG installed and running at http://localhost:$SEARX_PORT"
else
    echo "⚠️ SearXNG did not respond. Check logs with: docker logs searxng"
fi

# --------------------------
# 11. Test LlamaCPP to SearXNG connectivity (inside container)
# --------------------------
docker exec llamacpp-api bash -c "apt-get update && apt-get install -y curl && curl -s http://searxng:8080/search?q=test" >/dev/null \
    && echo "✅ LlamaCPP can reach SearXNG by container name" \
    || echo "⚠️ LlamaCPP cannot reach SearXNG"

# --------------------------
# 12. End-to-end API tests on localhost
# --------------------------
echo ""
echo "🔹 Running end-to-end API tests..."

API_URL="http://localhost:$LLAMA_PORT/generate?prompt="

echo ""
echo "Test 1: SearXNG search only"
curl -s "http://localhost:$SEARX_PORT/search?q=latest+news&format=json" | jq

echo ""
echo "Test 2: LLaMA only"
curl -s "${API_URL}$(echo Hello world | sed 's/ /+/g')" | jq

echo ""
echo "Test 3: LLaMA with search trigger"
curl -s "${API_URL}$(echo 'What is the latest news today?' | sed 's/ /+/g')" | jq

echo ""
echo "✅ End-to-end API tests completed!"
