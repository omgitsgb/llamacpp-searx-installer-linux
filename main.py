import os
import requests
import logging
from fastapi import FastAPI, HTTPException
from llama_cpp import Llama
from functools import lru_cache
import re

# =====================================================
# 1. Configuration
# =====================================================

# Base directory where this script is located
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Folder where GGUF models are stored
MODEL_DIR = os.path.join(BASE_DIR, "models")

# List all .gguf files in the models folder
gguf_models = [f for f in os.listdir(MODEL_DIR) if f.endswith(".gguf")]

# Raise error if no model found
if not gguf_models:
    raise FileNotFoundError(f"No .gguf model found in {MODEL_DIR}")

# Use the first model found
MODEL_PATH = os.path.join(MODEL_DIR, gguf_models[0])

# Initialize LLaMA with a large context window for longer responses
llm = Llama(model_path=MODEL_PATH, n_ctx=8192)

# Initialize FastAPI app
app = FastAPI()

# =====================================================
# 2. Logging
# =====================================================

# Configure basic logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

# =====================================================
# 3. Search Configuration
# =====================================================

# Keywords that trigger a SearXNG search
SEARCH_TRIGGERS = ["news", "latest", "current", "update", "headlines"]

# URL for SearXNG, must use container hostname within Docker network
SEARX_URL = "http://searxng:8080/search"

# =====================================================
# 4. SearXNG Search Function
# =====================================================

def searx_search(query: str):
    """
    Perform a search request to the SearXNG instance.
    Returns top 5 results with title, content, and URL.
    """
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

            # Only include results with any content
            if title or content or url:
                results.append({
                    "title": title.strip(),
                    "content": content.strip(),
                    "url": url.strip()
                })

        return results[:5]  # Limit to top 5

    except Exception as e:
        logging.error(f"SearXNG error: {e}")
        return []

# =====================================================
# 5. Cache Search Results
# =====================================================

@lru_cache(maxsize=128)
def cached_searx_search(query: str):
    """
    Cache results to reduce repeated API calls to SearXNG.
    """
    return searx_search(query)

# =====================================================
# 6. Search Trigger Detection
# =====================================================

def is_search_triggered(prompt: str):
    """
    Check if the user's prompt contains keywords that trigger a search.
    """
    prompt_lower = prompt.lower()
    return any(re.search(rf"\b{re.escape(word)}\b", prompt_lower) for word in SEARCH_TRIGGERS)

# =====================================================
# 7. FastAPI Routes
# =====================================================

@app.get("/")
def read_root():
    """
    Root endpoint to verify API is running.
    """
    return {"message": f"LlamaCPP API running with {gguf_models[0]}"}

@app.get("/generate")
def generate(prompt: str):
    """
    Main endpoint to generate text from a prompt.
    Performs search if prompt triggers it.
    """
    logging.info(f"Prompt received: {prompt}")

    try:
        search_triggered = False
        search_results = []

        # Trigger search if prompt contains keywords
        if is_search_triggered(prompt):
            search_triggered = True
            search_results = cached_searx_search(prompt)

        # -------------------------------------------------
        # Build full prompt for LLaMA
        # -------------------------------------------------
        if search_results:
            # Format search results for context
            numbered_results = "\n".join([
                f"{i+1}. {r['title']}\n{r['content'][:300]}\n{r['url']}"
                for i, r in enumerate(search_results)
            ])

            full_prompt = f"""
Use the search results below to answer the question.

Provide a clear and detailed summary of the most important information.
If multiple relevant points exist, include them.

Question:
{prompt}

Search Results:
{numbered_results}

Answer:
"""
        else:
            # Use original prompt if no search triggered
            full_prompt = prompt

        # -------------------------------------------------
        # Generate output using LLaMA
        # -------------------------------------------------
        output = llm(
            full_prompt,
            max_tokens=500,   # Allow longer responses
            temperature=0.7   # Slight randomness for natural answers
        )

        text_output = output["choices"][0]["text"].strip()

        # -------------------------------------------------
        # Return response
        # -------------------------------------------------
        return {
            "prompt": prompt,
            "search_triggered": search_triggered,
            "search_results": search_results,
            "output": text_output
        }

    except Exception as e:
        logging.error(f"API error: {e}")
        raise HTTPException(status_code=500, detail=str(e))
