import os
import requests
from fastapi import FastAPI, HTTPException
from llama_cpp import Llama

# ---------------------------
# Configuration
# ---------------------------
MODEL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models")
gguf_models = [f for f in os.listdir(MODEL_DIR) if f.endswith(".gguf")]

if not gguf_models:
    raise FileNotFoundError(f"No .gguf model found in {MODEL_DIR}")

MODEL_PATH = os.path.join(MODEL_DIR, gguf_models[0])

# Initialize LLaMA with a larger context window
llm = Llama(model_path=MODEL_PATH, n_ctx=8192)

app = FastAPI()

SEARCH_TRIGGERS = ["news", "latest", "current", "update", "headlines"]

# Always use local SearXNG
SEARX_URL = "http://localhost:8080/search"

# ---------------------------
# Helper: Perform SearXNG search
# ---------------------------
def searx_search(query):
    try:
        params = {"q": query, "format": "json"}
        resp = requests.get(SEARX_URL, params=params, timeout=10)
        resp.raise_for_status()
        data = resp.json()

        results = []
        for result in data.get("results", []):
            title = result.get("title", "")
            content = result.get("content") or result.get("description") or ""
            url = result.get("url", "")
            if title or content or url:
                results.append({
                    "title": title.strip(),
                    "content": content.strip(),
                    "url": url.strip()
                })

        return results[:5]  # top 5 results
    except Exception as e:
        return [{"title": "", "content": f"[Error fetching search results: {e}]", "url": ""}]

# ---------------------------
# Routes
# ---------------------------
@app.get("/")
def read_root():
    return {"message": f"LlamaCPP API is running with model {gguf_models[0]}"}

@app.get("/generate")
def generate(prompt: str):
    try:
        search_triggered = False
        search_results = []

        # Trigger SearXNG search if prompt contains trigger words
        if any(word.lower() in prompt.lower() for word in SEARCH_TRIGGERS):
            search_triggered = True
            search_results = searx_search(prompt)

        # Build full prompt for LLaMA
        if search_results:
            numbered_results = "\n".join([
                f"{i+1}. Title: {r['title']}\n   Content: {r['content'][:300]}\n   URL: {r['url']}"
                for i, r in enumerate(search_results)
            ])
            full_prompt = f"""
You are an AI assistant. Answer the following question using ONLY the information from the search results below.
If the answer is not fully in the results, summarize what is available. Do NOT include unrelated facts.

Question:
{prompt}

Search Results:
{numbered_results}

Answer:
"""
        else:
            full_prompt = prompt

        # Generate output
        output = llm(full_prompt, max_tokens=2000)

        return {
            "prompt": prompt,
            "search_triggered": search_triggered,
            "search_results": search_results,
            "output": output['choices'][0]['text'].strip()
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
