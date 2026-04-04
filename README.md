
# LlamaCPP + SearXNG Full Installer for Linux (Networked)

This repository provides a **full automated installer** for running **LlamaCPP** with **SearXNG** on Linux. The setup allows LlamaCPP to dynamically query SearXNG for real-time search results when generating responses.

The installer handles:

* Installing Git and Docker (if missing)
* Cleaning any old Docker remnants
* Downloading and managing LLaMA models
* Creating a Docker network for container communication
* Running both LlamaCPP and SearXNG as Docker containers
* Testing end-to-end connectivity and functionality

---

## Features

* ✅ Automated setup with minimal user interaction
* ✅ Optional persistence of Docker containers on reboot
* ✅ End-to-end tests for LlamaCPP and SearXNG connectivity
* ✅ Includes sample test scripts (`test.py`) for verification
* ✅ Friendly social links for support and community

---

## Requirements

* Linux (tested on Ubuntu 22.04+)
* `curl` installed
* Internet connection for downloading models and Docker images

---

## Installer Script Overview

```bash
#!/bin/bash
set -e
```

* **Purpose:** Ensures the script exits immediately on any error.
* **Function:** Prevents partial installations or inconsistent states.

### 1. Configuration

```bash
LLAMA_REPO="https://github.com/omgitsgb/llamacpp-searx-installer-linux.git"
LLAMA_FOLDER="llamacpp-searx-installer-linux"
MODEL="llama-3.2-1b-instruct-q8_0.gguf"
MODEL_URL="https://huggingface.co/hugging-quants/.../$MODEL"
SEARX_FOLDER="$HOME/searxng"
SEARX_SETTINGS="$SEARX_FOLDER/settings.yml"
SEARX_PORT=8080
LLAMA_PORT=8000
DOCKER_NET="llama-searx-net"
```

* Configures repository URLs, model names, folders, ports, and Docker network.

---

### 2. Install Git if missing

Checks if Git is installed; if not, installs it automatically:

```bash
if ! command -v git &>/dev/null; then
    echo "Installing Git..."
    sudo apt update
    sudo apt install -y git
fi
```

---

### 3. Clean old Docker remnants

Removes previous Docker installations, images, and volumes to avoid conflicts:

```bash
sudo apt remove -y docker.io docker-compose ... || true
sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker ...
```

---

### 4. Install Docker

Installs Docker CE and related tools:

```bash
sudo apt update
sudo apt install -y ca-certificates curl
...
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

---

### 5. Create Docker network

```bash
docker network create "$DOCKER_NET"
```

* Creates an isolated network so LlamaCPP and SearXNG can communicate.

---

### 6. Clone or update LlamaCPP repository

```bash
if [ -d "$LLAMA_FOLDER" ]; then
    git pull
else
    git clone "$LLAMA_REPO"
fi
```

* Ensures the latest version of LlamaCPP is available locally.

---

### 7. Model download

Prompts the user to download the LLaMA 3.2 1B model if it’s not already present:

```bash
read -p "Do you want to download LLaMA 3.2 1B model now? (Y/N) " -r MODEL_CHOICE
```

* Alternatively, the user can manually place the model file in the models folder.

---

### 8. Docker container persistence

Optional: keep containers running after system reboot:

```bash
read -p "Do you want the Docker containers to persist on reboot? (Y/N) " -r PERSIST_INPUT
```

---

### 9. Build and run LlamaCPP container

```bash
docker build --no-cache -t llamacpp-api "$LLAMA_FOLDER"
docker run -d $PERSIST_FLAG --network "$DOCKER_NET" -p $LLAMA_PORT:8000 --name llamacpp-api llamacpp-api
```

* Waits until the container responds to confirm it’s running properly.

---

### 10. Create SearXNG folder and settings

```bash
mkdir -p "$SEARX_FOLDER"
cat > "$SEARX_SETTINGS" <<'EOF'
...
EOF
```

* Generates a default configuration for SearXNG, with engines enabled and bot detection disabled.

---

### 11. Run SearXNG container

```bash
docker run -d $PERSIST_FLAG --network "$DOCKER_NET" --name searxng -p $SEARX_PORT:8080 \
    -v searxng-config:/etc/searxng searxng/searxng:latest
docker cp "$SEARX_SETTINGS" searxng:/etc/searxng/settings.yml
```

* Ensures LlamaCPP can query SearXNG from inside the container.

---

### 12. Connectivity checks

* Tests SearXNG from the host:

```bash
curl -s --head "http://localhost:$SEARX_PORT/search?q=hello" | grep "200 OK"
```

* Tests LlamaCPP container can reach SearXNG:

```bash
docker exec llamacpp-api bash -c "curl -s http://searxng:8080/search?q=test"
```

---

### 13. End-to-end API tests

* Tests LlamaCPP and SearXNG separately and together:

```bash
curl -s "http://localhost:$SEARX_PORT/search?q=latest+news&format=json" | jq
curl -s "${API_URL}$(echo Hello world | sed 's/ /+/g')" | jq
python3 test.py
```

---

### 14. Friendly closing message

Displays success message and social links:

```bash
echo "Setup complete. Your LlamaCPP + SearXNG environment is running."
echo "LinkedIn:  https://www.linkedin.com/in/giancarlo-bellino-02a2292a5/"
echo "Instagram: https://www.instagram.com/omgitsgb/"
echo "YouTube:   https://www.youtube.com/@OMGITSGB"
echo "GitHub:    https://github.com/omgitsgb/llamacpp-searx-installer-linux/commits?author=omgitsgb"
```

---

## Usage

1. Make the installer executable:

```bash
chmod +x installer.sh
```

2. Run the script:

```bash
./installer.sh
```

3. Access services:

   * **LlamaCPP API:** `http://localhost:8000`
   * **SearXNG:** `http://localhost:8080`

4. Use `test.py` to trigger LlamaCPP with SearXNG search integration.

---


## Troubleshooting

- If containers fail to start, check logs:

```bash
docker logs llamacpp-api
docker logs searxng
```

- If ports `8000` or `8080` are in use, either stop conflicting services or change `LLAMA_PORT` / `SEARX_PORT` in `installer.sh`.
- Ensure your Linux user has permissions to run Docker without `sudo`.

---

## Health & Connectivity Tests

### 1️⃣ List Docker containers

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
```

### 2️⃣ Test LlamaCPP health

```bash
curl -s --max-time 5 http://localhost:8000/health >/dev/null && echo "✅ LlamaCPP localhost OK" || echo "❌ LlamaCPP localhost FAIL"
```

### 3️⃣ Test SearXNG health

```bash
curl -s --max-time 5 "http://localhost:8080/search?q=test" >/dev/null && echo "✅ SearXNG localhost OK" || echo "❌ SearXNG localhost FAIL"
```

### 4️⃣ Test LlamaCPP → SearXNG connectivity

```bash
docker exec llamacpp-api bash -c "apt-get update >/dev/null 2>&1 && apt-get install -y curl >/dev/null 2>&1 && curl -s http://searxng:8080/search?q=test >/dev/null" && echo "✅ LlamaCPP can reach SearXNG" || echo "❌ LlamaCPP cannot reach SearXNG"
```

### 5️⃣ Test sample prompts

```bash
curl -s "http://localhost:8000/generate?prompt=What+is+the+latest+news+today?" | jq
curl -s "http://localhost:8000/generate?prompt=Summarize+the+top+headlines+in+technology." | jq
curl -s "http://localhost:8000/generate?prompt=Tell+me+a+fun+fact+about+space." | jq
```

---

## Fix & Remount Safely After Reboot

Stop and remove old containers:

```bash
docker stop llamacpp-api searxng
docker rm llamacpp-api searxng
```

Ensure the host folder and settings file exist and are readable:

```bash
ls -la ~/searxng
cat ~/searxng/settings.yml
```

Restart containers with proper mounts:

```bash
docker run -d --network llama-searx-net --name searxng -p 8080:8080 \
    -v "$HOME/searxng/settings.yml":/etc/searxng/settings.yml:ro searxng/searxng:latest

docker run -d --network llama-searx-net -p 8000:8000 --name llamacpp-api llamacpp-api
```

Test connectivity from LlamaCPP container:

```bash
docker exec llamacpp-api curl -s http://searxng:8080/search?q=test
```

> You should now see JSON results. ✅

---

## Option B – Using Docker volume (recommended, persistent across reboots): Stability Recommendation

Bind mounts like `-v ~/searxng/settings.yml:/etc/searxng/settings.yml` can break on restarts.  
Use a Docker volume for `/etc/searxng` instead:

```bash
docker stop llamacpp-api searxng 2>/dev/null
docker rm llamacpp-api searxng 2>/dev/null
docker rmi -f llamacpp-api searxng/searxng:latest 2>/dev/null
docker network rm llama-searx-net 2>/dev/null
docker network create llama-searx-net
docker volume rm searxng-config 2>/dev/null
docker volume create searxng-config
docker pull searxng/searxng:latest
cd C:\path\to\llamacpp-searx-installer-linux
docker build --pull -t llamacpp-api .
docker run -d --network llama-searx-net --name searxng -p 8080:8080 -v searxng-config:/etc/searxng --restart unless-stopped searxng/searxng:latest
docker cp /home/gb/searxng/settings.yml searxng:/etc/searxng
docker run -d --network llama-searx-net -p 8000:8000 --name llamacpp-api --restart unless-stopped llamacpp-api

```

Volumes persist across reboots and avoid host path issues.

---

## Sample Prompt Tests

```bash
curl -s "http://localhost:8000/generate?prompt=What+is+the+latest+news+today?" | jq
curl -s "http://localhost:8000/generate?prompt=Summarize+the+top+headlines+in+technology." | jq
curl -s "http://localhost:8000/generate?prompt=Tell+me+a+fun+fact+about+space." | jq
```

