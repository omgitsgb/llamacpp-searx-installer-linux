
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

## **Manual LlamaCPP + SearXNG Setup (Ubuntu 24.04)**

### **1. Update system & install basics**

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl lsb-release ca-certificates gnupg
```

---

### **2. Remove any old/broken Docker remnants**

```bash
sudo apt remove -y docker.io docker-compose docker-compose-plugin containerd runc
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo apt-get autoremove -y
sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker /etc/apt/keyrings/docker* /etc/apt/sources.list.d/docker*
```

---

### **3. Add Docker GPG key & repository**

```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

UBUNTU_CODENAME=$(lsb_release -cs)
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list
```

---

### **4. Update package list & install Docker**

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

**Test Docker:**

```bash
docker --version
sudo docker run hello-world
```

---

### **5. Create Docker network**

```bash
docker network create llama-searx-net
```

---

### **6. Clone or update LlamaCPP repo**

```bash
cd $HOME
git clone https://github.com/omgitsgb/llamacpp-searx-installer-linux.git
# If already cloned, update:
# cd llamacpp-searx-installer-linux
# git pull
```

---

### **7. Prepare LLaMA model**

```bash
mkdir -p $HOME/llamacpp-searx-installer-linux/models
cd $HOME/llamacpp-searx-installer-linux/models
# Download model (replace MODEL_URL with the correct URL if needed)
curl -L -O https://huggingface.co/hugging-quants/Llama-3.2-1B-Instruct-Q8_0-GGUF/resolve/main/llama-3.2-1b-instruct-q8_0.gguf
```

---

### **8. Build LlamaCPP Docker image**

```bash
cd $HOME/llamacpp-searx-installer-linux
docker build --no-cache -t llamacpp-api .
```

---

### **9. Run LlamaCPP container**

```bash
docker rm -f llamacpp-api 2>/dev/null
docker run -d --restart unless-stopped --network llama-searx-net -p 8000:8000 --name llamacpp-api llamacpp-api
```


---

### **10. Prepare SearXNG folder & settings**

```bash
mkdir -p $HOME/searxng
nano $HOME/searxng/settings.yml
# Paste this into settings.yml:
# use_default_settings: true
# general:
#   debug: false
#   instance_name: "SearXNG"
# server:
#   bind_address: "0.0.0.0"
#   port: 8080
#   secret_key: "mR7q4vF9sP2xZ8jWkL1uB0yT6cE3nA5"
#   public_instance: false
# engines:
#   - name: duckduckgo
#     disabled: false
#   - name: google
#     disabled: false
#   - name: bing
#     disabled: false
```

---

### **11. Run SearXNG container**

```bash
docker rm -f searxng 2>/dev/null
docker volume create searxng-config
docker run -d --restart unless-stopped --network llama-searx-net --name searxng -p 8080:8080 -v searxng-config:/etc/searxng searxng/searxng:latest
docker cp $HOME/searxng/settings.yml searxng:/etc/searxng/settings.yml
```

**Check SearXNG:**

```bash
curl "http://localhost:8080/search?q=hello&format=json"
```

---

### ✅ **12. Optional Tests**

* Test LlamaCPP:

```bash
curl "http://localhost:8000/generate?prompt=Hello+world"
```

* Test container connectivity:

```bash
docker exec llamacpp-api curl -s http://searxng:8080/search?q=test
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

