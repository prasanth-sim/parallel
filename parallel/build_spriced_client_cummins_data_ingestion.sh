#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# === INPUT ARGUMENTS ===
BRANCH="${1:-main}"
BASE_DIR="${2:-$HOME/projects}"   # fallback
REPO="spriced-client-cummins-data-ingestion"

DATE_TAG=$(date +"%Y%m%d_%H%M%S")

# === Dynamic Paths ===
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_BASE="$BASE_DIR/builds/$REPO"
LOG_DIR="$BASE_DIR/automationlogs"

mkdir -p "$REPO_DIR" "$BUILD_BASE" "$LOG_DIR"

LOG_FILE="$LOG_DIR/${REPO//\//-}_${BRANCH}_${DATE_TAG}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "🚀 Starting build for [$REPO] on branch [$BRANCH]"

# === Clone or Update ===
if [[ -d "$REPO_DIR/.git" ]]; then
  echo "🔁 Updating existing repo at $REPO_DIR"
  cd "$REPO_DIR"
  git fetch origin
  git checkout "$BRANCH"
  git pull origin "$BRANCH"
else
  echo "📥 Cloning repo to $REPO_DIR"
  git clone "https://github.com/simaiserver/$REPO.git" "$REPO_DIR"
  cd "$REPO_DIR"
  git checkout "$BRANCH"
fi

# === Build ===
echo "🔨 Running Maven build..."
mvn clean install -Dmaven.test.skip=true

# === Artifact Copy with ARTIFACTS Filter ===
BUILD_DIR="$BUILD_BASE/${BRANCH}_${DATE_TAG}"
mkdir -p "$BUILD_DIR"

declare -A ARTIFACTS=(
  ["spriced-client-cummins-data-ingestion"]="spriced-client-cummins-data-ingestion"
)

ARTIFACT_LIST="${ARTIFACTS[$REPO]}"
IFS=',' read -ra ARTIFACT_NAMES <<< "$ARTIFACT_LIST"

echo "📦 Copying matched artifacts to [$BUILD_DIR]..."
for ARTIFACT in "${ARTIFACT_NAMES[@]}"; do
  FOUND_JARS=$(find "$REPO_DIR" -type f -path "*/target/*.jar" -name "${ARTIFACT}*.jar" ! -name "*original*" || true)
  if [[ -z "$FOUND_JARS" ]]; then
    echo "⚠️ No JARs found for [$ARTIFACT] in $REPO_DIR"
  else
    echo "$FOUND_JARS" | while read -r JAR_PATH; do
      echo "✅ Copying: $JAR_PATH"
      cp -p "$JAR_PATH" "$BUILD_DIR/"
    done
  fi
done

# === Symlink 'latest' ===
echo "🔗 Updating 'latest' symlink..."
ln -sfn "$BUILD_DIR" "$BUILD_BASE/latest"

# === Done ===
echo "✅ Build complete for [$REPO] on branch [$BRANCH]"
echo "🗂️ Artifacts stored at: $BUILD_DIR"
echo "🔗 Latest symlink: $BUILD_BASE/latest"
