
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

## USING INSTALLER

## 1. Install
Clone the repo (first time only)
```bash
cd ~  # or wherever you want to keep it
git clone https://github.com/omgitsgb/llamacpp-searx-installer-linux.git
cd llamacpp-searx-installer-linux
```

## 2. Pull latest changes (future updates)
```bash
cd ~/llamacpp-searx-installer-linux
git pull
```

## 3.  Make the script executable

```bash
chmod +x llamacpp-searxng-installer-linux.sh
```

##  4.  Run the script
```bash
./llamacpp-searxng-installer-linux.sh
```

---

Install dependencies if needed:

```bash
sudo apt update
sudo apt install -y curl git lsb-release ca-certificates gnupg
```

---

## ⚡ Step 1: Install Docker

1. Remove old Docker remnants:

```bash
sudo apt remove -y docker.io docker-compose docker-compose-plugin containerd runc
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo apt-get autoremove -y
sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker /etc/apt/keyrings/docker* /etc/apt/sources.list.d/docker*
```

2. Add Docker GPG key & repository:

```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

UBUNTU_CODENAME=$(lsb_release -cs)
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list
```

3. Install Docker:

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

4. Verify Docker:

```bash
docker --version
sudo docker run hello-world
```

---

## ⚡ Step 2: Prepare Project Folder & Files

```bash
mkdir -p $HOME/llamacpp-searx-installer-linux/models
cd $HOME/llamacpp-searx-installer-linux
```

### 1️⃣ Create `requirements.txt`

```bash
nano requirements.txt
```

Paste:

```
fastapi
uvicorn[standard]
llama-cpp-python
requests
```

### 2️⃣ Create `main.py`

```bash
nano main.py
```

Paste the production-ready API code (included above). Save & exit.

### 3️⃣ Create Dockerfile

```bash
nano Dockerfile
```

Paste:

```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libssl-dev \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .
COPY models ./models

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

## ⚡ Step 3: Download Llama Model

```bash
cd $HOME/llamacpp-searx-installer-linux/models
curl -L -O https://huggingface.co/hugging-quants/Llama-3.2-1B-Instruct-Q8_0-GGUF/resolve/main/llama-3.2-1b-instruct-q8_0.gguf
```

---

## ⚡ Step 4: Build & Run LlamaCPP Container

```bash
cd $HOME/llamacpp-searx-installer-linux
docker build --no-cache -t llamacpp-api .
docker rm -f llamacpp-api 2>/dev/null
docker run -d --restart unless-stopped --network llama-searx-net -p 8000:8000 --name llamacpp-api llamacpp-api
```

---

## ⚡ Step 5: Prepare & Run SearXNG

1. **Create folder & `settings.yml`**

```bash
mkdir -p $HOME/searxng
nano $HOME/searxng/settings.yml
```

Paste:

```yaml
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
```

2. **Run SearXNG container**

```bash
docker volume create searxng-config
docker rm -f searxng 2>/dev/null

docker run -d --restart unless-stopped --network llama-searx-net --name searxng -p 8080:8080 -v searxng-config:/etc/searxng searxng/searxng:latest
docker cp $HOME/searxng/settings.yml searxng:/etc/searxng/settings.yml
```

3. **Verify**

```bash
curl "http://localhost:8080/search?q=hello&format=json"
```

---

## 🧪 Step 6: Health & Connectivity Tests

### 1️⃣ List running Docker containers

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
```

### 2️⃣ Test LlamaCPP API

```bash
curl -s --max-time 5 http://localhost:8000/health >/dev/null && echo "✅ LlamaCPP localhost OK" || echo "❌ LlamaCPP localhost FAIL"
```

### 3️⃣ Test SearXNG

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

## 🔧 Troubleshooting

```bash
docker logs llamacpp-api
docker logs searxng

docker restart llamacpp-api searxng
```


Got it — you want the **persistent, robust Docker volume version** to be the main, “regular” setup, and the bind-mount method to be the “alternative” version for quick testing. I’ve also added **rebuild lines** so users can refresh the images if needed. Here's the rewritten section:

---

## 🔄 Persistence & Reboot Safety

For LlamaCPP + SearXNG, we **recommend using Docker volumes** for persistent and robust setup.
Bind mounts can be used as a quick alternative but may break after a reboot.

---

### **Option A – Recommended: Docker Volume (persistent, robust)**

1. Stop old containers and remove old network/volume (if any):

```bash
docker stop llamacpp-api searxng 2>/dev/null
docker rm llamacpp-api searxng 2>/dev/null
docker network rm llama-searx-net 2>/dev/null
docker volume rm searxng-config 2>/dev/null
```

2. Recreate network and volume:

```bash
docker network create llama-searx-net
docker volume create searxng-config
```

3. Pull latest SearXNG image and rebuild LlamaCPP (in case of updates):

```bash
docker pull searxng/searxng:latest
cd $HOME/llamacpp-searx-installer-linux
docker build --pull -t llamacpp-api .
```

4. Run containers using Docker volume and automatic restart (`--restart unless-stopped`):

```bash
docker run -d --network llama-searx-net --name searxng -p 8080:8080 \
    -v searxng-config:/etc/searxng --restart unless-stopped searxng/searxng:latest

docker cp ~/searxng/settings.yml searxng:/etc/searxng

docker run -d --network llama-searx-net -p 8000:8000 --name llamacpp-api \
    --restart unless-stopped llamacpp-api
```

5. Test connectivity:

```bash
docker exec llamacpp-api curl -s http://searxng:8080/search?q=test
```

> ✅ Should return JSON results.
> This setup **persists across reboots** and automatically restarts containers.

---

### **Option B – Alternative: Bind Mount (quick test, not robust)**

Use this if you want to quickly test changes on the host without rebuilding the volume.

1. Stop and remove containers:

```bash
docker stop llamacpp-api searxng
docker rm llamacpp-api searxng
```

2. Verify host folder and settings file exist:

```bash
ls -la ~/searxng
cat ~/searxng/settings.yml
```

3. Run containers with bind mount (no automatic restart):

```bash
docker run -d --network llama-searx-net --name searxng -p 8080:8080 \
    -v "$HOME/searxng/settings.yml":/etc/searxng/settings.yml:ro searxng/searxng:latest

docker run -d --network llama-searx-net -p 8000:8000 --name llamacpp-api llamacpp-api
```

4. Test connectivity from LlamaCPP container:

```bash
docker exec llamacpp-api curl -s http://searxng:8080/search?q=test
```

> ✅ Works immediately, but may **break after a host reboot**.

---

### **Rebuild Notes**

If you update your `main.py` or want to refresh the images:

```bash
cd $HOME/llamacpp-searx-installer-linux
docker build --pull -t llamacpp-api .

# Optional: restart the container
docker stop llamacpp-api
docker rm llamacpp-api
docker run -d --network llama-searx-net -p 8000:8000 --name llamacpp-api --restart unless-stopped llamacpp-api
```

---

### **Sample Prompt Tests**

```bash
curl -s "http://localhost:8000/generate?prompt=What+is+the+latest+news+today?" | jq
curl -s "http://localhost:8000/generate?prompt=Summarize+the+top+headlines+in+technology." | jq
curl -s "http://localhost:8000/generate?prompt=Tell+me+a+fun+fact+about+space." | jq
```

> Returns JSON output from LlamaCPP, optionally using live SearXNG results.

---

