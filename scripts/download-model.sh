#!/usr/bin/env bash
#
# download-model.sh - Download a GGUF model from Hugging Face to the local models directory
#
# Usage:
#   ./scripts/download-model.sh <repo-id> [<filename>] [target_dir]
#
# Examples:
#   ./scripts/download-model.sh meta-llama/Llama-3.2-1B-Instruct
#   ./scripts/download-model.sh TheBloke/Mistral-7B-Instruct-v0.2 Q4_K_M.gguf
#   ./scripts/download-model.sh Qwen/Qwen2.5-7B-Instruct-GGUF qwen2.5-7b-instruct-q4_k_m.gguf ./custom_models
#

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <repo-id> [<filename>] [target_dir]"
    echo ""
    echo "Arguments:"
    echo "  repo-id      Hugging Face repository ID (e.g., TheBloke/Llama-2-7B-GGUF)"
    echo "  filename     Optional: specific GGUF file to download"
    echo "  target_dir   Optional: target directory (default: ./models)"
    exit 1
fi

REPO_ID="$1"
FILENAME="${2:-}"
TARGET_DIR="${3:-./models}"

# Resolve target directory
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Creating target directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi

echo "========================================"
echo "  Downloading Model"
echo "========================================"
echo "Repo:       $REPO_ID"
echo "Filename:   ${FILENAME:-<auto-detect>}"
echo "Target:     $TARGET_DIR"
echo "========================================"
echo ""

# Install huggingface-cli if not present
if ! command -v huggingface-cli &> /dev/null; then
    echo "Installing huggingface-cli..."
    pip install --user huggingface_hub
    export PATH="$HOME/.local/bin:$PATH"
fi

# Check if repo exists
echo "Checking repository..."
if ! huggingface-cli repo-info "$REPO_ID" &> /dev/null; then
    echo "Error: Repository '$REPO_ID' not found."
    exit 1
fi

# If no filename specified, list GGUF files and let user choose
if [[ -z "$FILENAME" ]]; then
    echo "Available GGUF files:"
    echo "----------------------------------------"
    huggingface-cli list-files "$REPO_ID" | grep -i '\.gguf$' | sort -k1 | nl
    echo ""
    echo "Enter the number of the file to download (or 'a' for all):"
    read -r choice
    
    if [[ "$choice" == "a" ]]; then
        echo "Downloading all GGUF files..."
        huggingface-cli download "$REPO_ID" --include "*.gguf" --local-dir "$TARGET_DIR"
    else
        FILENAME=$(huggingface-cli list-files "$REPO_ID" | grep -i '\.gguf$' | sort -k1 | sed -n "${choice}p" | awk '{print $1}')
        if [[ -z "$FILENAME" ]]; then
            echo "Error: Invalid selection."
            exit 1
        fi
    fi
fi

# Download the specified file
echo "Downloading $FILENAME..."
huggingface-cli download "$REPO_ID" "$FILENAME" --local-dir "$TARGET_DIR"

echo ""
echo "Download complete!"
echo "Model location: $(realpath "$TARGET_DIR")/$FILENAME"
