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

# Copy API and models
COPY llama_api.py .
COPY models ./models

EXPOSE 8000

CMD ["uvicorn", "llama_api:app", "--host", "0.0.0.0", "--port", "8000"]
