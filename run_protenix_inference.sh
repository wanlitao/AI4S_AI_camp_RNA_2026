#!/bin/bash

set -e

MODEL_NAME="protenix_base_default_v0.5.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JSON_DIR="${SCRIPT_DIR}/competition_datas"
OUTPUT_BASE="${SCRIPT_DIR}/protenix_outputs"
USE_MSA=false
SAMPLE_NUM=""
SKIP_JSON_NAME="3"

echo "============================================"
echo " SAISfold Track A - Protenix inference"
echo " Model: ${MODEL_NAME}"
echo " MSA: ${USE_MSA}"
echo " Skip JSON: ${SKIP_JSON_NAME}.json"
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
    echo "  CLI format: new (protenix predict --input ...)"
else
    CLI_CMD="pred"
    FLAG_INPUT="-i"
    FLAG_OUTDIR="-o"
    FLAG_MODEL="-n"
    FLAG_MSA=""
    FLAG_SAMPLE="-e"
    echo "  CLI format: old (protenix pred -i ...)"
fi
echo "  protenix CLI is ready"

echo ""
echo "[Step 3/4] Check input JSON files..."

if [ ! -d "${JSON_DIR}" ]; then
    echo "  ERROR: JSON directory not found: ${JSON_DIR}"
    exit 1
fi

JSON_COUNT=$(find "${JSON_DIR}" -maxdepth 1 -name "*.json" -type f | wc -l)
if [ "${JSON_COUNT}" -eq 0 ]; then
    echo "  ERROR: no .json files found in ${JSON_DIR}"
    exit 1
fi

RUN_COUNT=$(find "${JSON_DIR}" -maxdepth 1 -name "*.json" -type f ! -name "${SKIP_JSON_NAME}.json" | wc -l)
if [ "${RUN_COUNT}" -eq 0 ]; then
    echo "  ERROR: no JSON files left to run after excluding ${SKIP_JSON_NAME}.json"
    exit 1
fi

echo "  Found ${JSON_COUNT} JSON files in total"
echo "  Will run ${RUN_COUNT} JSON files in this script"
for f in "${JSON_DIR}"/*.json; do
    [ ! -f "${f}" ] && continue
    if [ "$(basename "${f}" .json)" = "${SKIP_JSON_NAME}" ]; then
        echo "    - $(basename "${f}") [skip]"
    else
        echo "    - $(basename "${f}")"
    fi
done

echo ""
echo "[Step 4/4] Run Protenix inference..."
mkdir -p "${OUTPUT_BASE}"

SUCCESS_COUNT=0
FAIL_COUNT=0

for json_file in "${JSON_DIR}"/*.json; do
    [ ! -f "${json_file}" ] && continue

    basename_noext=$(basename "${json_file}" .json)
    if [ "${basename_noext}" = "${SKIP_JSON_NAME}" ]; then
        continue
    fi

    OUT_DIR="${OUTPUT_BASE}/${basename_noext}"
    CMD="protenix ${CLI_CMD} ${FLAG_INPUT} ${json_file} ${FLAG_OUTDIR} ${OUT_DIR} ${FLAG_MODEL} ${MODEL_NAME}"

    if [ -n "${FLAG_MSA}" ]; then
        CMD="${CMD} ${FLAG_MSA} ${USE_MSA}"
    fi
    if [ -n "${SAMPLE_NUM}" ]; then
        CMD="${CMD} ${FLAG_SAMPLE} ${SAMPLE_NUM}"
    fi

    echo ""
    echo "  ----------------------------------------"
    echo "  Inference: ${basename_noext}.json"
    echo "  Output: ${OUT_DIR}"
    echo "  Command: ${CMD}"
    echo "  ----------------------------------------"

    SECONDS=0
    if eval "${CMD}"; then
        ELAPSED=${SECONDS}
        echo "  OK: ${basename_noext} finished in $((ELAPSED / 60))m $((ELAPSED % 60))s"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "  FAIL: ${basename_noext}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
echo "============================================"
echo " Finished. Success: ${SUCCESS_COUNT}, Fail: ${FAIL_COUNT}"
echo " 3.json was skipped here."
echo " Run ./run_protenix_inference_large.sh for 3.json"
echo " Run ./output_submit.sh after all inference outputs are ready"
echo "============================================"
