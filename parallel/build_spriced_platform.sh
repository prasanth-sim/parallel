#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)" >&2' ERR

# === Config ===
REPO="spriced-platform"
BRANCH="${1:-main}"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="$HOME/automationlogs"
REPO_DIR="$HOME/projects/repos/$REPO"
BUILD_DIR="$HOME/projects/builds/$REPO/${BRANCH//\//_}_$DATE_TAG"
LATEST_LINK="$HOME/projects/builds/$REPO/latest"

mkdir -p "$LOG_DIR" "$BUILD_DIR"
LOG_FILE="$LOG_DIR/${REPO}_${DATE_TAG}.log"
exec &> >(tee -a "$LOG_FILE")

echo "🚀 Starting build for [$REPO] on branch [$BRANCH]..."

# === Git checkout ===
cd "$REPO_DIR"
echo "🔄 Fetching branch [$BRANCH] from origin..."
git fetch origin "$BRANCH"
git checkout "$BRANCH"
git reset --hard "origin/$BRANCH"

# === Maven Build ===
echo "🔧 Running Maven build..."
mvn clean install -DskipTests

# === Copy Artifacts ===
echo "📦 Copying build artifacts..."

declare -A ARTIFACTS=(
  ["spriced-platform"]="orchestratorRest,flinkRestImage"
)

IFS=',' read -ra MODULES <<< "${ARTIFACTS[$REPO]}"

for module in "${MODULES[@]}"; do
  JAR_PATH="$REPO_DIR/$module/target"
  JAR_FILE=$(find "$JAR_PATH" -maxdepth 1 -type f -name "*.jar" ! -name "*sources.jar" ! -name "*javadoc.jar" | head -n1)

  if [[ -f "$JAR_FILE" ]]; then
    cp "$JAR_FILE" "$BUILD_DIR/"
    echo "✅ Copied $(basename "$JAR_FILE")"
  else
    echo "⚠️ JAR not found for module [$module]"
  fi
done

# === Update 'latest' symlink ===
ln -sfn "$BUILD_DIR" "$LATEST_LINK"

echo "✅ Build complete for [$REPO] on branch [$BRANCH]"
echo "🗂️ Artifacts: $BUILD_DIR"
echo "📝 Log File: $LOG_FILE"

