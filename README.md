Got it — we can clean this README up and structure it so it’s **much easier to follow**, while keeping all the essential info (manual setup, Docker, tests, persistence). Here’s a **refactored, streamlined version**:

---

# LlamaCPP + SearXNG Full Installer for Linux (Networked)

This repository provides a **full installer** for running **LlamaCPP** (LLaMA inference) with **SearXNG** (search engine) on Linux. The setup allows LlamaCPP to query SearXNG for real-time search results when generating responses.

---

## ✅ Features

* Automated setup with minimal interaction
* Optional Docker-based deployment (CPU/GPU)
* End-to-end health & connectivity tests
* Sample `test.py` script for verifying API
* Persistent containers with auto-restart on reboot

---

## 🖥️ Requirements

* Linux (tested on Ubuntu 22.04+)
* `curl`, `git` installed
* Internet connection for downloading models and Docker images

Check dependencies:

```bash
curl --version
git --version
lsb_release -a
```

---

## 📂 Folder Structure

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

## 1️⃣ Manual Setup

### Step 1: Create Project Folders

```bash
cd ~
mkdir -p llamacpp-searx/llamacpp/models
mkdir -p llamacpp-searx/searxng/searx
cd llamacpp-searx/llamacpp
```
## Create your main.py or download it.
```bash
nano main.py
```
### Step 2: Create main.py

Paste into main.py
```python
import os
import logging
import requests
from fastapi import FastAPI, HTTPException
from llama_cpp import Llama
import subprocess

MODEL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models")

gguf_models = [f for f in os.listdir(MODEL_DIR) if f.endswith(".gguf")]

if not gguf_models:
    raise FileNotFoundError(f"No .gguf model found in {MODEL_DIR}")

MODEL_PATH = os.path.join(MODEL_DIR, gguf_models[0])
CONTEXT_SIZE = 4096
MAX_TOKENS = 1000
SEARCH_TRIGGERS = ["news", "latest", "current", "update", "headlines"]
SEARX_URL = "http://localhost:8080/search"

app = FastAPI()
logging.basicConfig(level=logging.INFO)

llm = None  

def has_cuda():
    try:
        result = subprocess.run(["nvidia-smi"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return result.returncode == 0
    except FileNotFoundError:
        return False

@app.on_event("startup")
def load_model():
    global llm
    use_cuda = has_cuda()
    llm = Llama(model_path=MODEL_PATH, n_ctx=CONTEXT_SIZE, use_cuda=use_cuda)
    logging.info("✅ Model loaded successfully")
    logging.info(f"{'CUDA detected — using GPU' if use_cuda else 'CUDA not detected — using CPU'}")

def searx_search(user_search):
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36"
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

@app.get("/")
def read_root():
    return {"message": f"LlamaCPP API running with {gguf_models[0]}"}

@app.get("/generate")
def generate(prompt: str):
    global llm
    if llm is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet")

    logging.info(f"Prompt: {prompt}")

    try:
        search_triggered = any(word.lower() in prompt.lower() for word in SEARCH_TRIGGERS)
        search_results = searx_search(prompt) if search_triggered else []

        if search_results:
            numbered = "\n".join([
                f"{i+1}. Title: {r['title']}\n   Content: {r['content'][:300]}\n   URL: {r['url']}"
                for i, r in enumerate(search_results)
            ])

            full_prompt = f"Answer the question using ONLY these search results:\n{numbered}\nQuestion: {prompt}\nAnswer:"
        else:
            full_prompt = prompt

        output = llm(full_prompt, max_tokens=MAX_TOKENS)

        return {
            "prompt": prompt,
            "search_triggered": search_triggered,
            "search_results": search_results,
            "output": output['choices'][0]['text'].strip()
        }

    except Exception as e:
        logging.error(f"Error in /generate: {e}")
        raise HTTPException(status_code=500, detail=str(e))
```
---

### Step 3: Python Environment & Dependencies

```bash
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install llamacpp uvicorn==0.44.0 requests fastapi
pip install -r llm.requirements.txt   # if available
```

---

### Step 4: Download LLaMA Model

```bash
cd llamacpp-searx/llamacpp
mkdir models
cd models
curl -L -O https://huggingface.co/hugging-quants/Llama-3.2-1B-Instruct-Q8_0-GGUF/resolve/main/llama-3.2-1b-instruct-q8_0.gguf
```

---


---

### Step 5: Start LlamaCPP API

```bash
cd ~/llamacpp-searx
cd llamacpp
python3 -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

> Runs on `http://localhost:8000`

---

### Step 6: Setup SearXNG

```bash
cd ~/llamacpp-searx
git clone https://github.com/searxng/searxng.git
cd searxng
pip install --upgrade pip
pip install -r requirements.txt
pip install gunicorn==25.3.0
```

Start the server:

```bash
gunicorn -w 4 -b 0.0.0.0:8080 searx.webapp:app --log-level debug
```

> Runs on `http://localhost:8080`

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
Perfect — here’s a **clean, ready-to-paste Step 3** for your README. It clearly separates **Persistent** vs **Non-Persistent** and **CPU vs GPU**, with explanatory notes.

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

# Quick Start (Docker - Non-Persistent)

> ⚠️ This setup runs containers **without auto-restart**. If you reboot or stop Docker, the containers will stop.
```
docker network create llama-searx-net
docker run -d --network llama-searx-net -p 8080:8080 searxng/searxng:latest
docker run -d --network llama-searx-net -p 8000:8000 llamacpp-api
```

### Step 4: Run SearXNG Container

```bash
cd $HOME/llamacpp-searx/searxng
docker run -d --restart unless-stopped --network llama-searx-net --name searxng -p 8080:8080 -v /home/gb/llamacpp-searx/searxng/searx:/etc/searxng searxng/searxng:latest
```
---


### 5️⃣ Test sample prompts
```

```bash

# 2️⃣ Test LlamaCPP API (localhost)
curl -s --max-time 5 http://localhost:8000/health >/dev/null && echo "✅ LlamaCPP localhost OK" || echo "❌ LlamaCPP localhost FAIL"

# 3️⃣ Test SearXNG (localhost)
curl -s --max-time 5 "http://localhost:8080/search?q=test" >/dev/null && echo "✅ SearXNG localhost OK" || echo "❌ SearXNG localhost FAIL"

# 4️⃣ Test end-to-end prompt through LlamaCPP
curl -s "http://localhost:8000/generate?prompt=Summarize+the+top+headlines+in+technology." | jq >/dev/null && echo "✅ End-to-end LlamaCPP test OK" || echo "❌ End-to-end LlamaCPP test FAIL"

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
