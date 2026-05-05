#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JSON_DIR="${SCRIPT_DIR}/competition_datas"
OUTPUT_BASE="${SCRIPT_DIR}/protenix_outputs"
SUBMIT_DIR="${OUTPUT_BASE}/submit"
ZIP_PATH="${OUTPUT_BASE}/output.zip"

echo "============================================"
echo " SAISfold Track A - collect outputs"
echo " Output base: ${OUTPUT_BASE}"
echo " Submit dir: ${SUBMIT_DIR}"
echo "============================================"

echo ""
echo "[Step 1/1] Collect CIF files and build output.zip..."

if [ ! -d "${JSON_DIR}" ]; then
    echo "  ERROR: JSON directory not found: ${JSON_DIR}"
    exit 1
fi

mkdir -p "${SUBMIT_DIR}"
find "${SUBMIT_DIR}" -maxdepth 1 -name "*.cif" -type f -delete

FOUND_COUNT=0
MISS_COUNT=0

for json_file in "${JSON_DIR}"/*.json; do
    [ ! -f "${json_file}" ] && continue

    basename_noext=$(basename "${json_file}" .json)
    found_cif=$(find "${OUTPUT_BASE}/${basename_noext}" -name "*_sample_0.cif" -type f 2>/dev/null | head -1)

    if [ -n "${found_cif}" ]; then
        cp "${found_cif}" "${SUBMIT_DIR}/${basename_noext}_pred.cif"
        FILE_SIZE=$(du -h "${found_cif}" | cut -f1)
        echo "  OK: ${basename_noext}_pred.cif (${FILE_SIZE})"
        FOUND_COUNT=$((FOUND_COUNT + 1))
    else
        echo "  MISS: ${basename_noext}.json"
        find "${OUTPUT_BASE}/${basename_noext}" -type f 2>/dev/null | head -10 | sed 's/^/    /'
        MISS_COUNT=$((MISS_COUNT + 1))
    fi
done

if ! command -v zip > /dev/null 2>&1; then
    echo "  ERROR: zip command not found."
    exit 1
fi

if ls "${SUBMIT_DIR}"/*.cif > /dev/null 2>&1; then
    rm -f "${ZIP_PATH}"
    (
        cd "${SUBMIT_DIR}"
        zip -j "${ZIP_PATH}" *.cif
    )

    echo ""
    echo "============================================"
    echo " output.zip created: ${ZIP_PATH}"
    echo " CIF found: ${FOUND_COUNT}, missing: ${MISS_COUNT}"
    unzip -l "${ZIP_PATH}"
    echo "============================================"
else
    echo ""
    echo "ERROR: no CIF files were collected, output.zip was not created."
    exit 1
fi
