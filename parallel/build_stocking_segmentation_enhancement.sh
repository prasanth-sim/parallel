#!/bin/bash
set -Eeuo pipefail
trap 'echo "[ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)" >&2' ERR

# === Setup ===
REPO_NAME="Stocking-Segmentation-Enhancement"
MODULE_NAME="Stocking_Enhancement"
BRANCH_NAME="${1:-main}"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

LOG_DIR="$HOME/automationlogs"
REPO_DIR="$HOME/projects/repos/$REPO_NAME"
BUILD_DIR="$HOME/projects/builds/$REPO_NAME/${BRANCH_NAME//\//_}_$DATE_TAG"
LATEST_LINK="$HOME/projects/builds/$REPO_NAME/latest"
LOG_FILE="$LOG_DIR/build_${REPO_NAME}_${DATE_TAG}.log"

mkdir -p "$LOG_DIR" "$BUILD_DIR"

echo " Updating/cloning $REPO_NAME..." | tee -a "$LOG_FILE"
if [[ -d "$REPO_DIR/.git" ]]; then
  cd "$REPO_DIR"
  git fetch origin
  git checkout "$BRANCH_NAME"
  git pull origin "$BRANCH_NAME"
else
  git clone "https://github.com/simaiserver/${REPO_NAME}.git" "$REPO_DIR"
  cd "$REPO_DIR"
  git checkout "$BRANCH_NAME"
fi

echo " Building with Maven..." | tee -a "$LOG_FILE"
mvn clean install -DskipTests | tee -a "$LOG_FILE"

echo " Searching for artifact..." | tee -a "$LOG_FILE"
JAR_PATH=$(find target -name "${MODULE_NAME}-*.jar" ! -name "*original*" | head -n1)

if [[ -z "$JAR_PATH" ]]; then
  echo "[ ERROR] JAR not found!" | tee -a "$LOG_FILE"
  exit 1
fi

echo " Copying JAR to $BUILD_DIR..." | tee -a "$LOG_FILE"
cp -p "$JAR_PATH" "$BUILD_DIR/"

echo " Updating symlink: $LATEST_LINK → $BUILD_DIR" | tee -a "$LOG_FILE"
ln -sfn "$BUILD_DIR" "$LATEST_LINK"

echo "✅ Build complete: $(basename "$JAR_PATH")" | tee -a "$LOG_FILE"
echo "📁 Available at: $LATEST_LINK" | tee -a "$LOG_FILE"
