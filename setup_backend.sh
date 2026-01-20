#!/bin/bash

# TinyDictate Backend Setup Script
# This script sets up the Python environment for the TinyDictate backend

set -e

echo "=== TinyDictate Backend Setup ==="
echo ""

# Configuration
APP_SUPPORT_DIR="$HOME/Library/Application Support/TinyDictate"
VENV_DIR="$APP_SUPPORT_DIR/venv"
BACKEND_DIR="$APP_SUPPORT_DIR/backend"

# Find Python
find_python() {
    local pythons=(
        "/opt/homebrew/bin/python3.11"
        "/opt/homebrew/bin/python3.12"
        "/opt/homebrew/bin/python3"
        "/usr/local/bin/python3.11"
        "/usr/local/bin/python3.12"
        "/usr/local/bin/python3"
        "/usr/bin/python3"
        "python3"
    )
    
    for py in "${pythons[@]}"; do
        if command -v "$py" &> /dev/null; then
            version=$("$py" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
            major=$(echo "$version" | cut -d. -f1)
            minor=$(echo "$version" | cut -d. -f2)
            
            if [ "$major" -ge 3 ] && [ "$minor" -ge 11 ]; then
                echo "$py"
                return 0
            fi
        fi
    done
    
    return 1
}

# Check for Python 3.11+
echo "Checking for Python 3.11+..."
PYTHON=$(find_python)

if [ -z "$PYTHON" ]; then
    echo "Error: Python 3.11 or later is required but not found."
    echo ""
    echo "Please install Python 3.11+ using one of these methods:"
    echo "  1. Homebrew: brew install python@3.11"
    echo "  2. Official installer: https://www.python.org/downloads/"
    echo ""
    exit 1
fi

echo "Found Python: $PYTHON"
$PYTHON --version
echo ""

# Create directories
echo "Creating application directories..."
mkdir -p "$APP_SUPPORT_DIR"
mkdir -p "$BACKEND_DIR"
mkdir -p "$APP_SUPPORT_DIR/Models"
echo "  Created: $APP_SUPPORT_DIR"
echo ""

# Copy backend files
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/backend/main.py" ]; then
    echo "Copying backend files..."
    cp -r "$SCRIPT_DIR/backend/"* "$BACKEND_DIR/"
    echo "  Copied to: $BACKEND_DIR"
    echo ""
fi

# Create virtual environment
if [ -d "$VENV_DIR" ]; then
    echo "Virtual environment already exists at $VENV_DIR"
    read -p "Do you want to recreate it? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing existing virtual environment..."
        rm -rf "$VENV_DIR"
    else
        echo "Using existing virtual environment."
    fi
fi

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..."
    $PYTHON -m venv "$VENV_DIR"
    echo "  Created: $VENV_DIR"
    echo ""
fi

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip
echo ""

# Install dependencies
echo "Installing dependencies..."
echo "This may take several minutes due to PyTorch and NeMo downloads."
echo ""

# Install PyTorch first (CPU version for simplicity)
echo "Installing PyTorch..."
pip install torch torchvision torchaudio
echo ""

# Install other dependencies
echo "Installing remaining dependencies..."
pip install websockets>=12.0 numpy>=1.24.0 huggingface_hub>=0.20.0
echo ""

# Install NeMo (this is the largest dependency)
echo "Installing NeMo Toolkit..."
echo "Note: This is a large package (~500MB+) and may take a while."
pip install nemo_toolkit[asr]>=1.22.0
echo ""

# Verify installation
echo "Verifying installation..."
python -c "
import torch
print(f'  PyTorch version: {torch.__version__}')
print(f'  MPS available: {torch.backends.mps.is_available()}')

import nemo.collections.asr as nemo_asr
print('  NeMo ASR: OK')

import websockets
print('  Websockets: OK')

from huggingface_hub import hf_hub_download
print('  Hugging Face Hub: OK')

print('')
print('All dependencies installed successfully!')
"

# Create a launcher script
LAUNCHER="$APP_SUPPORT_DIR/run_backend.sh"
cat > "$LAUNCHER" << EOF
#!/bin/bash
source "$VENV_DIR/bin/activate"
cd "$BACKEND_DIR"
python main.py "\$@"
EOF
chmod +x "$LAUNCHER"
echo ""
echo "Created launcher script: $LAUNCHER"

# Summary
echo ""
echo "=== Setup Complete ==="
echo ""
echo "The TinyDictate backend is now configured."
echo ""
echo "Locations:"
echo "  Virtual environment: $VENV_DIR"
echo "  Backend code: $BACKEND_DIR"
echo "  Models cache: $APP_SUPPORT_DIR/Models"
echo ""
echo "To run the backend manually:"
echo "  $LAUNCHER --port 9877"
echo ""
echo "Next steps:"
echo "  1. Open the TinyDictate app"
echo "  2. The app will start the backend automatically"
echo "  3. On first use, download the model in Settings > Model"
echo ""
