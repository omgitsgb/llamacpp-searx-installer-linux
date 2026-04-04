
# LlamaCPP + SearXNG Networked Installer

This repository provides a **full automated setup** for running **LlamaCPP** with **SearXNG** in Docker on Linux.  
The setup allows LlamaCPP to dynamically query SearXNG for real-time search results when generating responses.

---

## Features

- Fully automated Linux installer script (`installer.sh`).
- Automatically installs Git and Docker if missing.
- Creates a dedicated Docker network for LlamaCPP and SearXNG.
- Downloads LLaMA 3.2 1B GGUF model if not already present.
- Builds and runs LlamaCPP API container.
- Sets up SearXNG container with JSON and HTML search support.
- End-to-end API test suite included.

---

## Requirements

- Linux (tested on Ubuntu)
- `curl`, `git`, `docker` (installed automatically if missing)
- Internet connection for downloading model and Docker images

---

## Installation

Clone the repository:

```bash
git clone https://github.com/omgitsgb/llamacpp-searx-installer-linux.git
cd llamacpp-searx-installer-linux
```

Run the installer:

```bash
chmod +x installer.sh
./installer.sh
```

The script will:

1. Install Git and Docker if missing.
2. Remove old Docker/Podman remnants.
3. Create a Docker network (`llama-searx-net`).
4. Clone/update LlamaCPP repository and download the model.
5. Build and run LlamaCPP container on port `8000`.
6. Create SearXNG configuration and run container on port `8080`.
7. Run end-to-end API tests.

---

## Usage

### LlamaCPP API

The LlamaCPP FastAPI server runs on port `8000`.

Example request:

```bash
curl -s -G "http://localhost:8000/generate" --data-urlencode "prompt=What is the latest news today?" | jq
```

- Automatically triggers SearXNG search if prompt contains keywords like:  
  `news`, `latest`, `update`, `headlines`.
- Returns JSON object with:  
  - `prompt`
  - `search_triggered` (bool)
  - `search_results` (array)
  - `output` (generated text)

### SearXNG

- Runs on port `8080`.
- Accessible inside Docker network at `http://searxng:8080`.
- Supports JSON and HTML results.
- Example query:

```bash
curl -s "http://localhost:8080/search?q=latest+news&format=json" | jq
```

---

## File Structure

```bash
llamacpp-searx-installer-linux/
├─ installer.sh          # Main installer script
├─ models/               # LLaMA GGUF models
├─ llama_api.py          # FastAPI LlamaCPP server
├─ README.md             # This file
```

---

## Docker Network

Both containers share a dedicated Docker network:

- Network name: `llama-searx-net`
- Allows LlamaCPP to reach SearXNG via container name `searxng:8080`.

---

## End-to-End API Tests

`installer.sh` includes three test cases:

1. **SearXNG search only**

```bash
curl -s "http://localhost:8080/search?q=latest+news&format=json" | jq
```

2. **LLaMA without search trigger**

```bash
curl -s "http://localhost:8000/generate?prompt=Hello+world" | jq
```

3. **LLaMA with search trigger**

```bash
curl -s "http://localhost:8000/generate?prompt=What+is+the+latest+news+today?" | jq
```

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

