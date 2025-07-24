#!/bin/bash
set -Eeuo pipefail
trap 'echo "[ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)" >&2' ERR

# === Setup ===
repo="spriced-backend"
branch="${1:-main}"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="$HOME/automationlogs"
REPO_DIR="$HOME/projects/repos/$repo"
BUILD_DIR="$HOME/projects/builds/$repo/${branch//\//_}_$DATE_TAG"
LATEST_LINK="$HOME/projects/builds/$repo/latest"

mkdir -p "$LOG_DIR" "$BUILD_DIR"

LOG_FILE="$LOG_DIR/${repo}_${branch//\//_}_$DATE_TAG.log"
exec &> >(tee -a "$LOG_FILE")

echo " Starting build for [$repo] on branch [$branch]..."

# === Git checkout ===
cd "$REPO_DIR"
echo " Fetching latest from origin/$branch..."
git fetch origin "$branch"
git checkout "$branch"
git reset --hard "origin/$branch"

# === Maven Build ===
echo " Building sim-spriced-api-parent..."
cd "$REPO_DIR/sim-spriced-api-parent"
mvn clean install -Dmaven.test.skip=true

echo " Building sim-spriced-api-gateway..."
cd "$REPO_DIR/sim-spriced-api-gateway"
mvn clean install -Dmaven.test.skip=true

# === Define ARTIFACTS mapping ===
declare -A ARTIFACTS=(
  ["spriced-backend"]="sim-spriced-user-access-api,sim-spriced-data-api,sim-spriced-jobs-api,sim-spriced-defnition-api,sim-spriced-api-gateway"
)

# === Copy Artifacts ===
echo " Copying build artifacts to: $BUILD_DIR"
IFS=',' read -ra MODULES <<< "${ARTIFACTS[$repo]}"
for module in "${MODULES[@]}"; do
  jar_path=$(find "$REPO_DIR" -path "*/$module/target/*.jar" ! -name "*original*" 2>/dev/null | head -n1)
  if [[ -f "$jar_path" ]]; then
    cp -p "$jar_path" "$BUILD_DIR/"
    echo " Copied: $(basename "$jar_path")"
  else
    echo "Missing artifact for module: $module"
  fi
done

# === Update symlink ===
ln -snf "$BUILD_DIR" "$LATEST_LINK"

echo "✅ Build completed for [$repo] at [$DATE_TAG]"
echo "📁 Artifacts available in: $BUILD_DIR"
echo "📄 Log saved to: $LOG_FILE"
