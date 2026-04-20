import os
import logging
import requests
import subprocess

from fastapi import FastAPI, HTTPException
from llama_cpp import Llama

# ==================================================
# CONFIG
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
# CUDA CHECK
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
        n_gpu_layers=50 if use_cuda else 0
    )

    logging.info("Model loaded")
    logging.info("CUDA enabled" if use_cuda else "CPU mode")

# ==================================================
# SEARCH
# ==================================================

def searx_search(query):
    try:
        resp = requests.get(
            SEARX_URL,
            params={"q": query, "format": "json"},
            headers={"User-Agent": "Mozilla/5.0"},
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
        logging.error(f"SearX error: {e}")
        return []

# ==================================================
# CORE GENERATION (FULLY SIMPLIFIED)
# ==================================================

def generate_response(prompt: str):
    prompt_lower = prompt.lower()

    # direct inline trigger logic (NO helper function)
    search_triggered = (
        len(prompt.split()) >= 3 and
        any(word in prompt_lower for word in SEARCH_TRIGGERS)
    )

    search_results = searx_search(prompt) if search_triggered else []

    if search_triggered and search_results:
        numbered = "\n".join([
            f"{i+1}. {r['title']}\n{r['content'][:300]}\n{r['url']}"
            for i, r in enumerate(search_results)
        ])

        full_prompt = f"""
You are a real-time news analyst.

Use ONLY the sources below.

SOURCES:
{numbered}

QUESTION:
{prompt}

ANSWER:
"""
    else:
        full_prompt = f"""
You are a helpful assistant.

User: {prompt}
Assistant:
"""

    output = llm(full_prompt, max_tokens=MAX_TOKENS)
    text = output["choices"][0]["text"]

    return {
        "prompt": prompt,
        "search_triggered": search_triggered,
        "search_results": search_results,
        "output": text
    }

# ==================================================
# ROUTES
# ==================================================

@app.get("/")
def root():
    return {"message": f"LlamaCPP API running with {gguf_models[0]}"}


@app.get("/generate")
def generate(prompt: str):
    if llm is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet")

    return generate_response(prompt)
