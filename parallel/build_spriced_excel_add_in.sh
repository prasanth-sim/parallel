#!/bin/bash
set -Eeuo pipefail
trap 'echo "[ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# === INPUT ARGUMENTS ===
BRANCH="${1:-main}"
ENVIRONMENT="${2:-dev}"
BASE_DIR="${3:-$HOME/projects}"
REPO="spriced-excel-add-in"

# === Directories and Logging Setup ===
DATE_TAG=$(date +"%Y%m%d_%H%M%S")
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_BASE="$BASE_DIR/builds/$REPO"
LOG_DIR="$BASE_DIR/automationlogs"
mkdir -p "$REPO_DIR" "$BUILD_BASE" "$LOG_DIR"
LOG_FILE="$LOG_DIR/${REPO//\//-}_${BRANCH}_${DATE_TAG}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "--- Starting build for [$REPO] on branch [$BRANCH], environment [$ENVIRONMENT] at $(date) ---"

# === Clone or Update Repo ===
if [[ -d "$REPO_DIR/.git" ]]; then
    echo "Updating existing repo at $REPO_DIR"
    cd "$REPO_DIR"
    git fetch origin --prune
    git checkout -B "$BRANCH" "origin/$BRANCH"
    git pull origin "$BRANCH"
else
    echo "Cloning repo to $REPO_DIR"
    git clone "https://github.com/simaiserver/$REPO.git" "$REPO_DIR"
    cd "$REPO_DIR"
    git checkout "$BRANCH"
fi

# === NPM Dependency Installation with legacy-peer-deps ===
echo "Installing Node.js dependencies with --legacy-peer-deps..."
if ! npm install --legacy-peer-deps; then
    echo "[ERROR] npm install failed. Exiting build."
    exit 1
fi

# === Build Command Based on Environment ===
echo "Running npm build for environment: [$ENVIRONMENT]..."
case "$ENVIRONMENT" in
    dev|uat|staging|test|qa)
        npm_command="npm run build:$ENVIRONMENT"
        ;;
    prod)
        npm_command="npm run build"
        ;;
    *)
        echo "[ERROR] Invalid environment '$ENVIRONMENT' provided. Exiting."
        exit 1
        ;;
esac

if ! $npm_command; then
    echo "[ERROR] npm build failed. Exiting."
    exit 1
fi

# === Display the new version after build ===
NEW_VERSION=$(node -p "require('./package.json').version")
echo "Build completed with version: v$NEW_VERSION"

# === Copy Build Artifacts from nested dist directory ===
BUILD_DIR="$BUILD_BASE/${BRANCH}_${DATE_TAG}"
mkdir -p "$BUILD_DIR"
echo "Copying build artifacts from '$REPO_DIR/dist/poc-add-in/' to '$BUILD_DIR'..."
cp -r "$REPO_DIR/dist/poc-add-in/." "$BUILD_DIR/"

# === Create zip archive if zip command is available ===
echo "Creating zip archive of build artifacts..."
ZIP_FILE="$BUILD_BASE/${REPO}-${ENVIRONMENT}-${DATE_TAG}.zip"
if command -v zip >/dev/null 2>&1; then
    (
        cd "$BUILD_DIR"
        zip -r "$ZIP_FILE" ./*
    )
    echo "Zip file created at: $ZIP_FILE"
else
    echo "Warning: 'zip' command not found. Skipping zip archive creation."
fi

# === Update 'latest' symlink ===
echo "Updating 'latest' symlink to latest build directory..."
ln -sfn "$BUILD_DIR" "$BUILD_BASE/latest"

echo "--- Build complete for [$REPO] on branch [$BRANCH] and environment [$ENVIRONMENT] at $(date) ---"
echo "Artifacts stored at: $BUILD_DIR"
echo "Latest symlink: $BUILD_BASE/latest"
echo "Zip file: $ZIP_FILE"

