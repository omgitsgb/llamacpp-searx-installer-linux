#!/bin/bash
set -e

# ==================================================
# LlamaCPP + SearXNG NATIVE INSTALLER (CLEAN FIXED)
# ==================================================

INSTALL_FOLDER="$HOME/llamacpp-searx"
LLAMA_FOLDER="$INSTALL_FOLDER/llamacpp"
SEARX_FOLDER="$INSTALL_FOLDER/searxng"

MODEL="llama-3.2-1b-instruct-q8_0.gguf"
MODEL_URL="https://huggingface.co/hugging-quants/Llama-3.2-1B-Instruct-Q8_0-GGUF/resolve/main/$MODEL"

echo "===================================="
echo "  LlamaCPP + SearXNG SETUP"
echo "===================================="

# ==================================================
# GPU DETECTION
# ==================================================
DEVICE_CHOICE="cpu"

if command -v nvidia-smi &>/dev/null; then
    echo "✅ NVIDIA GPU detected"
    read -p "Use GPU for llama-cpp-python? (gpu/cpu) " GPU_INPUT
    if [[ "$GPU_INPUT" =~ ^[Gg][Pp][Uu]$ ]]; then
        DEVICE_CHOICE="gpu"
        echo "🚀 GPU MODE"
    else
        echo "🧠 CPU MODE"
    fi
else
    echo "⚠️ No NVIDIA GPU detected (CPU mode)"
fi

# ==================================================
# 1. LLAMA SERVER
# ==================================================
echo ""
echo "=============================="
echo "Cloning / Updating Llama Repo"
echo "=============================="

mkdir -p "$INSTALL_FOLDER"

if [ -d "$LLAMA_FOLDER/.git" ]; then
    cd "$LLAMA_FOLDER"
    git pull
else
    git clone https://github.com/omgitsgb/llamacpp-searx-installer-linux.git "$LLAMA_FOLDER"
fi

cd "$LLAMA_FOLDER"

echo "Creating Llama venv..."
rm -rf venv
python3 -m venv venv
source venv/bin/activate

python -m pip install --upgrade pip setuptools wheel

pip uninstall -y llama-cpp-python || true
pip cache purge || true

if [ "$DEVICE_CHOICE" = "gpu" ]; then
    echo "🔥 GPU BUILD (GGML_CUDA)"
    CMAKE_ARGS="-DGGML_CUDA=on -DCMAKE_BUILD_TYPE=Release" \
    FORCE_CMAKE=1 \
    pip install --no-cache-dir llama-cpp-python
else
    echo "🔵 CPU BUILD"
    pip install llama-cpp-python
fi

echo "Installing core backend dependencies..."
pip install fastapi "uvicorn[standard]" requests

deactivate

# ==================================================
# PATCH SEARX URL IN MAIN.PY
# ==================================================
echo "Patching SEARX_URL in main.py..."

cd "$LLAMA_FOLDER"

if [ -f "main.py" ]; then
    sed -i 's|SEARX_URL = "http://searxng:8080/search"|SEARX_URL = "http://localhost:8080/search"|g' main.py
    echo "✅ SEARX_URL set to localhost"
else
    echo "⚠️ main.py not found — skipping patch"
fi

# ==================================================
# MODEL DOWNLOAD
# ==================================================
mkdir -p "$LLAMA_FOLDER/models"
MODEL_PATH="$LLAMA_FOLDER/models/$MODEL"

if [ ! -f "$MODEL_PATH" ]; then
    read -p "Download model? (Y/N) " m
    if [[ "$m" =~ ^[Yy]$ ]]; then
        curl -L "$MODEL_URL" -o "$MODEL_PATH"
    fi
fi

# ==================================================
# 2. SEARXNG INSTALL (FIXED PATHING)
# ==================================================
echo ""
echo "=============================="
echo "Cloning + Installing SearXNG"
echo "=============================="

mkdir -p "$INSTALL_FOLDER"
cd "$INSTALL_FOLDER"

rm -rf searxng
git clone https://github.com/searxng/searxng.git searxng

cd "$SEARX_FOLDER"

echo "Creating SearXNG venv..."
python3.11 -m venv venv
source venv/bin/activate

pip install --upgrade pip setuptools wheel
pip install -r requirements.txt
pip install msgspec pyyaml gunicorn typing_extensions packaging

pip install --no-build-isolation -e .

python - <<EOF
import searx
print("✅ SearXNG installed correctly")
EOF

# ==================================================
# SETTINGS FILE
# ==================================================
echo "Writing settings.yml..."

cd "$SEARX_FOLDER/searx"

rm -f settings.yml

cat > settings.yml <<'EOF'
debug: true
instance_name: "SearXNG"
privacypolicy_url: false
donation_url: false
contact_url: false
enable_metrics: true
open_metrics: ''

brand:
  docs_url: https://docs.searxng.org/
  public_instances: https://searx.space
  wiki_url: https://github.com/searxng/searxng/wiki
  issue_url: https://github.com/searxng/searxng/issues

search:
  safe_search: 0
  autocomplete: ""
  autocomplete_min: 4
  favicon_resolver: ""
  default_lang: "auto"
  ban_time_on_fail: 5
  max_ban_time_on_fail: 120
  suspended_times:
    SearxEngineAccessDenied: 180
    SearxEngineCaptcha: 3600
    SearxEngineTooManyRequests: 180
    cf_SearxEngineCaptcha: 1296000
    cf_SearxEngineAccessDenied: 86400
    recaptcha_SearxEngineCaptcha: 604800
  formats:
    - html
    - json

server:
  bind_address: "0.0.0.0"
  port: 8080
  secret_key: "masfasgfweagewsgewsgewsgewsgewsgwesg"
  public_instance: false

botdetection:
  enabled: false
  whitelist:
    - 127.0.0.1
    - ::1

limiter:
  enabled: false

valkey:
  url: false

ui:
  static_path: ""
  templates_path: ""
  query_in_title: false
  default_theme: simple
  center_alignment: false
  default_locale: ""
  theme_args:
    simple_style: auto
  search_on_category_select: true
  hotkeys: default
  url_formatting: pretty

outgoing:
  request_timeout: 3.0
  useragent_suffix: ""
  pool_connections: 100
  pool_maxsize: 20
  enable_http2: true

plugins:
  searx.plugins.calculator.SXNGPlugin:
    active: true

  searx.plugins.infinite_scroll.SXNGPlugin:
    active: false

  searx.plugins.hash_plugin.SXNGPlugin:
    active: true

  searx.plugins.self_info.SXNGPlugin:
    active: true

  searx.plugins.unit_converter.SXNGPlugin:
    active: true

  searx.plugins.ahmia_filter.SXNGPlugin:
    active: true

  searx.plugins.hostnames.SXNGPlugin:
    active: true

  searx.plugins.time_zone.SXNGPlugin:
    active: true

  searx.plugins.oa_doi_rewrite.SXNGPlugin:
    active: false

  searx.plugins.tor_check.SXNGPlugin:
    active: false

  searx.plugins.tracker_url_remover.SXNGPlugin:
    active: true

categories_as_tabs:
  general:
  images:
  videos:
  news:
  map:
  music:
  it:
  science:
  files:
  social media:

engines:
  - name: duckduckgo
    engine: duckduckgo
    shortcut: ddg

  - name: google
    engine: google
    shortcut: go

  - name: bing
    engine: bing
    shortcut: bi
    disabled: true

  - name: yahoo
    engine: yahoo
    shortcut: yh
    disabled: true

  - name: yahoo news
    engine: yahoo_news
    shortcut: yhn

  - name: youtube
    shortcut: yt
    engine: youtube_noapi

  - name: youtube_api
    engine: youtube_api
    shortcut: yta
    inactive: true

  - name: braveapi
    engine: braveapi
    api_key: ""
    inactive: true

  - name: brave
    engine: brave
    shortcut: br
    time_range_support: true
    paging: true
    categories: [general, web]

  - name: wikipedia
    engine: wikipedia
    shortcut: wp
    display_type: ["infobox"]
    categories: [general]

  - name: bing news
    engine: bing_news
    shortcut: bin

  - name: duckduckgo news
    engine: duckduckgo_extra
    categories: [news]
    ddg_category: news
    shortcut: ddn

doi_resolvers:
  oadoi.org: 'https://oadoi.org/'
  doi.org: 'https://doi.org/'
  sci-hub.se: 'https://sci-hub.se/'
  sci-hub.st: 'https://sci-hub.st/'
  sci-hub.ru: 'https://sci-hub.ru/'

default_doi_resolver: 'oadoi.org'

EOF

deactivate

# ==================================================
# DONE
# ==================================================
echo ""
echo "🎉 INSTALL COMPLETE"
echo "===================================="
echo "LLAMA: $LLAMA_FOLDER"
echo "SEARX: $SEARX_FOLDER"
echo "===================================="

echo ""
echo "STEP 1 - RUN SEARXNG:"
echo "cd $SEARX_FOLDER"
echo "source venv/bin/activate"
echo "gunicorn -w 4 -b 0.0.0.0:8080 searx.webapp:app --log-level debug"

echo ""
echo "STEP 2 - RUN LLAMA:"
echo "cd $LLAMA_FOLDER"
echo "source venv/bin/activate"
echo "python3 -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload"
