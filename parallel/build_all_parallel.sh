#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

REPOS=(
  "spriced-platform"
  "nrp-cummins-outbound"
  "spriced-backend"
  "spriced-ui"
  "spriced-client-cummins-data-ingestion"
  "Stocking-Segmentation-Enhancement"
  "spriced-client-cummins-parts-pricing"
)

BUILD_SCRIPTS=(
  "./build_spriced_platform.sh"
  "./build_nrp_cummins_outbound.sh"
  "./build_spriced_backend.sh"
  "./build_spriced_ui.sh"
  "./build_spriced_client_cummins_data_ingestion.sh"
  "./build_stocking_segmentation_enhancement.sh"
  "./build_spriced_client_cummins_parts_pricing.sh"
)

echo "📦 Available Repositories:"
for i in "${!REPOS[@]}"; do
  printf "  %d) %s\n" "$((i+1))" "${REPOS[$i]}"
done
echo "  0) ALL"

read -rp $'\n📌 Enter repo numbers to build (space-separated or 0 for all): ' -a SELECTED

# Handle '0' or 'all' → select all repos
if [[ "${SELECTED[0]}" == "0" || "${SELECTED[0],,}" == "all" ]]; then
  SELECTED=($(seq 1 ${#REPOS[@]}))
fi

COMMANDS=()
BUILD_LOG_DIR="$HOME/automationlogs"
mkdir -p "$BUILD_LOG_DIR"

for idx in "${SELECTED[@]}"; do
  if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#REPOS[@]} )); then
    echo "⚠️ Invalid selection: $idx. Skipping..."
    continue
  fi

  i=$((idx - 1))
  REPO="${REPOS[$i]}"
  SCRIPT="${BUILD_SCRIPTS[$i]}"

  read -rp "🌿 Enter branch for ${REPO}: " BRANCH

  LOG_FILE="$BUILD_LOG_DIR/${REPO}_$(date +%Y%m%d_%H%M%S).log"

  CMD="bash -c '${SCRIPT} \"${BRANCH}\" &>> \"${LOG_FILE}\" && echo \"[✔️ DONE] ${REPO}\" || echo \"[❌ FAIL] ${REPO} - see log: ${LOG_FILE}\"'"
  COMMANDS+=("$CMD")
done

# 🧠 Detect CPU cores (leave 1 free if possible)
TOTAL_CPUS=$(nproc)
CPU_CORES=$(( TOTAL_CPUS > 1 ? TOTAL_CPUS - 1 : 1 ))

echo -e "\n🚀 Running ${#COMMANDS[@]} builds in parallel using ${CPU_CORES}/${TOTAL_CPUS} CPU cores...\n"
printf "%s\n" "${COMMANDS[@]}" | parallel -j "$CPU_CORES" --tag --lb --bar

echo -e "\n✅ All builds attempted. Check logs in: $BUILD_LOG_DIR"
