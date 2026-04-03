import os
import requests
from fastapi import FastAPI, HTTPException
from llama_cpp import Llama

# ---------------------------
# Configuration
# ---------------------------

# Automatically find the first .gguf model in the models/ folder
MODEL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models")
gguf_models = [f for f in os.listdir(MODEL_DIR) if f.endswith(".gguf")]

if not gguf_models:
    raise FileNotFoundError(f"No .gguf model found in {MODEL_DIR}")

MODEL_PATH = os.path.join(MODEL_DIR, gguf_models[0])

# Initialize LLaMA
llm = Llama(model_path=MODEL_PATH)

# Initialize FastAPI
app = FastAPI()

# Trigger words for SearXNG search
SEARCH_TRIGGERS = ["news", "latest", "current", "update", "headlines"]

# SearXNG endpoint (default to Docker container network)
SEARX_URL = os.getenv("SEARX_URL", "http://searxng:8080/search")

# ---------------------------
# Helper: Perform a SearXNG search
# ---------------------------
def searx_search(query):
    try:
        params = {"q": query, "format": "json"}
        resp = requests.get(SEARX_URL, params=params, timeout=10)
        resp.raise_for_status()
        data = resp.json()
        
        snippets = []
        for result in data.get("results", []):
            content = result.get("content") or f"{result.get('title','')} : {result.get('description','')}"
            if content:
                snippets.append(content)
        return snippets[:5]  # top 5 results
    except Exception as e:
        return [f"[Error fetching search results: {e}]"]

# ---------------------------
# Routes
# ---------------------------
@app.get("/")
def read_root():
    return {"message": f"LlamaCPP API is running with model {gguf_models[0]}"}

@app.get("/generate")
def generate(prompt: str):
    try:
        search_results = []
        search_triggered = False
        full_prompt = prompt

        # Check for trigger words
        if any(word.lower() in prompt.lower() for word in SEARCH_TRIGGERS):
            search_results = searx_search(prompt)
            search_text = "\n".join(search_results)
            full_prompt = f"{prompt}\n\nHere is some recent content from the web:\n{search_text}"
            search_triggered = True

        # Run the model
        output = llm(full_prompt, max_tokens=200)

        return {
            "prompt": prompt,
            "search_triggered": search_triggered,
            "search_results": search_results,
            "model_output": output['choices'][0]['text']
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
