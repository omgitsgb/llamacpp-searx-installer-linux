import requests
import json

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
        # Use GET with URL-encoded prompt
        response = requests.get(LLAMA_API_URL, params={"prompt": prompt}, timeout=10)
        response.raise_for_status()
        data = response.json()

        print("\n" + "="*40)
        print(f"Prompt: {prompt}")
        print("Search Triggered:", data.get("search_triggered"))
        print("Search Results:", [r['title'] for r in data.get("search_results", [])])
        print("Generated Output:\n", data.get("output"))
        print("="*40 + "\n")

    except Exception as e:
        print(f"Error with prompt '{prompt}': {e}")
