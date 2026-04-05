
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
Ah—got it. You want a **manual, step-by-step approach** to what your installer does, as if the script didn’t exist. Let’s break it down **carefully, from scratch**, so you could do each part by hand and understand it. I’ll assume we’re starting on a fresh Ubuntu system.

---

## **Step 0: Prerequisites**

Make sure you have:

* Linux (Ubuntu 22.04+ recommended)
* `curl` installed
* Internet access
* `sudo` privileges

Check `curl` and `git`:

```bash
curl --version
git --version
```

If missing, install them:

```bash
sudo apt update
sudo apt install -y curl git ca-certificates
```

---

## **Step 1: Clean any old Docker remnants**

If Docker or previous installs exist, remove them to avoid conflicts:

```bash
sudo apt remove -y docker.io docker-compose docker-compose-plugin containerd runc || true
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || true
sudo apt-get autoremove -y
sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker /etc/apt/keyrings/docker* /etc/apt/sources.list.d/docker*
```

This ensures a clean slate.

---

## **Step 2: Install Docker (manually)**

1. Add Docker’s official GPG key:

```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
```

2. Add the Docker repository:

```bash
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable
EOF
```

3. Update and install Docker:

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

4. Verify Docker:

```bash
docker --version
sudo docker run hello-world
```

Optional: run Docker without `sudo`:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

---

## **Step 3: Create a Docker network**

This allows LlamaCPP and SearXNG containers to communicate by name:

```bash
docker network create llama-searx-net
```

---

## **Step 4: Clone LlamaCPP repository**

```bash
git clone https://github.com/omgitsgb/llamacpp-searx-installer-linux.git
cd llamacpp-searx-installer-linux
```

Or, if already cloned:

```bash
cd llamacpp-searx-installer-linux
git pull
```

---

## **Step 5: Download LLaMA 3.2 1B model**

Create a models folder:

```bash
mkdir -p models
```

Download the model (or manually place it in `models/`):

```bash
curl -L -o models/llama-3.2-1b-instruct-q8_0.gguf https://huggingface.co/hugging-quants/Llama-3.2-1B-Instruct-Q8_0-GGUF/resolve/main/llama-3.2-1b-instruct-q8_0.gguf
```

---

## **Step 6: Build LlamaCPP Docker image**

```bash
docker build --no-cache -t llamacpp-api .
```

---

## **Step 7: Start LlamaCPP container**

```bash
docker run -d --network llama-searx-net -p 8000:8000 --name llamacpp-api llamacpp-api
```

Check it’s ready:

```bash
curl http://localhost:8000/health
```

---

## **Step 8: Create SearXNG folder and settings**

```bash
mkdir -p ~/searxng
cat > ~/searxng/settings.yml <<'EOF'
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
```

---

## **Step 9: Run SearXNG container**

```bash
docker volume create searxng-config
docker run -d --network llama-searx-net -p 8080:8080 --name searxng -v searxng-config:/etc/searxng searxng/searxng:latest
docker cp ~/searxng/settings.yml searxng:/etc/searxng/settings.yml
```

Wait a few seconds:

```bash
sleep 10
```

Verify SearXNG:

```bash
curl "http://localhost:8080/search?q=hello"
```

---

## **Step 10: Test LlamaCPP → SearXNG connectivity**

```bash
docker exec llamacpp-api bash -c "apt-get update && apt-get install -y curl && curl -s http://searxng:8080/search?q=test"
```

---

## **Step 11: End-to-end test from host**

1. Test SearXNG only:

```bash
curl "http://localhost:8080/search?q=latest+news&format=json" | jq
```

2. Test LlamaCPP only:

```bash
curl "http://localhost:8000/generate?prompt=Hello+world" | jq
```

3. Optional: run `test.py` from the repo to trigger integrated behavior.

---

✅ At this point, everything is running manually, exactly like your script would do automatically.

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

