#!/bin/bash
# =============================================================================
# 2-download-models.sh — Download the GB10 Western-only model set to the SSD
#
# Target hardware : 1-2x Dell GB10 (128GB unified, DGX OS), vLLM serving
# Run on          : vanilla macOS (needs Xcode Command Line Tools for python3;
#                   macOS will prompt to install them automatically if missing)
# Usage           : bash 2-download-models.sh
#
# Downloads are RESUMABLE — if interrupted, just re-run the script.
# =============================================================================
set -uo pipefail

SSD_DEFAULT="/Volumes/GB10MODELS"
VENV_DIR="$HOME/.gb10-hf-venv"

# -----------------------------------------------------------------------------
# MODEL MANIFEST  (verified on Hugging Face, 2026-08-26)
# Format:  "hf_repo_id | destination_subdir | approx_size"
# -----------------------------------------------------------------------------
MODELS=(
  # --- Tier 1: core -----------------------------------------------------------
  "openai/gpt-oss-120b                                | gpt-oss-120b                  | 63G"
  "nvidia/NVIDIA-Nemotron-3-Super-120B-A12B-NVFP4     | nemotron-3-super-120b-nvfp4   | 65G"
  "mistralai/Devstral-Small-2-24B-Instruct-2512       | devstral-small-2-24b-fp8      | 26G"
  # --- Tier 2: Gemma stack (router / vision / summaries — not code writing) ---
  "RedHatAI/gemma-4-26B-A4B-it-FP8-Dynamic            | gemma-4-26b-a4b-it-fp8        | 27G"
  "google/gemma-4-26B-A4B-it-assistant                | gemma-4-26b-mtp-drafter       | 1G"
  "bg-digitalservices/Gemma-4-26B-A4B-it-NVFP4        | gemma-4-26b-a4b-it-nvfp4      | 17G"
  "coolthor/Gemma-4-E4B-it-NVFP4A16                   | gemma-4-e4b-it-nvfp4a16       | 10G"
)

# --- Tier 3 (optional): uncomment to include ---------------------------------
# Devstral 2 123B GGUF (llama.cpp only, batch jobs only).
# NOTE license: prohibits companies >$20M MONTHLY revenue without a commercial
# license — confirm TRG Screen's status before deploying.
# OPTIONAL_GGUF_REPO="unsloth/Devstral-2-123B-Instruct-2512-GGUF"
# OPTIONAL_GGUF_INCLUDE="*UD-Q4_K_XL*"

TOTAL_NEEDED_GB=210   # Tier 1 + Tier 2 with headroom

# =============================================================================
# STEP 0 — Locate the SSD
# =============================================================================
echo "============================================================"
echo " GB10 Model Downloader — Western-only manifest (7 models)"
echo "============================================================"
echo
if [[ -d "$SSD_DEFAULT" ]]; then
  SSD="$SSD_DEFAULT"
else
  echo "Default SSD not found at $SSD_DEFAULT."
  echo "Currently mounted volumes:"
  ls /Volumes/
  read -r -p "Enter the SSD volume path (e.g. /Volumes/MyDrive): " SSD
  [[ -d "$SSD" ]] || { echo "ERROR: $SSD does not exist. Run 1-format-ssd.sh first."; exit 1; }
fi

DEST_ROOT="$SSD/models"
mkdir -p "$DEST_ROOT"
echo "Downloading into: $DEST_ROOT"

# Free-space check (exFAT-safe)
FREE_GB=$(df -g "$SSD" | awk 'NR==2 {print $4}')
echo "Free space on SSD: ${FREE_GB} GB (need ~${TOTAL_NEEDED_GB} GB)"
if (( FREE_GB < TOTAL_NEEDED_GB )); then
  echo "WARNING: less than ${TOTAL_NEEDED_GB} GB free."
  read -r -p "Continue anyway? (yes/no): " CONT
  [[ "$CONT" == "yes" ]] || exit 1
fi

# =============================================================================
# STEP 1 — Python env + Hugging Face CLI
# =============================================================================
echo
echo "--- Setting up Hugging Face CLI ---"
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found. macOS should prompt you to install Command Line Tools."
  echo "Run 'xcode-select --install', then re-run this script."
  exit 1
fi

if [[ ! -d "$VENV_DIR" ]]; then
  python3 -m venv "$VENV_DIR"
fi
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet --upgrade "huggingface_hub[cli]" hf_transfer

# Faster parallel downloads
export HF_HUB_ENABLE_HF_TRANSFER=1

# Prefer new 'hf' CLI, fall back to legacy name
if command -v hf >/dev/null 2>&1; then
  HF_DL() { hf download "$@"; }
else
  HF_DL() { huggingface-cli download "$@"; }
fi

# =============================================================================
# STEP 2 — Hugging Face auth (required for the gated Google repo)
# =============================================================================
echo
echo "--- Hugging Face authentication ---"
echo "The Gemma drafter repo (google/gemma-4-26B-A4B-it-assistant) is GATED:"
echo "  1. Create/log into a Hugging Face account"
echo "  2. Visit the repo page in a browser and click 'Agree' on the Gemma license"
echo "  3. Create a read token at https://huggingface.co/settings/tokens"
echo
if [[ -z "${HF_TOKEN:-}" ]]; then
  read -r -s -p "Paste your HF read token (or press Enter to skip gated repos): " HF_TOKEN_IN
  echo
  if [[ -n "$HF_TOKEN_IN" ]]; then
    export HF_TOKEN="$HF_TOKEN_IN"
  else
    echo "No token — gated repos will be SKIPPED (you can re-run later)."
  fi
fi

# =============================================================================
# STEP 3 — Download loop (resumable)
# =============================================================================
echo
echo "--- Downloading ${#MODELS[@]} models ---"
FAILED=()
i=0
for entry in "${MODELS[@]}"; do
  i=$((i+1))
  REPO=$(echo "$entry"   | cut -d'|' -f1 | xargs)
  SUBDIR=$(echo "$entry" | cut -d'|' -f2 | xargs)
  SIZE=$(echo "$entry"   | cut -d'|' -f3 | xargs)
  DEST="$DEST_ROOT/$SUBDIR"

  echo
  echo "[$i/${#MODELS[@]}] $REPO  (~$SIZE)"
  echo "        -> $DEST"

  if [[ "$REPO" == google/* && -z "${HF_TOKEN:-}" ]]; then
    echo "        SKIPPED (gated repo, no HF token)"
    FAILED+=("$REPO (skipped: gated, no token)")
    continue
  fi

  if HF_DL "$REPO" --local-dir "$DEST"; then
    echo "        DONE"
  else
    echo "        FAILED — will list at the end; re-run script to resume."
    FAILED+=("$REPO")
  fi
done

# Optional Tier 3 GGUF (only if variables uncommented above)
if [[ -n "${OPTIONAL_GGUF_REPO:-}" ]]; then
  echo
  echo "[optional] $OPTIONAL_GGUF_REPO ($OPTIONAL_GGUF_INCLUDE)"
  HF_DL "$OPTIONAL_GGUF_REPO" --include "$OPTIONAL_GGUF_INCLUDE" \
    --local-dir "$DEST_ROOT/devstral-2-123b-gguf" || FAILED+=("$OPTIONAL_GGUF_REPO")
fi

# =============================================================================
# STEP 4 — Summary + walk-through for the GB10 side
# =============================================================================
echo
echo "============================================================"
echo " DOWNLOAD SUMMARY"
echo "============================================================"
du -sh "$DEST_ROOT"/* 2>/dev/null || true
if (( ${#FAILED[@]} > 0 )); then
  echo
  echo "Incomplete/skipped (re-run this script to resume):"
  printf '  - %s\n' "${FAILED[@]}"
fi

cat <<'EOF'

============================================================
 NEXT STEPS — moving models onto the GB10s
============================================================
1. EJECT SAFELY on the Mac (exFAT corrupts if yanked):
     diskutil eject /Volumes/GB10MODELS

2. Plug the SSD into a GB10. DGX OS should auto-mount it under
   /media/$USER/GB10MODELS. If it doesn't:
     lsblk                                   # find e.g. /dev/sda1
     sudo mkdir -p /mnt/ssd
     sudo mount -t exfat /dev/sda1 /mnt/ssd

3. COPY to internal NVMe — do NOT serve models from the USB drive:
     sudo mkdir -p /opt/models && sudo chown $USER /opt/models
     rsync -ah --info=progress2 /media/$USER/GB10MODELS/models/ /opt/models/

   Suggested split if using both boxes independently:
     Node A (coding):     gpt-oss-120b, nemotron-3-super-120b-nvfp4,
                          devstral-small-2-24b-fp8
     Node B (light-lift): gemma-4-26b-a4b-it-fp8, gemma-4-26b-mtp-drafter,
                          gemma-4-e4b-it-nvfp4a16, gemma-4-26b-a4b-it-nvfp4

4. Verify integrity after copy (compare file counts + sizes):
     du -sh /opt/models/*

5. Serve with vLLM pointing at local paths, e.g.:
     vllm serve /opt/models/gpt-oss-120b \
       --served-model-name gpt-oss-120b \
       --max-model-len 131072 --enable-prefix-caching
EOF

echo "Done."
