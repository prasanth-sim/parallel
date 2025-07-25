#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

CLONE_DIR="$HOME/projects/repos"
DEPLOY_DIR="$HOME/projects/builds"
LOG_DIR="$HOME/automationlogs"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")
TRACKER_FILE="$LOG_DIR/build-tracker-$DATE_TAG.csv"

mkdir -p "$CLONE_DIR" "$DEPLOY_DIR" "$LOG_DIR"

declare -A REPO_URLS=(
  ["spriced-ui"]="https://github.com/simaiserver/spriced-ui.git"
  ["spriced-backend"]="https://github.com/simaiserver/spriced-backend.git"
  ["spriced-client-cummins-parts-pricing"]="https://github.com/simaiserver/spriced-client-cummins-parts-pricing.git"
  ["spriced-client-cummins-data-ingestion"]="https://github.com/simaiserver/spriced-client-cummins-data-ingestion.git"
  ["Stocking-Segmentation-Enhancement"]="https://github.com/simaiserver/Stocking-Segmentation-Enhancement.git"
  ["spriced-platform"]="https://github.com/simaiserver/https://github.com/simaiserver/spriced-platform.git"
  ["nrp-cummins-outbound"]="https://github.com/simaiserver/nrp-cummins-outbound.git"
)

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

# Select all if '0' or 'all'
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
  REPO_DIR="$CLONE_DIR/$REPO"

  # Clone or update the repo
  if [[ -d "$REPO_DIR/.git" ]]; then
    echo "📁 Repo '$REPO' already cloned at $REPO_DIR. Pulling latest changes..."
    git -C "$REPO_DIR" pull
  else
    echo "🚀 Cloning '$REPO' into $REPO_DIR..."
    git clone "${REPO_URLS[$REPO]}" "$REPO_DIR"
  fi

  if [[ "$REPO" == "spriced-ui" ]]; then
    # Special case for spriced-ui: also clone spriced-pipeline
    PIPELINE_DIR="$HOME/projects/spriced-pipeline"
    PIPELINE_URL="https://github.com/simaiserver/spriced-pipeline.git"
    mkdir -p "$(dirname "$PIPELINE_DIR")"

    if [[ -d "$PIPELINE_DIR/.git" ]]; then
      echo "📁 Repo 'spriced-pipeline' already cloned at $PIPELINE_DIR. Pulling latest changes..."
      git -C "$PIPELINE_DIR" pull
    else
      echo "🚀 Cloning 'spriced-pipeline' repo to $PIPELINE_DIR..."
      git clone "$PIPELINE_URL" "$PIPELINE_DIR"
    fi

    echo -e "\n🌐 Choose environment for spriced-ui:"
    echo "  1) dev"
    echo "  2) qa"
    echo "  3) test"
    read -rp "📌 Enter environment number (1/2/3): " ENV_NUM
    case "$ENV_NUM" in
      1) ENV="dev" ;;
      2) ENV="qa" ;;
      3) ENV="test" ;;
      *) echo "❌ Invalid environment selected"; exit 1 ;;
    esac

    read -rp $'\n🌿 Enter branch name for spriced-ui: ' BRANCH
    LOG_FILE="$BUILD_LOG_DIR/${REPO}$(date +%Y%m%d%H%M%S).log"
    CMD="bash -c '${SCRIPT} \"${ENV}\" \"${BRANCH}\" &>> \"${LOG_FILE}\" && echo \"[✔️ DONE] ${REPO}\" || echo \"[❌ FAIL] ${REPO} - see log: ${LOG_FILE}\"'"
  else
    read -rp "🌿 Enter branch for ${REPO}: " BRANCH
    LOG_FILE="$BUILD_LOG_DIR/${REPO}$(date +%Y%m%d%H%M%S).log"
    CMD="bash -c '${SCRIPT} \"${BRANCH}\" &>> \"${LOG_FILE}\" && echo \"[✔️ DONE] ${REPO}\" || echo \"[❌ FAIL] ${REPO} - see log: ${LOG_FILE}\"'"
  fi

  COMMANDS+=("$CMD")
done

TOTAL_CPUS=$(nproc)
NUM_BUILDS=${#COMMANDS[@]}
CPU_CORES=$(( NUM_BUILDS < TOTAL_CPUS ? NUM_BUILDS : TOTAL_CPUS ))
CPU_CORES=$(( CPU_CORES > 0 ? CPU_CORES : 1 ))

echo -e "\n🚀 Running ${NUM_BUILDS} builds in parallel using ${CPU_CORES}/${TOTAL_CPUS} CPU cores...\n"
printf "%s\n" "${COMMANDS[@]}" | parallel -j "$CPU_CORES" --tag --lb --bar

echo -e "\n✅ All builds attempted. Check logs in: $BUILD_LOG_DIR"
