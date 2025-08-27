#!/bin/bash
set -Eeuo pipefail
trap 'echo "[ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# === Inputs from Main Script ===
BRANCH_NAME="${1:-main}"
BASE_DIR="${2:-$HOME/projects}"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

# === Constants ===
REPO_NAME="Stocking-Segmentation-Enhancement"
MODULE_NAME="Stocking_Enhancement"

# === Derived Paths ===
REPO_DIR="$BASE_DIR/repos/$REPO_NAME"
BUILD_DIR="$BASE_DIR/builds/$REPO_NAME/${BRANCH_NAME//\//_}_$DATE_TAG"
LOG_DIR="$BASE_DIR/automationlogs"
LATEST_LINK="$BASE_DIR/builds/$REPO_NAME/latest"
LOG_FILE="$LOG_DIR/build_${REPO_NAME}_${DATE_TAG}.log"

mkdir -p "$LOG_DIR" "$BUILD_DIR"

echo "Updating/cloning $REPO_NAME..." | tee -a "$LOG_FILE"
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

echo "Building with Maven..." | tee -a "$LOG_FILE"
mvn clean install -Dmaven.test.skip=true | tee -a "$LOG_FILE"

echo " Searching for artifact..." | tee -a "$LOG_FILE"
JAR_PATH=$(find target -name "${MODULE_NAME}-*.jar" ! -name "*original*" | head -n1)

if [[ -z "$JAR_PATH" ]]; then
  echo "[ERROR] JAR not found!" | tee -a "$LOG_FILE"
  exit 1
fi

echo "Copying JAR to $BUILD_DIR..." | tee -a "$LOG_FILE"
cp -p "$JAR_PATH" "$BUILD_DIR/"

echo " Updating symlink: $LATEST_LINK → $BUILD_DIR" | tee -a "$LOG_FILE"
ln -sfn "$BUILD_DIR" "$LATEST_LINK"

echo " Build complete: $(basename "$JAR_PATH")" | tee -a "$LOG_FILE"
echo " Available at: $LATEST_LINK" | tee -a "$LOG_FILE"
