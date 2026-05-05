#!/bin/bash
# ============================================================
# SAISfold 路线A：Protenix 推理一键脚本
# 用法：bash run_protenix_inference.sh
# 环境：Linux + NVIDIA GPU (>=16GB显存) + CUDA
# 已验证：Protenix 0.5.5 + RTX 4090 D (24GB)
# ============================================================

set -e

# ===================== 配置区 =====================
# 模型名称（必须用 v0.5.0 后缀！v1.0.0 会报 not supported）
MODEL_NAME="protenix_base_default_v0.5.0"
# 赛题JSON所在目录（相对于脚本位置）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JSON_DIR="${SCRIPT_DIR}/competition_datas"
# 输出目录
OUTPUT_BASE="${SCRIPT_DIR}/protenix_outputs"
# 是否使用MSA（必须关闭，MSA服务器不可达）
USE_MSA=false
# 采样数（赛题2较大，建议1；其余可用默认5）
# 留空则使用Protenix默认值(5)
SAMPLE_NUM=""
# ===================== 配置区结束 =====================

echo "============================================"
echo " SAISfold 路线A - Protenix 推理一键脚本"
echo " 模型: ${MODEL_NAME}"
echo " MSA: ${USE_MSA}"
echo "============================================"

# ---------- Step 1: 环境检查与准备 ----------
echo ""
echo "[Step 1/5] 环境检查..."

# 检查GPU
if command -v nvidia-smi &> /dev/null; then
    GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo "unknown")
    echo "  GPU: ${GPU_INFO}"
else
    echo "  ❌ 未检测到 nvidia-smi，必须有 NVIDIA GPU 才能运行！"
    exit 1
fi

# 检查Python
if ! command -v python &> /dev/null; then
    echo "  ❌ 未找到 python，请先安装 Python 3.10+"
    exit 1
fi
PY_VER=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "  Python: ${PY_VER}"

# ---------- Step 2: 安装 Protenix ----------
echo ""
echo "[Step 2/5] 安装 Protenix..."

if python -c "import protenix" 2>/dev/null; then
    PROT_VER=$(python -c "import importlib.metadata; print(importlib.metadata.version('protenix'))" 2>/dev/null || echo "unknown")
    echo "  Protenix 已安装: v${PROT_VER}"
else
    echo "  pip install protenix (首次安装需要几分钟)..."
    pip install protenix
fi

# 卸载 deepspeed（否则 CLI 启动报 ImportError）
if python -c "import deepspeed" 2>/dev/null; then
    echo "  检测到 deepspeed，卸载中（推理不需要，会导致 ImportError）..."
    pip uninstall deepspeed -y
else
    echo "  deepspeed 未安装，无需处理"
fi

# 验证 CLI 可用并自动检测命令格式（不同版本差异很大）
if ! protenix --help &> /dev/null; then
    echo "  ❌ protenix CLI 启动失败！请检查上方错误信息"
    exit 1
fi

# 自动检测 CLI 命令格式
# 新版(如0.5.5)：protenix predict --input --out_dir --model_name --use_msa
# 旧版(如0.3.x)：protenix pred -i -o -n
if protenix predict --help &> /dev/null 2>&1; then
    CLI_CMD="predict"
    FLAG_INPUT="--input"
    FLAG_OUTDIR="--out_dir"
    FLAG_MODEL="--model_name"
    FLAG_MSA="--use_msa"
    FLAG_SAMPLE="--sample"
    echo "  CLI 格式: 新版 (protenix predict --input ...)"
else
    CLI_CMD="pred"
    FLAG_INPUT="-i"
    FLAG_OUTDIR="-o"
    FLAG_MODEL="-n"
    FLAG_MSA=""
    FLAG_SAMPLE="-s"
    echo "  CLI 格式: 旧版 (protenix pred -i ...)"
fi
echo "  protenix CLI 验证通过 ✓"

# ---------- Step 3: 检查赛题文件 ----------
echo ""
echo "[Step 3/5] 检查赛题文件..."

if [ ! -d "${JSON_DIR}" ]; then
    echo "  ❌ 赛题目录不存在: ${JSON_DIR}"
    exit 1
fi

JSON_COUNT=$(ls "${JSON_DIR}"/*.json 2>/dev/null | wc -l)
if [ "${JSON_COUNT}" -eq 0 ]; then
    echo "  ❌ 赛题目录中未找到 .json 文件: ${JSON_DIR}"
    exit 1
fi
echo "  找到 ${JSON_COUNT} 个赛题文件:"
for f in "${JSON_DIR}"/*.json; do
    echo "    - $(basename "$f")"
done

# ---------- Step 4: 逐个运行推理（串行，避免OOM） ----------
echo ""
echo "[Step 4/5] 运行 Protenix 推理（串行执行）..."
mkdir -p "${OUTPUT_BASE}"

SUCCESS_COUNT=0
FAIL_COUNT=0

for json_file in "${JSON_DIR}"/*.json; do
    [ ! -f "$json_file" ] && continue

    basename_noext=$(basename "$json_file" .json)
    OUT_DIR="${OUTPUT_BASE}/${basename_noext}"

    echo ""
    echo "  ──────────────────────────────────"
    echo "  推理: ${basename_noext}.json"
    echo "  输出: ${OUT_DIR}"
    echo "  ──────────────────────────────────"

    # 构建推理命令（自动适配新旧版本CLI）
    CMD="protenix ${CLI_CMD} ${FLAG_INPUT} ${json_file} ${FLAG_OUTDIR} ${OUT_DIR} ${FLAG_MODEL} ${MODEL_NAME}"
    # MSA 标志（旧版无此参数）
    if [ -n "${FLAG_MSA}" ]; then
        CMD="${CMD} ${FLAG_MSA} ${USE_MSA}"
    fi
    # 如果指定了采样数则加上
    if [ -n "${SAMPLE_NUM}" ]; then
        CMD="${CMD} ${FLAG_SAMPLE} ${SAMPLE_NUM}"
    fi

    echo "  命令: ${CMD}"

    SECONDS=0
    if eval "${CMD}"; then
        ELAPSED=${SECONDS}
        echo "  ✓ ${basename_noext} 推理完成！耗时: $((ELAPSED/60))分$((ELAPSED%60))秒"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "  ✗ ${basename_noext} 推理失败！"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

# ---------- Step 5: 收集输出 CIF 文件，打包提交 ----------
echo ""
echo "[Step 5/5] 收集输出文件，打包提交..."

SUBMIT_DIR="${OUTPUT_BASE}/submit"
mkdir -p "${SUBMIT_DIR}"

for json_file in "${JSON_DIR}"/*.json; do
    [ ! -f "$json_file" ] && continue
    basename_noext=$(basename "$json_file" .json)

    # Protenix 输出的 CIF 文件路径模式：
    # {out_dir}/{name}/seed_101/predictions/{name}_seed_101_sample_0.cif
    # 取 sample_0（最佳采样）作为提交结果
    found_cif=$(find "${OUTPUT_BASE}/${basename_noext}" -name "*_sample_0.cif" -type f 2>/dev/null | head -1)

    if [ -n "$found_cif" ]; then
        cp "${found_cif}" "${SUBMIT_DIR}/${basename_noext}_pred.cif"
        FILE_SIZE=$(du -h "${found_cif}" | cut -f1)
        echo "  ✓ ${basename_noext}_pred.cif (${FILE_SIZE})"
    else
        echo "  ✗ 未找到 ${basename_noext} 的 CIF 输出！"
        echo "    输出目录内容:"
        find "${OUTPUT_BASE}/${basename_noext}" -type f 2>/dev/null | head -10 | sed 's/^/      /'
    fi
done

# 打包成 output.zip
ZIP_PATH="${OUTPUT_BASE}/output.zip"
if ls "${SUBMIT_DIR}"/*.cif &> /dev/null; then
    cd "${SUBMIT_DIR}"
    zip -j "${ZIP_PATH}" *.cif
    cd "${SCRIPT_DIR}"

    echo ""
    echo "============================================"
    echo " 完成！成功: ${SUCCESS_COUNT}, 失败: ${FAIL_COUNT}"
    echo " 提交文件: ${ZIP_PATH}"
    echo " 内容:"
    unzip -l "${ZIP_PATH}"
    echo "============================================"
else
    echo ""
    echo "❌ 没有成功生成任何 CIF 文件，无法打包！"
    exit 1
fi
