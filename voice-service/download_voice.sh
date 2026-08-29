#!/bin/bash
# Downloads the Piper TTS voice model used by main.py. Run once after
# `pip install -r requirements.txt`.
set -e
cd "$(dirname "$0")"
mkdir -p models
curl -sL -o models/en_GB-jenny_dioco-medium.onnx \
  "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/jenny_dioco/medium/en_GB-jenny_dioco-medium.onnx"
curl -sL -o models/en_GB-jenny_dioco-medium.onnx.json \
  "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/jenny_dioco/medium/en_GB-jenny_dioco-medium.onnx.json"
echo "Downloaded Piper voice model (Jenny, British English) to models/"
