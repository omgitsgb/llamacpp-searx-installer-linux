---

# LlamaCPP + SearXNG Full Installer for Linux (Manual / Docker Optional)

This guide covers both **manual setup** and optional **Docker deployment** for running **LlamaCPP** with **SearXNG**.

---

## ✅ Features

* End-to-end LlamaCPP + SearXNG integration
* Real-time search-enabled responses
* Optional Docker-based deployment (CPU/GPU)
* Persistent containers with auto-restart or non-persistent mode
* Sample `test.py` for verifying API

---

## 🖥️ Requirements

* Linux (Ubuntu 22.04+ recommended)
* `python3`, `pip3`, `curl`, `git`
* Internet connection for models and packages

Check:

```bash
python3 --version
pip3 --version
curl --version
git --version
lsb_release -a
```

---

## 📂 Recommended Folder Structure

```text
$HOME/llamacpp-searx/
├─ llamacpp/
│  ├─ models/
│  │  └─ llama-3.2-1b-instruct-q8_0.gguf
│  ├─ venv/
│  ├─ main.py
│  └─ requirements.txt
├─ searxng/
│  └─ searx/
│     └─ settings.yml
```

---

## 1️⃣ LlamaCPP Manual Setup

### Step 1: Create Project Folders

```bash
cd ~
mkdir -p llamacpp-searx/llamacpp
mkdir -p llamacpp-searx/llamacpp/models
cd llamacpp-searx/llamacpp
```

---

### Step 2: Create `main.py`
```
nano main.py
```

Paste main.py
```python
import os
import logging
import requests
import subprocess
from fastapi.responses import StreamingResponse

from fastapi import FastAPI, HTTPException
from llama_cpp import Llama

# ==================================================
# MODEL SETUP
# ==================================================

MODEL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models")

gguf_models = [f for f in os.listdir(MODEL_DIR) if f.endswith(".gguf")]

if not gguf_models:
    raise FileNotFoundError(f"No .gguf model found in {MODEL_DIR}")

MODEL_PATH = os.path.join(MODEL_DIR, gguf_models[0])

CONTEXT_SIZE = 4096
MAX_TOKENS = 1000

SEARCH_TRIGGERS = ["news", "latest", "current", "update", "headlines"]

SEARX_URL = "http://localhost:8080/search"

# ==================================================
# APP INIT
# ==================================================

app = FastAPI()
logging.basicConfig(level=logging.INFO)

llm = None


# ==================================================
# CUDA DETECTION
# ==================================================

def has_cuda():
    try:
        result = subprocess.run(
            ["nvidia-smi"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        return result.returncode == 0
    except FileNotFoundError:
        return False


# ==================================================
# LOAD MODEL
# ==================================================

@app.on_event("startup")
def load_model():
    global llm

    use_cuda = has_cuda()

    llm = Llama(
        model_path=MODEL_PATH,
        n_ctx=CONTEXT_SIZE,
        n_gpu_layers=50 if use_cuda else 0  # IMPORTANT CUDA SWITCH
    )

    logging.info("✅ Model loaded successfully")
    logging.info("🚀 CUDA ENABLED" if use_cuda else "🧠 CPU MODE")


# ==================================================
# SEARX FUNCTION
# ==================================================

def searx_search(user_search):
    try:
        headers = {
            "User-Agent": "Mozilla/5.0"
        }

        resp = requests.get(
            SEARX_URL,
            params={"q": user_search, "format": "json"},
            headers=headers,
            timeout=10
        )

        resp.raise_for_status()

        results = []

        for r in resp.json().get("results", []):
            results.append({
                "title": r.get("title", "").strip(),
                "content": (r.get("content") or r.get("description") or "").strip(),
                "url": r.get("url", "").strip()
            })

        return results[:5]

    except Exception as e:
        logging.error(f"SearXNG error: {e}")
        return []


# ==================================================
# ROUTES
# ==================================================

@app.get("/")
def root():
    return {"message": f"LlamaCPP API running with {gguf_models[0]}"}


@app.get("/generate")
def generate(prompt: str):
    global llm

    if llm is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet")

    logging.info(f"Prompt: {prompt}")

    try:
        # --------------------------
        # SEARCH STEP (BEFORE STREAM)
        # --------------------------
        search_triggered = any(
            word.lower() in prompt.lower()
            for word in SEARCH_TRIGGERS
        )

        search_results = searx_search(prompt) if search_triggered else []

        if search_results:
            numbered = "\n".join([
                f"{i+1}. Title: {r['title']}\n   Content: {r['content'][:300]}\n   URL: {r['url']}"
                for i, r in enumerate(search_results)
            ])

            full_prompt = (
                f"Answer using ONLY these search results:\n"
                f"{numbered}\n\n"
                f"Question: {prompt}\n"
                f"Answer:"
            )
        else:
            full_prompt = prompt

        # --------------------------
        # STREAMING (FIXED)
        # --------------------------
        stream = llm(
            full_prompt,
            max_tokens=MAX_TOKENS,
            stream=True
        )

        response = []

        print("Assistant: ", end="", flush=True)

        for chunk in stream:

            # SAFE COMPATIBLE EXTRACTION
            token = ""

            try:
                if isinstance(chunk, dict):
                    token = chunk["choices"][0].get("text", "")
                else:
                    token = chunk.choices[0].text
            except Exception as e:
                logging.error(f"Stream parse error: {e}")
                continue

            print(token, end="", flush=True)
            response.append(token)

        print()

        final_text = "".join(response)

        # --------------------------
        # RETURN
        # --------------------------
        return {
            "prompt": prompt,
            "search_triggered": search_triggered,
            "search_results": search_results,
            "output": final_text
        }

    except Exception as e:
        logging.error(f"Error in /generate: {e}")
        raise HTTPException(status_code=500, detail=str(e))
        
@app.get("/generate_stream")
def generate_stream(prompt: str):
    global llm

    if llm is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet")

    def stream_tokens():

        # --------------------------
        # SAME SEARCH LOGIC AS /generate
        # --------------------------
        search_triggered = any(
            word.lower() in prompt.lower()
            for word in SEARCH_TRIGGERS
        )

        search_results = searx_search(prompt) if search_triggered else []

        if search_results:
            numbered = "\n".join([
                f"{i+1}. Title: {r['title']}\n"
                f"   Content: {r['content'][:300]}\n"
                f"   URL: {r['url']}"
                for i, r in enumerate(search_results)
            ])

            full_prompt = (
                "Use ONLY the search results below:\n\n"
                f"{numbered}\n\n"
                f"User question: {prompt}\n"
                "Answer:"
            )
        else:
            full_prompt = prompt

        # --------------------------
        # STREAM MODEL OUTPUT
        # --------------------------
        stream = llm(
            full_prompt,
            max_tokens=MAX_TOKENS,
            stream=True
        )

        for chunk in stream:
            try:
                if isinstance(chunk, dict):
                    token = chunk["choices"][0].get("text", "")
                else:
                    token = chunk.choices[0].text

                yield token

            except Exception as e:
                yield f"\n[error: {e}]"

    return StreamingResponse(stream_tokens(), media_type="text/plain")
```
> ⚠️ **Note:** If using Docker later, update the SearXNG URL:

```python
# COMMENT OUT localhost
# SEARX_URL = "http://localhost:8080/search"

# DOCKER NETWORK
SEARX_URL = "http://searxng:8080/search"
```
### Make requirements.txt
```
nano requirements.txt
```
### Paste
```
annotated-doc==0.0.4
annotated-types==0.7.0
anyio==4.13.0
certifi==2026.2.25
charset-normalizer==3.4.7
click==8.3.2
diskcache==5.6.3
fastapi==0.135.3
h11==0.16.0
httptools==0.7.1
idna==3.11
Jinja2==3.1.6
llama_cpp_python==0.3.20
MarkupSafe==3.0.3
numpy==2.4.4
pydantic==2.12.5
pydantic_core==2.41.5
python-dotenv==1.2.2
PyYAML==6.0.3
requests==2.33.1
starlette==1.0.0
typing-inspection==0.4.2
typing_extensions==4.15.0
urllib3==2.6.3
uvicorn==0.44.0
uvloop==0.22.1
watchfiles==1.1.1
websockets==16.0
```
---

### Step 3: Python Environment & Dependencies

```bash
python3 -m venv venv
source venv/bin/activate

pip install --upgrade pip

pip install uvicorn==0.44.0 requests fastapi

```
### OPTIONAL (Cuda GPU Acceleration)
```bash
# CUDA-enabled llama.cpp
CMAKE_ARGS="-DGGML_CUDA=on" FORCE_CMAKE=1 pip install --no-cache-dir llama-cpp-python
```
### Install Requirements
```
#
pip install -r requirements.txt

```

---

### Step 4: Download LLaMA Model

```bash
cd ~/llamacpp-searx/llamacpp/models
curl -L -O https://huggingface.co/hugging-quants/Llama-3.2-1B-Instruct-Q8_0-GGUF/resolve/main/llama-3.2-1b-instruct-q8_0.gguf
```

---

### Step 5: Run LlamaCPP API

```bash
cd ~/llamacpp-searx/llamacpp
python3 -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

> Available at `http://localhost:8000`

---

## 2️⃣ SearXNG Manual Setup

### Step 1: Clone & Install

```bash
cd ~/llamacpp-searx
git clone https://github.com/searxng/searxng.git
cd searxng
python3.11 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install gunicorn==25.3.0
```

---

### Edit Settings

```bash
cd ~/llamacpp-searx/searxng/searx
nano settings.yml
```
paste:
```
debug: true
instance_name: "SearXNG"

search:
  safe_search: 0
  autocomplete: ""
  autocomplete_min: 4
  default_lang: "auto"

  ban_time_on_fail: 5
  max_ban_time_on_fail: 120

  suspended_times:
    SearxEngineAccessDenied: 180
    SearxEngineCaptcha: 3600
    SearxEngineTooManyRequests: 180
    cf_SearxEngineCaptcha: 1296000
    cf_SearxEngineAccessDenied: 86400
    recaptcha_SearxEngineCaptcha: 604800

  formats:
    - html
    - json


server:
  bind_address: "0.0.0.0"
  port: 8080
  secret_key: "masfasgfweagewsgewsgewsgewsgewsgwesg"
  public_instance: false


botdetection:
  enabled: false
  whitelist:
    - 127.0.0.1
    - ::1


limiter:
  enabled: false


ui:
  default_theme: simple
  query_in_title: false


outgoing:
  request_timeout: 4.0
  pool_connections: 100
  pool_maxsize: 20
  enable_http2: true


# ==================================================
# PLUGINS (keep useful ones only)
# ==================================================
plugins:
  searx.plugins.self_info.SXNGPlugin:
    active: true

  searx.plugins.calculator.SXNGPlugin:
    active: true

  searx.plugins.unit_converter.SXNGPlugin:
    active: true

  searx.plugins.hash_plugin.SXNGPlugin:
    active: true

  searx.plugins.time_zone.SXNGPlugin:
    active: true

  searx.plugins.hostnames.SXNGPlugin:
    active: true

  searx.plugins.tracker_url_remover.SXNGPlugin:
    active: true


# ==================================================
# CATEGORIES
# ==================================================
categories_as_tabs:
  general:
  news:
  images:
  videos:
  science:
  it:
  music:
  files:
  map:
  social media:


# ==================================================
# ENGINES (CLEAN + STABLE STACK)
# ==================================================
engines:

  # --------------------------
  # CORE WEB SEARCH
  # --------------------------
  - name: google
    engine: google
    shortcut: go

  - name: bing
    engine: bing
    shortcut: bi


  # --------------------------
  # NEWS (STABLE ONLY)
  # --------------------------
  - name: bing news
    engine: bing_news
    shortcut: bin
    categories: [news]

  # (optional fallback news aggregation)
  - name: duckduckgo news
    engine: duckduckgo_extra
    shortcut: ddn
    categories: [news]
    ddg_category: news


  # --------------------------
  # KNOWLEDGE BASE
  # --------------------------
  - name: wikipedia
    engine: wikipedia
    shortcut: wp
    categories: [general]


  # --------------------------
  # VIDEO
  # --------------------------
  - name: youtube
    engine: youtube_noapi
    shortcut: yt

```
### Step 2: Start SearXNG Server

```bash
cd ~/llamacpp-searx/searxng
gunicorn -w 4 -b 0.0.0.0:8080 searx.webapp:app --log-level debug
```

> Available at `http://localhost:8080`

> ⚠️ **Tip:** If running LlamaCPP in Docker, change `SEARX_URL` in `main.py` to `http://searxng:8080/search`.

---

## 3️⃣ Quick Health Check

* Test LlamaCPP API:

```bash
curl "http://localhost:8000/generate?prompt=Hello"
```

* Test SearXNG:

```bash
curl "http://localhost:8080/search?q=test&format=json"
```

---

## 4️⃣ Optional: Docker Deployment (CPU/GPU)

> See **Step 3 from Docker setup section** above for persistent/non-persistent containers for LlamaCPP and SearXNG.

---

### Docker Setup (Optional)
---

PLEASE BE SURE TO CHANGE THIS LINE IN THE main.py as we can not use the localhost for when we dock our container.
### Lines are located in the main.py under config

```
# COMMENT OUT or delete
# SEARX_URL = "http://localhost:8080/search"

# DOCKER (USE THIS HTTP)
SEARX_URL = "http://searxng:8080/search"
```

# ---------------------------
## Step 0: Install Docker
```bash
sudo apt update && \
sudo apt install -y ca-certificates curl gnupg && \
sudo install -m 0755 -d /etc/apt/keyrings && \
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
sudo chmod a+r /etc/apt/keyrings/docker.gpg && \
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
sudo apt update && \
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && \
sudo usermod -aG docker $USER && \
newgrp docker && \
docker run hello-world
```

### Step 1: Create Docker Network

```bash
docker network inspect llama-searx-net 2>/dev/null || docker network create llama-searx-net
```

---


### Step 2: Dockerfile
Make one of the follow files
```
cd ~
cd llamacpp-searx/llamacpp
nano Dockerfile.cpu
or
nano dockerfile.gpu
```
**CPU Version: `Dockerfile.cpu`**

```dockerfile
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y build-essential cmake git libssl-dev libffi-dev && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
COPY models ./models
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**GPU Version: `Dockerfile.gpu`** (requires NVIDIA GPU)

```dockerfile
# Use Python slim as base for a smaller image
FROM python:3.12-slim

# ---------------------------
# Environment variables
# ---------------------------
ENV PYTHONUNBUFFERED=1
ENV LANG=C.UTF-8

# ---------------------------
# System dependencies for building llama_cpp_python and general usage
# ---------------------------
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    cmake \
    libomp-dev \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------
# Set working directory
# ---------------------------
WORKDIR /app

# ---------------------------
# Copy and install Python dependencies
# ---------------------------
COPY requirements.txt .
RUN pip install --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt

# ---------------------------
# Copy project files
# ---------------------------
COPY . .

# ---------------------------
# Expose FastAPI port
# ---------------------------
EXPOSE 8000

# ---------------------------
# Default command to run FastAPI with Uvicorn
# ---------------------------
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
```


---

### Step 3: Build & Run LlamaCPP Container

> ⚠️ **Persistent vs Non-Persistent:**
>
> * **Persistent:** Container auto-restarts on host reboot (`--restart unless-stopped`).
> * **Non-Persistent:** Container stops when Docker exits or the system reboots (no `--restart` flag).

---

#### **Persistent (auto-restart on reboot)**

**CPU:**

```bash
cd $HOME/llamacpp-searx/llamacpp
docker build -f Dockerfile.cpu --no-cache -t llamacpp-api .
docker run -d --restart unless-stopped --network llama-searx-net -p 8000:8000 --name llamacpp-api llamacpp-api
```

**GPU:**

```bash
cd $HOME/llamacpp-searx/llamacpp
docker build -f Dockerfile.gpu --no-cache -t llamacpp-api .
docker run -d --restart unless-stopped --network llama-searx-net -p 8000:8000 --name llamacpp-api llamacpp-api
```

---

#### **Non-Persistent (stops on exit/reboot)**

**CPU:**

```bash
cd $HOME/llamacpp-searx/llamacpp
docker build -f Dockerfile.cpu --no-cache -t llamacpp-api .
docker run -d --network llama-searx-net -p 8000:8000 --name llamacpp-api llamacpp-api
```

**GPU:**

```bash
cd $HOME/llamacpp-searx/llamacpp
docker build -f Dockerfile.gpu --no-cache -t llamacpp-api .
docker run -d --network llama-searx-net -p 8000:8000 --name llamacpp-api llamacpp-api
```
---
### Step 4: Run SearXNG Container

```bash
cd $HOME/llamacpp-searx/searxng
docker run -d --restart unless-stopped --network llama-searx-net --name searxng -p 8080:8080 -v /home/gb/llamacpp-searx/searxng/searx:/etc/searxng searxng/searxng:latest
```
---




# Quick Start (Docker - Non-Persistent)

> ⚠️ This setup runs containers **without auto-restart**. If you reboot or stop Docker, the containers will stop.
```
docker network create llama-searx-net
docker run -d --network llama-searx-net -p 8080:8080 searxng/searxng:latest
docker run -d --network llama-searx-net -p 8000:8000 llamacpp-api
```




### 5️⃣ Test sample prompts
```

```bash

# 2️⃣ Test LlamaCPP API (localhost)
curl -s --max-time 5 http://localhost:8000/health >/dev/null && echo "✅ LlamaCPP localhost OK" || echo "❌ LlamaCPP localhost FAIL"

# 3️⃣ Test SearXNG (localhost)
curl -s --max-time 5 "http://localhost:8080/search?q=test" >/dev/null && echo "✅ SearXNG localhost OK" || echo "❌ SearXNG localhost FAIL"

# 4️⃣ Test end-to-end prompt through LlamaCPP
curl -s "http://localhost:8000/generate?prompt=Summarize+the+top+headlines+in+technology." | jq

# Stream Tokens Test
curl -N "http://localhost:8000/generate_stream?prompt=latest%20news"
curl -N "http://localhost:8000/generate_stream?prompt=what's%20the%20latest%20news"
```

### 3️⃣ Test Script (`test.py`)

```python
import requests

LLAMA_API_URL = "http://localhost:8000/generate"
test_prompts = [
    "What is the latest news today?",
    "Summarize top headlines in technology.",
    "Tell me a fun fact about space."
]

for prompt in test_prompts:
    try:
        resp = requests.get(LLAMA_API_URL, params={"prompt": prompt}, timeout=40)
        resp.raise_for_status()
        data = resp.json()
        print(f"\nPrompt: {prompt}")
        print("Search Triggered:", data.get("search_triggered"))
        print("Search Results:", [r['title'] for r in data.get("search_results", [])])
        print("Generated Output:", data.get("output"))
    except Exception as e:
        print(f"Error: {e}")
```

Run:

```bash
python3 test.py
```

---

### Rebuild (if you change any of the code)

Remove LlamaCPP CPU
```
# Stop and remove old container
docker rm -f llamacpp-cpu 2>/dev/null || true
```
## Rebuild Llama (CPU Mode)
```
cd $HOME/llamacpp-searx/llamacpp
docker build -f Dockerfile.cpu --no-cache -t llamacpp-cpu .
```
## Run container again
```
docker run -d --restart unless-stopped --network llama-searx-net -p 8000:8000 --name llamacpp-cpu llamacpp-cpu
```

Remove LlamaCPP GPU
```
# Stop and remove old container
docker rm -f llamacpp-gpu 2>/dev/null || true
```
## Rebuild Llama (GPU Mode)
```
cd $HOME/llamacpp-searx/llamacpp
docker build -f Dockerfile.gpu --no-cache -t llamacpp-gpu 
```
# Run container again
```
docker run -d --restart unless-stopped --network llama-searx-net -p 8000:8000 --name llamacpp-gpu llamacpp-gpu
```
# Remove Network Containers, Rebuild Network
```
# Stop & remove containers
docker rm -f llamacpp-api searxng 2>/dev/null || true

# Remove old network
docker network rm llama-searx-net 2>/dev/null || true

# Recreate network
docker network create llama-searx-net
```

## Unmount/Remove Docker Containers & Network
```base
# Stop and remove LlamaCPP containers (CPU or GPU) and SearXNG
docker rm -f llamacpp-api searxng 2>/dev/null || true

# Remove Docker images (optional)
docker rmi -f llamacpp-api searxng/searxng:latest 2>/dev/null || true

# Remove Docker network
docker network rm llama-searx-net 2>/dev/null || true

# All-in-one command
docker rm -f llamacpp-api searxng 2>/dev/null || true && \
docker rmi -f llamacpp-api searxng/searxng:latest 2>/dev/null || true && \
docker network rm llama-searx-net 2>/dev/null || true

echo "✅ All LlamaCPP (CPU/GPU), SearXNG containers, images, and network removed."
```
---

## 4️⃣ Health Checks

```bash
docker ps
docker network inspect llama-searx-net
docker exec llamacpp-api curl -s http://searxng:8080/search?q=test
curl http://localhost:8000/
curl http://localhost:8080/search?q=hello&format=json
```

$
