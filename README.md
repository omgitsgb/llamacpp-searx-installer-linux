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

---

### Step 2: Python Environment & Dependencies

```bash
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install llamacpp uvicorn==0.44.0 requests fastapi
pip install -r llm.requirements.txt   # if available
```

---

### Step 3: Download LLaMA Model

```bash
cd models
curl -L -O https://huggingface.co/hugging-quants/Llama-3.2-1B-Instruct-Q8_0-GGUF/resolve/main/llama-3.2-1b-instruct-q8_0.gguf
```

---

### Step 4: Create `main.py`

Paste the **production-ready FastAPI code** (your existing code handles model loading, SearXNG search integration, and /generate endpoint).

---

### Step 5: Start LlamaCPP API

```bash
cd ../
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

## 2️⃣ Docker Setup (Optional)

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

### Step 3: Build & Run LlamaCPP Container

**CPU:**

```bash
docker build -f Dockerfile.cpu -t llamacpp-api .
docker rm -f llamacpp-api 2>/dev/null
docker run -d --restart unless-stopped --network llama-searx-net -p 8000:8000 --name llamacpp-api llamacpp-api
```

**GPU:**

```bash
docker build -f Dockerfile.gpu -t llamacpp-api .
docker rm -f llamacpp-api 2>/dev/null
docker run -d --gpus all --restart unless-stopped --network llama-searx-net -p 8000:8000 --name llamacpp-api llamacpp-api
```

---

### Step 4: Run SearXNG Container

```bash
docker volume create searxng-config
docker rm -f searxng 2>/dev/null
docker run -d --restart unless-stopped --network llama-searx-net --name searxng -p 8080:8080 -v searxng-config:/etc/searxng searxng/searxng:latest
docker cp ~/llamacpp-searx/searxng/settings.yml searxng:/etc/searxng/settings.yml
```

---

## 3️⃣ Test Script (`test.py`)

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

## 4️⃣ Health Checks

```bash
docker ps
docker network inspect llama-searx-net
docker exec llamacpp-api curl -s http://searxng:8080/search?q=test
curl http://localhost:8000/
curl http://localhost:8080/search?q=hello&format=json
```

---

