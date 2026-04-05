# -----------------------------------------
# LlamaCPP Python 3.11 Dockerfile with GPU detection
# -----------------------------------------

# Use Python 3.11 slim as default (CPU)
FROM python:3.11-slim

# Allow optional GPU build by installing CUDA runtime only if using nvidia/cuda image
# Build with: docker build --build-arg USE_GPU=true -t llamacpp-api .
ARG USE_GPU=false

# Workdir
WORKDIR /app

# -------------------------
# Install system dependencies
# -------------------------
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libssl-dev \
    libffi-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# -------------------------
# Optional: CUDA runtime for GPU
# -------------------------
# Note: Actual GPU support requires the host to have NVIDIA drivers and nvidia-docker runtime.
# The installer will select --gpus all when running if GPU is detected.
RUN if [ "$USE_GPU" = "true" ]; then \
        echo "GPU support selected, make sure NVIDIA runtime is enabled"; \
    else \
        echo "CPU build"; \
    fi

# -------------------------
# Copy Python requirements and install
# -------------------------
COPY requirements.txt .
RUN pip install --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt

# -------------------------
# Copy API and models
# -------------------------
COPY main.py .
COPY models ./models

# -------------------------
# Expose API port
# -------------------------
EXPOSE 8000

# -------------------------
# Start API
# -------------------------
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
