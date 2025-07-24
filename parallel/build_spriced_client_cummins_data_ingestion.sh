#!/bin/bash
set -Eeuo pipefail
trap 'echo "[ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

REPO_NAME="spriced-client-cummins-data-ingestion"
REPO_URL="https://github.com/simaiserver/${REPO_NAME}.git"
BRANCH="${1:-main}"

CLONE_DIR="$HOME/projects/repos/$REPO_NAME"
BUILD_DIR="$HOME/projects/builds/$REPO_NAME"
LATEST_DIR="$BUILD_DIR/latest"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="$HOME/automationlogs"
LOG_FILE="$LOG_DIR/build_${REPO_NAME}.log"

mkdir -p "$CLONE_DIR" "$BUILD_DIR" "$LOG_DIR"

echo " [$TIMESTAMP] Starting build for $REPO_NAME | Branch: $BRANCH" | tee -a "$LOG_FILE"

# Clone or pull latest
if [ -d "$CLONE_DIR/.git" ]; then
  echo " Repo exists. Pulling latest for $BRANCH..." | tee -a "$LOG_FILE"
  cd "$CLONE_DIR"
  git fetch origin "$BRANCH" | tee -a "$LOG_FILE"
  git checkout "$BRANCH" | tee -a "$LOG_FILE"
  git pull origin "$BRANCH" | tee -a "$LOG_FILE"
else
  echo " Cloning repo $REPO_NAME..." | tee -a "$LOG_FILE"
  git clone --branch "$BRANCH" "$REPO_URL" "$CLONE_DIR" | tee -a "$LOG_FILE"
  cd "$CLONE_DIR"
fi

COMMIT_ID=$(git rev-parse --short HEAD)
echo " Checked out to $BRANCH | Commit: $COMMIT_ID" | tee -a "$LOG_FILE"

# Maven Build
echo "Building the project with Maven..." | tee -a "$LOG_FILE"
mvn clean package -DskipTests | tee -a "$LOG_FILE"

# Copy Artifacts
echo " Copying artifacts to $LATEST_DIR..." | tee -a "$LOG_FILE"
mkdir -p "$LATEST_DIR"
cp target/*.jar "$LATEST_DIR" | tee -a "$LOG_FILE"

# Create timestamped backup
ARCHIVE_DIR="${BUILD_DIR}/${REPO_NAME}_${TIMESTAMP}"
mkdir -p "$ARCHIVE_DIR"
cp target/*.jar "$ARCHIVE_DIR" | tee -a "$LOG_FILE"

echo " Build completed for $REPO_NAME at $TIMESTAMP" | tee -a "$LOG_FILE"
