#!/bin/bash
set -Eeuo pipefail
trap 'echo "[ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)" | tee -a "$LOG_FILE"' ERR

REPO_NAME="spriced-client-cummins-parts-pricing"
BRANCH="${1:-main}"
REPO_DIR="$HOME/projects/repos/$REPO_NAME"
BUILD_BASE="$HOME/projects/builds/$REPO_NAME"
LOG_DIR="$HOME/automationlogs"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

BUILD_DIR="$BUILD_BASE/${BRANCH//\//_}_$DATE_TAG"
LOG_FILE="$LOG_DIR/${REPO_NAME}_${BRANCH//\//_}_$DATE_TAG.log"

mkdir -p "$BUILD_DIR" "$LOG_DIR"

{
echo " Building [$REPO_NAME] on branch [$BRANCH]..."

# === Git pull ===
cd "$REPO_DIR"
git reset --hard
git fetch origin
git checkout "$BRANCH"
git pull origin "$BRANCH"

# === Maven build ===
echo "🛠️Running Maven build..."
./mvnw clean install -Dmaven.test.skip=true

# === Copy JAR ===
JAR_PATH=$(find "$REPO_DIR/target" -name "*.jar" ! -name "*original*" | head -n1)
if [[ -f "$JAR_PATH" ]]; then
  cp -p "$JAR_PATH" "$BUILD_DIR/"
  echo " Copied JAR: $(basename "$JAR_PATH")"
else
  echo " No JAR found to copy."
fi

# === Done ===
ln -snf "$BUILD_DIR" "$BUILD_BASE/latest"
echo "✅ Build completed at [$DATE_TAG]"
echo "📁 Artifacts in: $BUILD_DIR"
} | tee "$LOG_FILE"
