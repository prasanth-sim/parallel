#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

CLONE_DIR="$HOME/projects/repos"
DEPLOY_DIR="$HOME/projects/builds"
LOG_DIR="$HOME/automationlogs"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")
TRACKER_FILE="$LOG_DIR/build-tracker-${DATE_TAG}.csv"

mkdir -p "$CLONE_DIR" "$DEPLOY_DIR" "$LOG_DIR"

declare -A REPO_URLS=(
  ["spriced-ui"]="https://github.com/simaiserver/spriced-ui.git"
  ["spriced-backend"]="https://github.com/simaiserver/spriced-backend.git"
  ["spriced-client-cummins-parts-pricing"]="https://github.com/simaiserver/spriced-client-cummins-parts-pricing.git"
  ["spriced-client-cummins-data-ingestion"]="https://github.com/simaiserver/spriced-client-cummins-data-ingestion.git"
  ["Stocking-Segmentation-Enhancement"]="https://github.com/simaiserver/Stocking-Segmentation-Enhancement.git"
  ["spriced-platform"]="https://github.com/simaiserver/spriced-platform.git"
  ["nrp-cummins-outbound"]="https://github.com/simaiserver/nrp-cummins-outbound.git"
)

declare -A DEFAULT_BRANCHES=(
  ["spriced-ui"]="main"
  ["spriced-backend"]="main"
  ["spriced-client-cummins-parts-pricing"]="main"
  ["spriced-client-cummins-data-ingestion"]="main"
  ["Stocking-Segmentation-Enhancement"]="main"
  ["spriced-platform"]="main"
  ["nrp-cummins-outbound"]="main"
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BUILD_SCRIPTS=(
  "$SCRIPT_DIR/build_spriced_platform.sh"
  "$SCRIPT_DIR/build_nrp_cummins_outbound.sh"
  "$SCRIPT_DIR/build_spriced_backend.sh"
  "$SCRIPT_DIR/build_spriced_ui.sh"
  "$SCRIPT_DIR/build_spriced_client_cummins_data_ingestion.sh"
  "$SCRIPT_DIR/build_stocking_segmentation_enhancement.sh"
  "$SCRIPT_DIR/build_spriced_client_cummins_parts_pricing.sh"
)

echo "📦 Available Repositories:"
for i in "${!REPOS[@]}"; do
  printf "  %d) %s\n" "$((i+1))" "${REPOS[$i]}"
done
echo "  0) ALL"

read -rp $'\n📌 Enter repo numbers to build (space-separated or 0 for all): ' -a SELECTED

if [[ "${SELECTED[0]}" == "0" || "${SELECTED[0],,}" == "all" ]]; then
  SELECTED=($(seq 1 ${#REPOS[@]}))
fi

COMMANDS=()
BUILD_LOG_DIR="$LOG_DIR"
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
  DEFAULT_BRANCH="${DEFAULT_BRANCHES[$REPO]}"

  if [[ -d "$REPO_DIR/.git" ]]; then
    echo "📁 Repo '$REPO' already cloned. Pulling latest..."
    git -C "$REPO_DIR" pull --quiet
  else
    echo "🚀 Cloning '$REPO'..."
    git clone --quiet "${REPO_URLS[$REPO]}" "$REPO_DIR"
  fi

  cd "$REPO_DIR"

  if [[ "$REPO" == "spriced-ui" ]]; then
    PIPELINE_DIR="$HOME/projects/spriced-pipeline"
    PIPELINE_URL="https://github.com/simaiserver/spriced-pipeline.git"
    if [[ -d "$PIPELINE_DIR/.git" ]]; then
      git -C "$PIPELINE_DIR" pull --quiet
    else
      git clone --quiet "$PIPELINE_URL" "$PIPELINE_DIR"
    fi

    echo -e "\n🌐 Choose environment for spriced-ui:"
    echo "  1) dev"
    echo "  2) qa"
    echo "  3) test"
    read -rp "📌 Enter environment number: " ENV_NUM
    case "$ENV_NUM" in
      1) ENV="dev" ;;
      2) ENV="qa" ;;
      3) ENV="test" ;;
      *) echo "❌ Invalid environment"; exit 1 ;;
    esac

    read -rp "🌿 Enter branch name [default: $DEFAULT_BRANCH]: " BRANCH
    BRANCH="${BRANCH:-$DEFAULT_BRANCH}"

    if [[ -z "$BRANCH" ]]; then
      echo "❌ No branch entered for $REPO. Skipping..."
      continue
    fi

    git fetch --quiet && git checkout "$BRANCH" &>/dev/null || {
      echo "❌ Branch '$BRANCH' not found. Skipping..."
      continue
    }

    LOG_FILE="$BUILD_LOG_DIR/${REPO}_$(date +%Y%m%d%H%M%S).log"
    CMD="bash -c '${SCRIPT} \"${ENV}\" \"${BRANCH}\" &>> \"${LOG_FILE}\" && echo \"[✔️ DONE] ${REPO} - see log: ${LOG_FILE}\" && echo \"${REPO},SUCCESS,${LOG_FILE}\" >> \"${TRACKER_FILE}\" || echo \"[❌ FAIL] ${REPO} - see log: ${LOG_FILE}\" && echo \"${REPO},FAIL,${LOG_FILE}\" >> \"${TRACKER_FILE}\"'"
  else
    read -rp "🌿 Enter branch for ${REPO} [default: $DEFAULT_BRANCH]: " BRANCH
    BRANCH="${BRANCH:-$DEFAULT_BRANCH}"

    if [[ -z "$BRANCH" ]]; then
      echo "❌ No branch entered for $REPO. Skipping..."
      continue
    fi

    git fetch --quiet && git checkout "$BRANCH" &>/dev/null || {
      echo "❌ Branch '$BRANCH' not found. Skipping..."
      continue
    }

    LOG_FILE="$BUILD_LOG_DIR/${REPO}_$(date +%Y%m%d%H%M%S).log"
    CMD="bash -c '${SCRIPT} \"${BRANCH}\" &>> \"${LOG_FILE}\" && echo \"[✔️ DONE] ${REPO} - see log: ${LOG_FILE}\" && echo \"${REPO},SUCCESS,${LOG_FILE}\" >> \"${TRACKER_FILE}\" || echo \"[❌ FAIL] ${REPO} - see log: ${LOG_FILE}\" && echo \"${REPO},FAIL,${LOG_FILE}\" >> \"${TRACKER_FILE}\"'"
  fi

  COMMANDS+=("$CMD")
done

# === Parallel Build Execution ===
TOTAL_CPUS=$(nproc)
NUM_BUILDS=${#COMMANDS[@]}
CPU_CORES=$(( NUM_BUILDS < TOTAL_CPUS ? NUM_BUILDS : TOTAL_CPUS ))
CPU_CORES=$(( CPU_CORES > 0 ? CPU_CORES : 1 ))

echo -e "\n🚀 Running ${NUM_BUILDS} builds in parallel using ${CPU_CORES}/${TOTAL_CPUS} CPU cores...\n"
printf "%s\n" "${COMMANDS[@]}" | parallel -j "$CPU_CORES" --lb --bar

# === Clean Build Summary ===
echo -e "\n================= 🧾 Build Summary ================="

if [[ -f "$TRACKER_FILE" ]]; then
  while IFS=',' read -r repo status logfile; do
    if [[ "$status" == "SUCCESS" ]]; then
      echo "[✅ SUCCESS] $repo - Log: $logfile"
    else
      echo "[❌ FAIL]    $repo - Log: $logfile"
    fi
  done < "$TRACKER_FILE"
else
  echo "⚠️ No tracker file found."
fi

echo "===================================================="
echo "📄 Build tracker written to: $TRACKER_FILE"
