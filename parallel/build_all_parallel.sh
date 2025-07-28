#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# === Paths & Setup ===
CLONE_DIR="$HOME/projects/repos"
DEPLOY_DIR="$HOME/projects/builds"
LOG_DIR="$HOME/automationlogs"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")
TRACKER_FILE="$LOG_DIR/build-tracker-${DATE_TAG}.csv"

mkdir -p "$CLONE_DIR" "$DEPLOY_DIR" "$LOG_DIR"

# === Repo Configs ===
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

# === Select Repositories ===
echo -e "\n📦 Available Repositories:"
for i in "${!REPOS[@]}"; do
  printf "  %d) %s\n" "$((i+1))" "${REPOS[$i]}"
done
echo "  0) ALL"

read -rp $'\n📌 Enter repo numbers to build (space-separated or 0 for all): ' -a SELECTED
if [[ "${SELECTED[0]}" == "0" || "${SELECTED[0],,}" == "all" ]]; then
  SELECTED=($(seq 1 ${#REPOS[@]}))
fi

COMMANDS=()
mkdir -p "$LOG_DIR"

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

  echo -e "\n🚀 Checking '$REPO' repository..."

  if [[ -d "$REPO_DIR/.git" ]]; then
    echo "🔄 Updating existing repo at $REPO_DIR"
    cd "$REPO_DIR"

    git fetch origin --prune
    git reset --hard HEAD
    git clean -fd

    if git rev-parse --verify "origin/$DEFAULT_BRANCH" >/dev/null 2>&1; then
      git checkout -B "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH"
    else
      echo "❌ Remote branch origin/$DEFAULT_BRANCH not found. Skipping..."
      continue
    fi
  else
    echo "📥 Cloning new repo from ${REPO_URLS[$REPO]} into $REPO_DIR"
    [[ -d "$REPO_DIR" && ! -d "$REPO_DIR/.git" ]] && rm -rf "$REPO_DIR"
    git clone "${REPO_URLS[$REPO]}" "$REPO_DIR"
    cd "$REPO_DIR"
  fi

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

    BACKUP_DIR="/tmp/spriced_ui_backup_$DATE_TAG"
    mkdir -p "$BACKUP_DIR"
    find apps/ -type f -name ".env" -exec mv {} "$BACKUP_DIR" \; 2>/dev/null || true
    mv package-lock.json "$BACKUP_DIR/" 2>/dev/null || true

    git fetch origin
    if git rev-parse --verify origin/"$BRANCH" >/dev/null 2>&1; then
      git checkout -B "$BRANCH" origin/"$BRANCH"
    else
      echo "❌ Branch '$BRANCH' not found on origin. Skipping..."
      continue
    fi

    find "$BACKUP_DIR" -name ".env" -exec cp {} ./apps/ \;
    cp "$BACKUP_DIR/package-lock.json" ./ 2>/dev/null || true

    ENV_FILE_SOURCE="$PIPELINE_DIR/framework/frontend/nrp-$ENV/spriced-data/.env"
    ENV_FILE_DEST="$REPO_DIR/.env"
    if [[ -f "$ENV_FILE_SOURCE" ]]; then
      cp "$ENV_FILE_SOURCE" "$ENV_FILE_DEST"
      echo "📄 Copied .env from pipeline [$ENV] to spriced-ui"
    else
      echo "⚠️ .env file not found for environment [$ENV]. Skipping copy."
    fi

    LOG_FILE="$LOG_DIR/${REPO}_$(date +%Y%m%d%H%M%S).log"
    CMD="bash -c '${SCRIPT} \"${ENV}\" \"${BRANCH}\" &>> \"${LOG_FILE}\" && echo \"[✔️ DONE] ${REPO} - see log: ${LOG_FILE}\" && echo \"${REPO},SUCCESS,${LOG_FILE}\" >> \"${TRACKER_FILE}\" || echo \"[❌ FAIL] ${REPO} - see log: ${LOG_FILE}\" && echo \"${REPO},FAIL,${LOG_FILE}\" >> \"${TRACKER_FILE}\"'"
  else
    read -rp "🌿 Enter branch for ${REPO} [default: $DEFAULT_BRANCH]: " BRANCH
    BRANCH="${BRANCH:-$DEFAULT_BRANCH}"

    git fetch origin
    if git rev-parse --verify origin/"$BRANCH" >/dev/null 2>&1; then
      git checkout -B "$BRANCH" origin/"$BRANCH"
    else
      echo "❌ Branch '$BRANCH' not found on origin. Skipping..."
      continue
    fi

    LOG_FILE="$LOG_DIR/${REPO}_$(date +%Y%m%d%H%M%S).log"
    CMD="bash -c '${SCRIPT} \"${BRANCH}\" &>> \"${LOG_FILE}\" && echo \"[✔️ DONE] ${REPO} - see log: ${LOG_FILE}\" && echo \"${REPO},SUCCESS,${LOG_FILE}\" >> \"${TRACKER_FILE}\" || echo \"[❌ FAIL] ${REPO} - see log: ${LOG_FILE}\" && echo \"${REPO},FAIL,${LOG_FILE}\" >> \"${TRACKER_FILE}\"'"
  fi

  COMMANDS+=("$CMD")
done

# === Parallel Build Execution ===
# === Parallel Build Execution ===
CPU_CORES=$(nproc)

echo -e "\n🚀 Running ${#COMMANDS[@]} builds in parallel using ${CPU_CORES} CPU cores...\n"
printf "%s\n" "${COMMANDS[@]}" | parallel -j "$CPU_CORES" --tag --lb --bar
echo -e "\n📄 Build tracker written to: $TRACKER_FILE"
