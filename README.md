LlamaCPP + SearXNG Networked Installer

This repository provides a full automated setup for running LlamaCPP with SearXNG in Docker on Linux.
The setup allows LlamaCPP to dynamically query SearXNG for real-time search results when generating responses.

Features
Fully automated Linux installer script (installer.sh).
Automatically installs Git and Docker if missing.
Creates a dedicated Docker network for LlamaCPP and SearXNG.
Downloads LLaMA 3.2 1B GGUF model if not already present.
Builds and runs LlamaCPP API container.
Sets up SearXNG container with JSON and HTML search support.
End-to-end API test suite included.
Requirements
Linux (tested on Ubuntu)
curl, git, docker (installed automatically if missing)
Internet connection for downloading model and Docker images
Installation

Clone the repository:

git clone https://github.com/omgitsgb/llamacpp-searx-installer-linux.git
cd llamacpp-searx-installer-linux

Run the installer:

chmod +x installer.sh
./installer.sh

The script will:

Install Git and Docker if missing.
Remove old Docker/Podman remnants.
Create a Docker network (llama-searx-net).
Clone/update LlamaCPP repository and download the model.
Build and run LlamaCPP container on port 8000.
Create SearXNG configuration and run container on port 8080.
Run end-to-end API tests.
Usage
LlamaCPP API

The LlamaCPP FastAPI server runs on port 8000.

Example request:

curl -s -G "http://localhost:8000/generate" --data-urlencode "prompt=What is the latest news today?" | jq
Automatically triggers SearXNG search if prompt contains keywords like:
news, latest, update, headlines.
Returns JSON object with:
prompt
search_triggered (bool)
search_results (array)
output (generated text)
SearXNG
Runs on port 8080.
Accessible inside Docker network at http://searxng:8080.
Supports JSON and HTML results.
Example query:
curl -s "http://localhost:8080/search?q=latest+news&format=json" | jq
File Structure
llamacpp-searx-installer-linux/
├─ installer.sh          # Main installer script
├─ models/               # LLaMA GGUF models
├─ llama_api.py          # FastAPI LlamaCPP server
├─ README.md             # This file
Docker Network

Both containers share a dedicated Docker network:

Network name: llama-searx-net
Allows LlamaCPP to reach SearXNG via container name searxng:8080.
End-to-End API Tests
# SearXNG search only
curl -s "http://localhost:8080/search?q=latest+news&format=json" | jq

# LLaMA without search trigger
curl -s "http://localhost:8000/generate?prompt=Hello+world" | jq

# LLaMA with search trigger
curl -s "http://localhost:8000/generate?prompt=What+is+the+latest+news+today?" | jq
Troubleshooting
If containers fail to start, check logs:
docker logs llamacpp-api
docker logs searxng
If ports 8000 or 8080 are in use, either stop conflicting services or change LLAMA_PORT / SEARX_PORT in installer.sh.
Ensure your Linux user has permissions to run Docker without sudo.
Notes
Model: llama-3.2-1b-instruct-q8_0.gguf from HuggingFace.
End-to-end tests are included in installer.sh and can be rerun anytime.
Both containers are connected internally via Docker network for seamless API calls.
]]]
