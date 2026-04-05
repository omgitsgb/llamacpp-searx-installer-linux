
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

# Check dependencies:

```bash
curl --version      # Should print curl version if installed
git --version       # Should print git version if installed
lsb_release -a      # Should print Ubuntu version info if installed
```
## Install dependencies if needed:
```bash
sudo apt update
sudo apt install -y curl git lsb-release ca-certificates gnupg
```
---
# USING INSTALLER

## 1. Install
Clone the repo (first time only)
```bash
cd ~  # or wherever you want to keep it
curl -O https://raw.githubusercontent.com/omgitsgb/llamacpp-searx-installer-linux/main/llamacpp-searxng-installer-linux.sh

```

## 2.  Make the script executable

```bash
chmod +x llamacpp-searxng-installer-linux.sh
```

##  3.  Run the script
```bash
./llamacpp-searxng-installer-linux.sh
```

---


---

# MANUAL SETUP

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

## ⚡ Step 2: Prepare Project Folders & Files

```bash
mkdir -p $HOME/llamacpp-searx/llamacpp/models
mkdir -p $HOME/llamacpp-searx/searxng
cd $HOME/llamacpp-searx/llamacpp
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
Paste the production-ready API code below. Save & exit.
```bash
# ---------------------------
# IMPORTS
# ---------------------------
import os                      # Provides functions to interact with the operating system (paths, files, etc.)
import logging                 # Built-in Python module for logging info, warnings, and errors
import requests                # Third-party library to make HTTP requests (used to query SearXNG)
from fastapi import FastAPI, HTTPException  
                                # FastAPI framework for building APIs
                                # HTTPException allows sending errors with custom HTTP status codes
from llama_cpp import Llama     # LlamaCPP Python binding to load and run .gguf LLaMA models

# ---------------------------
# CONFIGURATION
# ---------------------------

# Get absolute path to the "models" folder relative to this script
MODEL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models")

# List all files in the models folder that end with ".gguf" (LLaMA GGUF model format)
gguf_models = [f for f in os.listdir(MODEL_DIR) if f.endswith(".gguf")]

# If no GGUF model is found, raise an error and stop execution
if not gguf_models:
    raise FileNotFoundError(f"No .gguf model found in {MODEL_DIR}")

# Use the first GGUF model found in the folder
MODEL_PATH = os.path.join(MODEL_DIR, gguf_models[0])

# Set the context size: how many tokens the model can "remember" at once
CONTEXT_SIZE = 4096

# Maximum number of tokens to generate per request
MAX_TOKENS = 512

# Words that, if found in a prompt, will trigger a SearXNG search
SEARCH_TRIGGERS = ["news", "latest", "current", "update", "headlines"]

# URL of the SearXNG instance (accessible inside Docker network as "searxng")
SEARX_URL = "http://searxng:8080/search"

# ---------------------------
# FASTAPI APP & LOGGING
# ---------------------------

# Initialize a FastAPI application
app = FastAPI()

# Configure logging globally (INFO level shows basic info and errors)
logging.basicConfig(level=logging.INFO)

# Placeholder variable for the Llama model; will be loaded at startup
llm = None  

# ---------------------------
# STARTUP EVENT: LOAD LLAMA MODEL
# ---------------------------

@app.on_event("startup")
def load_model():
    """
    This function runs once when the FastAPI app starts.
    It loads the LLaMA model into memory, making it ready for generating responses.
    """
    global llm  # Declare that we are modifying the global llm variable
    logging.info(f"Loading model from {MODEL_PATH} ...")  # Log that model loading has started

    # Load LLaMA model using llama_cpp
    llm = Llama(model_path=MODEL_PATH, n_ctx=CONTEXT_SIZE)

    # Confirm successful model load
    logging.info("✅ Model loaded successfully")

# ---------------------------
# SEARCH HELPER FUNCTION
# ---------------------------

def searx_search(query):
    """
    Query the SearXNG search engine and return top results.
    
    Parameters:
        query (str): The text query to search.
    
    Returns:
        list of dict: Each dict contains 'title', 'content', 'url' of a result.
    """
    try:
        # Make an HTTP GET request to the SearXNG API
        resp = requests.get(SEARX_URL, params={"q": query, "format": "json"}, timeout=10)

        # Raise an exception if HTTP status is an error (4xx or 5xx)
        resp.raise_for_status()

        results = []  # List to store top results
        # Extract relevant fields from each search result returned by SearXNG
        for r in resp.json().get("results", []):
            results.append({
                "title": r.get("title", "").strip(),  # Remove whitespace
                "content": (r.get("content") or r.get("description") or "").strip(),
                "url": r.get("url", "").strip()
            })

        # Return only the top 5 results to keep prompt concise
        return results[:5]

    except Exception as e:
        # Log any error that occurs while querying SearXNG
        logging.error(f"SearXNG error: {e}")
        return []  # Return empty list if search fails

# ---------------------------
# ROOT ROUTE
# ---------------------------

@app.get("/")
def read_root():
    """
    Root endpoint for health check.
    Returns a JSON object with the loaded model name.
    """
    return {"message": f"LlamaCPP API running with {gguf_models[0]}"}

# ---------------------------
# GENERATE ROUTE
# ---------------------------

@app.get("/generate")
def generate(prompt: str):
    """
    Main endpoint to generate text using the LLaMA model.
    
    Parameters:
        prompt (str): User-provided text prompt.
    
    Returns:
        dict: JSON containing original prompt, whether a search was triggered, 
              any search results, and generated model output.
    """
    global llm  # Reference the global model variable

    # If the model hasn't loaded yet, return a 503 Service Unavailable
    if llm is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet")

    logging.info(f"Prompt: {prompt}")  # Log the incoming prompt

    try:
        # Check if any search trigger words appear in the prompt
        search_triggered = any(word.lower() in prompt.lower() for word in SEARCH_TRIGGERS)

        # Perform search if triggered
        search_results = searx_search(prompt) if search_triggered else []

        # Format prompt for the model
        if search_results:
            # Number results and format content for readability
            numbered = "\n".join([
                f"{i+1}. Title: {r['title']}\n   Content: {r['content'][:300]}\n   URL: {r['url']}"
                for i, r in enumerate(search_results)
            ])
            # Include search results in the prompt
            full_prompt = f"Answer the question using ONLY these search results:\n{numbered}\nQuestion: {prompt}\nAnswer:"
        else:
            # No search results, use original prompt
            full_prompt = prompt

        # Generate text with LLaMA
        output = llm(full_prompt, max_tokens=MAX_TOKENS)

        # Return JSON response including all useful info
        return {
            "prompt": prompt,
            "search_triggered": search_triggered,
            "search_results": search_results,
            "output": output['choices'][0]['text'].strip()
        }

    except Exception as e:
        # Log and return any error that occurs during generation
        logging.error(f"Error in /generate: {e}")
        raise HTTPException(status_code=500, detail=str(e))
```
Got it — here’s your section rewritten so everything reflects your **new folder structure under `$HOME/llamacpp-searx`** instead of the old paths:

---

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
cd $HOME/llamacpp-searx/llamacpp/models
curl -L -O https://huggingface.co/hugging-quants/Llama-3.2-1B-Instruct-Q8_0-GGUF/resolve/main/llama-3.2-1b-instruct-q8_0.gguf
```

## ⚡ Step 4: Build & Run LlamaCPP Container

```bash
docker network create llama-searx-net
docker volume create searxng-config
```

---

## ⚡ Step 5: Build & Run LlamaCPP Container

```bash
cd $HOME/llamacpp-searx/llamacpp
docker build --no-cache -t llamacpp-api .
docker rm -f llamacpp-api 2>/dev/null
docker run -d --restart unless-stopped --network llama-searx-net -p 8000:8000 --name llamacpp-api llamacpp-api
```

---

## ⚡ Step 6: Prepare & Run SearXNG

1. **Create folder & `settings.yml`**

```bash
mkdir -p $HOME/llamacpp-searx/searxng
nano $HOME/llamacpp-searx/searxng/settings.yml
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
docker cp $HOME/llamacpp-searx/searxng/settings.yml searxng:/etc/searxng/settings.yml
```

3. **Verify**

```bash
curl "http://localhost:8080/search?q=hello&format=json"
```

---

✅ Now **all paths** are correctly using `$HOME/llamacpp-searx/llamacpp` and `$HOME/llamacpp-searx/searxng`.


## 🧪 Step 7: Health & Connectivity Tests

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


Perfect — we can make a dedicated section for `test.py` in your manual or README, fully commented and beginner-friendly, showing how it simplifies testing the LlamaCPP API. Here’s a fully explained version:

---

## 🧪 Test Script: `test.py`

This small Python script lets you **quickly test your LlamaCPP API** without manually using `curl` or hitting the endpoints one by one.

You just run it after your containers are up, and it will:

* Send prompts to the API
* Automatically check if a search was triggered
* Print the returned search results and generated output

---

### **Contents of `test.py`**

```python
import requests  # For sending HTTP requests to the API
import json      # For formatting and handling JSON responses

# ---------------------------
# Configuration
# ---------------------------
LLAMA_API_URL = "http://localhost:8000/generate"  # Update if running on a different host/port

# Example prompts to test
test_prompts = [
    "What is the latest news today?",
    "Summarize the top headlines in technology.",
    "Tell me a fun fact about space."
]

# ---------------------------
# Run Tests
# ---------------------------
for prompt in test_prompts:
    try:
        # Send a GET request with URL-encoded prompt
        response = requests.get(LLAMA_API_URL, params={"prompt": prompt}, timeout=40)
        
        # Raise an error if the HTTP request fails (non-2xx response)
        response.raise_for_status()
        
        # Convert JSON response into a Python dictionary
        data = response.json()

        # ---------------------------
        # Display results nicely
        # ---------------------------
        print("\n" + "="*40)
        print(f"Prompt: {prompt}")  # Show the original prompt
        print("Search Triggered:", data.get("search_triggered"))  # Did the script trigger a SearXNG search?
        print("Search Results:", [r['title'] for r in data.get("search_results", [])])  # Titles only
        print("Generated Output:\n", data.get("output"))  # LlamaCPP output
        print("="*40 + "\n")

    except Exception as e:
        # Print any errors clearly
        print(f"Error with prompt '{prompt}': {e}")
```

---

### **How it works**

1. **Send prompts to your API** – The script loops over `test_prompts` and sends each one to `http://localhost:8000/generate`.
2. **Check for SearXNG integration** – If the prompt triggers a search (`news`, `latest`, etc.), it prints whether search results were used.
3. **See the output** – Prints LlamaCPP’s generated text, so you can quickly verify the AI is working.
4. **Handle errors automatically** – Any network or API errors are caught and displayed clearly.

---

### **Run the test**

```bash
python3 test.py
```

* Works **immediately** after your containers are up.
* No manual `curl` calls needed.
* Great for validating LlamaCPP + SearXNG integration in one place. ✅

---



---

## 🛠️ Troubleshooting & Connectivity Checks

### **1️⃣ List all running Docker containers**

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
```

*Shows which containers are running, their image, status, and exposed ports.*

✅ Confirms your LlamaCPP and SearXNG containers are up.

---

### **2️⃣ Check Docker network**

```bash
docker network inspect llama-searx-net
```

*Shows all containers attached to the `llama-searx-net` network and their IPs.*

✅ Confirms that LlamaCPP can “see” SearXNG inside the Docker network.

---

### **3️⃣ Test if LlamaCPP container can reach SearXNG**

```bash
docker exec llamacpp-api curl -s http://searxng:8080/search?q=test
```

*This runs `curl` inside the LlamaCPP container to query SearXNG by container name.*

* If you see JSON results → ✅ Connectivity OK
* If you see an error → ❌ Containers cannot communicate (check network)

---

### **4️⃣ Check ports on the host machine**

```bash
ss -tulnp | grep -E '8000|8080'
```

*Shows which services are listening on ports 8000 (LlamaCPP) and 8080 (SearXNG).*

✅ Confirms the APIs are exposed to your host machine.

---

### **5️⃣ Test API endpoints from host**

```bash
curl -s "http://localhost:8000/"
curl -s "http://localhost:8080/search?q=hello&format=json"
```

* First command: should return LlamaCPP API info
* Second command: should return JSON search results from SearXNG

✅ Confirms the services are reachable from outside Docker.

---

### **6️⃣ Debug LlamaCPP → SearXNG connection (optional)**

If LlamaCPP cannot reach SearXNG:

```bash
docker exec -it llamacpp-api bash
apt-get update
apt-get install -y curl
curl -v http://searxng:8080/search?q=test
```

---

## 🔄 Persistence & Reboot Safety

**Stop old containers and remove old network/volume (if any):**
```bash
docker stop llamacpp-api searxng 2>/dev/null
docker rm llamacpp-api searxng 2>/dev/null
docker network rm llama-searx-net 2>/dev/null
docker volume rm searxng-config 2>/dev/null
````

**Recreate network and volume:**

```bash
docker network create llama-searx-net
docker volume create searxng-config
```

**Build LlamaCPP container (latest code):**

```bash
cd $HOME/llamacpp-searx/llamacpp
docker build --no-cache -t llamacpp-api .

```

**Run LlamaCPP API (choose restart behavior):**

```bash
# Automatically restart on reboot
docker run -d --restart unless-stopped --network llama-searx-net -p 8000:8000 --name llamacpp-api llamacpp-api

# OR do NOT restart on reboot
# docker run -d --network llama-searx-net -p 8000:8000 --name llamacpp-api llamacpp-api
```

**Run SearXNG container using Docker volume (choose restart behavior):**

```bash
docker rm -f searxng 2>/dev/null

# Automatically restart on reboot
docker run -d --restart unless-stopped --network llama-searx-net --name searxng -p 8080:8080 -v searxng-config:/etc/searxng searxng/searxng:latest

# OR do NOT restart on reboot
# docker run -d --network llama-searx-net --name searxng -p 8080:8080 -v searxng-config:/etc/searxng searxng/searxng:latest

```

**Test connectivity:**

```bash
curl -s "http://localhost:8000/generate?prompt=What+is+the+latest+news+today?Quote+Sources" | jq
```

✅ Works, persists across reboots, optionally restarts containers.

---

## 🔄 Rebuild Notes

If you update your `main.py` or replace the model, and want to refresh the LlamaCPP image:

```base
cd $HOME/llamacpp-searx/llamacpp

# Rebuild image from scratch (no cache)
docker build --no-cache -t llamacpp-api .

# Remove old container if it exists
docker rm -f llamacpp-api 2>/dev/null

# Run the new container
# Automatically restarts on reboot
docker run -d --restart unless-stopped --network llama-searx-net -p 8000:8000 --name llamacpp-api llamacpp-api
```

---

## 📝 Sample Prompt Tests

```bash
curl -s "http://localhost:8000/generate?prompt=What+is+the+latest+news+today?" | jq
curl -s "http://localhost:8000/generate?prompt=Summarize+the+top+headlines+in+technology." | jq
curl -s "http://localhost:8000/generate?prompt=Tell+me+a+fun+fact+about+space." | jq
```

✅ Returns JSON output from LlamaCPP, optionally using live SearXNG results.

---
# 📝 Note
 With everything set up and linked properly, you can now:
 1. Use a simple test script like `test.py` to query the API.
 2. Or create a full application around these querying methods.
 Both approaches can dynamically pull responses from LlamaCPP and optionally live search results from SearXNG.
---


