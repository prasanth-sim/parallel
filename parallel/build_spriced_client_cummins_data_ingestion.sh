#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# ==== CONFIGURATION ====
REPO="spriced-client-cummins-data-ingestion"
BRANCH="${1:-main}"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

BASE_DIR="$HOME/projects"
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_BASE="$BASE_DIR/builds/$REPO"
LOG_DIR="$HOME/automationlogs"
mkdir -p "$REPO_DIR" "$BUILD_BASE" "$LOG_DIR"

LOG_FILE="$LOG_DIR/${REPO//\//-}_${BRANCH}_${DATE_TAG}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "🚀 Starting build for [$REPO] on branch [$BRANCH]"

# ==== CLONE OR UPDATE REPO ====
if [[ -d "$REPO_DIR/.git" ]]; then
  echo "🔁 Updating existing repo..."
  cd "$REPO_DIR"
  git fetch origin
  git checkout "$BRANCH"
  git pull origin "$BRANCH"
else
  echo "📥 Cloning repo..."
  git clone "https://github.com/simaiserver/$REPO.git" "$REPO_DIR"
  cd "$REPO_DIR"
  git checkout "$BRANCH"
fi

# ==== BUILD ====
echo "🔨 Running Maven build..."
mvn clean install -Dmaven.test.skip=true

# ==== COPY ARTIFACTS ====
BUILD_DIR="$BUILD_BASE/${BRANCH}_${DATE_TAG}"
mkdir -p "$BUILD_DIR"

echo "📦 Copying JARs to [$BUILD_DIR]..."
find "$REPO_DIR" -type f -path "*/target/*.jar" ! -name "*original*" -exec cp -p {} "$BUILD_DIR/" \;

# ==== UPDATE LATEST SYMLINK ====
echo "🔗 Updating 'latest' symlink..."
ln -sfn "$BUILD_DIR" "$BUILD_BASE/latest"

# ==== DONE ====
echo "✅ Build complete for [$REPO] on branch [$BRANCH]"
echo "🗂️ Artifacts: $BUILD_DIR"
echo "🔗 Latest: $BUILD_BASE/latest"
