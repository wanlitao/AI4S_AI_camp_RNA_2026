#!/bin/bash

set -e

MODEL_NAME="protenix_base_default_v0.5.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JSON_DIR="${SCRIPT_DIR}/competition_datas"
OUTPUT_BASE="${SCRIPT_DIR}/protenix_outputs"
USE_MSA=false
SAMPLE_NUM="1"
TARGET_JSON_NAME="3"

export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"

echo "============================================"
echo " SAISfold Track A - Protenix large inference"
echo " Model: ${MODEL_NAME}"
echo " MSA: ${USE_MSA}"
echo " Target JSON: ${TARGET_JSON_NAME}.json"
echo " PYTORCH_CUDA_ALLOC_CONF: ${PYTORCH_CUDA_ALLOC_CONF}"
echo "============================================"

echo ""
echo "[Step 1/4] Check environment..."

if command -v nvidia-smi > /dev/null 2>&1; then
    GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo "unknown")
    echo "  GPU: ${GPU_INFO}"
else
    echo "  ERROR: nvidia-smi not found. NVIDIA GPU is required."
    exit 1
fi

if ! command -v python > /dev/null 2>&1; then
    echo "  ERROR: python not found. Please install Python 3.10+."
    exit 1
fi
PY_VER=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "  Python: ${PY_VER}"

echo ""
echo "[Step 2/4] Install or verify Protenix..."

if python -c "import protenix" 2>/dev/null; then
    PROT_VER=$(python -c "import importlib.metadata; print(importlib.metadata.version('protenix'))" 2>/dev/null || echo "unknown")
    echo "  Protenix already installed: v${PROT_VER}"
else
    echo "  Installing protenix..."
    pip install protenix
fi

if python -c "import deepspeed" 2>/dev/null; then
    echo "  Found deepspeed, uninstalling to avoid CLI import issues..."
    pip uninstall deepspeed -y
else
    echo "  deepspeed not installed"
fi

if ! protenix --help > /dev/null 2>&1; then
    echo "  ERROR: protenix CLI failed to start."
    exit 1
fi

if protenix predict --help > /dev/null 2>&1; then
    CLI_CMD="predict"
    FLAG_INPUT="--input"
    FLAG_OUTDIR="--out_dir"
    FLAG_MODEL="--model_name"
    FLAG_MSA="--use_msa"
    FLAG_SAMPLE="--sample"
    FLAG_DEFAULT_PARAMS="--use_default_params"
    echo "  CLI format: new (protenix predict --input ...)"
else
    CLI_CMD="pred"
    FLAG_INPUT="-i"
    FLAG_OUTDIR="-o"
    FLAG_MODEL="-n"
    FLAG_MSA=""
    FLAG_SAMPLE="-e"
    FLAG_DEFAULT_PARAMS=""
    echo "  CLI format: old (protenix pred -i ...)"
fi
echo "  protenix CLI is ready"

echo ""
echo "[Step 3/4] Check target JSON file..."

TARGET_JSON_PATH="${JSON_DIR}/${TARGET_JSON_NAME}.json"
if [ ! -d "${JSON_DIR}" ]; then
    echo "  ERROR: JSON directory not found: ${JSON_DIR}"
    exit 1
fi
if [ ! -f "${TARGET_JSON_PATH}" ]; then
    echo "  ERROR: target JSON file not found: ${TARGET_JSON_PATH}"
    exit 1
fi
echo "  Found target file: ${TARGET_JSON_PATH}"

echo ""
echo "[Step 4/4] Run Protenix inference for ${TARGET_JSON_NAME}.json..."
mkdir -p "${OUTPUT_BASE}"

OUT_DIR="${OUTPUT_BASE}/${TARGET_JSON_NAME}"
CMD="protenix ${CLI_CMD} ${FLAG_INPUT} ${TARGET_JSON_PATH} ${FLAG_OUTDIR} ${OUT_DIR} ${FLAG_MODEL} ${MODEL_NAME}"

if [ -n "${FLAG_MSA}" ]; then
    CMD="${CMD} ${FLAG_MSA} ${USE_MSA}"
fi
if [ -n "${FLAG_DEFAULT_PARAMS}" ]; then
    CMD="${CMD} ${FLAG_DEFAULT_PARAMS} true"
fi
if [ -n "${SAMPLE_NUM}" ]; then
    CMD="${CMD} ${FLAG_SAMPLE} ${SAMPLE_NUM}"
fi

echo "  Command: ${CMD}"

SECONDS=0
if eval "${CMD}"; then
    ELAPSED=${SECONDS}
    echo "  OK: ${TARGET_JSON_NAME} finished in $((ELAPSED / 60))m $((ELAPSED % 60))s"
else
    echo "  FAIL: ${TARGET_JSON_NAME}"
    exit 1
fi

echo ""
echo "============================================"
echo " Finished ${TARGET_JSON_NAME}.json"
echo " Run ./output_submit.sh after all inference outputs are ready"
echo "============================================"
