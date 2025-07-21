#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# Setup paths
REPO_NAME="spriced-ui"
REPO_DIR="$HOME/projects/repos/$REPO_NAME"
LOG_DIR="$HOME/projects/logs"
LOG_FILE="$LOG_DIR/${REPO_NAME}_build_$(date +'%Y%m%d_%H%M%S').log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Start log
echo "🛠️  Starting NX build for $REPO_NAME at $(date)" | tee -a "$LOG_FILE"
echo "📁 Repo Directory: $REPO_DIR" | tee -a "$LOG_FILE"

# Change to repo directory
cd "$REPO_DIR"

# Build all projects in the monorepo
echo "🚧 Running: npx nx run-many --targets=build --all" | tee -a "$LOG_FILE"
npx nx run-many --targets=build --all | tee -a "$LOG_FILE"

# Final log
echo "✅ Build complete for $REPO_NAME at $(date)" | tee -a "$LOG_FILE"
