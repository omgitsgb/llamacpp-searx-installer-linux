import os
import logging
import requests
import subprocess

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

SEARX_URL = "http://searxng:8080/search"

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
