import os
import requests
import logging
from fastapi import FastAPI, HTTPException
from llama_cpp import Llama

# ---------------------------
# Config
# ---------------------------
MODEL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models")
gguf_models = [f for f in os.listdir(MODEL_DIR) if f.endswith(".gguf")]

if not gguf_models:
    raise FileNotFoundError(f"No .gguf model found in {MODEL_DIR}")

MODEL_PATH = os.path.join(MODEL_DIR, gguf_models[0])
llm = Llama(model_path=MODEL_PATH, n_ctx=4096)

app = FastAPI()
logging.basicConfig(level=logging.INFO)

SEARCH_TRIGGERS = ["news", "latest", "current", "update", "headlines"]
SEARX_URL = "http://host.docker.internal:8080/search"  # Connect to your host SearXNG

# ---------------------------
# Search helper
# ---------------------------
def searx_search(query):
    try:
        resp = requests.get(SEARX_URL, params={"q": query, "format": "json"}, timeout=10)
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

# ---------------------------
# Routes
# ---------------------------
@app.get("/")
def read_root():
    return {"message": f"LlamaCPP API running with {gguf_models[0]}"}

@app.get("/generate")
def generate(prompt: str):
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

        output = llm(full_prompt, max_tokens=2000)
        return {
            "prompt": prompt,
            "search_triggered": search_triggered,
            "search_results": search_results,
            "output": output['choices'][0]['text'].strip()
        }
    except Exception as e:
        logging.error(e)
        raise HTTPException(status_code=500, detail=str(e))
