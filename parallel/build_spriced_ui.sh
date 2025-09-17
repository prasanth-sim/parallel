#!/bin/bash
set -Eeuo pipefail

# Trap command that removes the build directory on script failure.
trap 'if [ -d "$BUILD_DIR" ]; then rm -rf "$BUILD_DIR"; echo "[❌ CLEANUP] Removed temporary build directory: $BUILD_DIR"; fi; exit 1' ERR

# === Script Arguments ===
# ENV: Environment name (e.g., dev, qa, prasanth) or full URL
ENV="${1:-}"
# BRANCH: Git branch to checkout
BRANCH="${2:-main}"
# URL_SEPARATOR: The character to use for the URL separator ('-' or '.')
URL_SEPARATOR="${3:-.}"
# BASE_DIR: Base directory for repos, builds, and logs
BASE_DIR="${4:-$HOME/automation_workspace}"

# === Input Validation ===
if [[ -z "$ENV" || -z "$BRANCH" || -z "$BASE_DIR" ]]; then
    echo " Missing required arguments. Usage: $0 <ENV> <BRANCH> <URL_SEPARATOR> <BASE_DIR>"
    exit 1
fi

# Check for npx command
command -v npx >/dev/null || { echo " 'npx' not found. Install Node.js first."; exit 1; }

# === Path Definitions ===
REPO="spriced-ui"
REPO_DIR="$BASE_DIR/repos/$REPO"
# --- ⚠️ MODIFIED HERE ⚠️ ---
# Set the base build directory to match your desired path structure.
BUILD_OUTPUT_ROOT_DIR="$BASE_DIR/builds/$REPO/$ENV"
# The BUILD_DIR now uses the branch name and "latest" as requested.
BUILD_DIR="$BUILD_OUTPUT_ROOT_DIR/$BRANCH/latest"
# Determine the pipeline configuration directory.
PIPELINE_DIR="$BASE_DIR/spriced-pipeline"
CONFIG_PIPELINE_BASE="$PIPELINE_DIR/framework/frontend"

# List of microfrontends
MICROFRONTENDS=(
    "spriced-container"
    "spriced-data"
    "spriced-data-definition"
    "spriced-reports"
    "spriced-user-management"
)

# === Script Execution Start ===
echo "Starting UI build for ENV='$ENV', BRANCH='$BRANCH'..."
echo "Build directory: $BUILD_DIR"

# Step 1: Prepare the repository
echo " Preparing '$REPO' repository..."
if [[ ! -d "$REPO_DIR/.git" ]]; then
    echo "  - Cloning from https://github.com/simaiserver/$REPO.git"
    git clone "https://github.com/simaiserver/$REPO.git" "$REPO_DIR"
fi
cd "$REPO_DIR"
git fetch origin
echo "  - Checking out branch: $BRANCH"
git checkout "$BRANCH"
git reset --hard "origin/$BRANCH"

# Step 2: Inject .env files for the build process
echo " Injecting environment files from spriced-pipeline into repository..."
# This part remains the same, as it handles the .env files.
if [[ "$ENV" =~ ^https?:\/\/.*simadvisory\.com$ ]]; then
    SOURCE_ENV_DIR="$CONFIG_PIPELINE_BASE/nrp-dev"
else
    SOURCE_ENV_DIR="$CONFIG_PIPELINE_BASE/nrp-$ENV"
fi
if [ ! -d "$SOURCE_ENV_DIR" ]; then
    echo " Missing environment configuration directory: $SOURCE_ENV_DIR"
    exit 1
fi
for mf in "${MICROFRONTENDS[@]}"; do
    SRC_ENV_FILE="$SOURCE_ENV_DIR/$mf/.env"
    DEST_ENV_FILE="$REPO_DIR/apps/$mf/.env"
    if [[ -f "$SRC_ENV_FILE" ]]; then
        mkdir -p "$(dirname "$DEST_ENV_FILE")"
        cp "$SRC_ENV_FILE" "$DEST_ENV_FILE"
        echo "  - Applied env for '$mf' from '$SOURCE_ENV_DIR'."
    else
        echo "  - Missing .env for '$mf': $SRC_ENV_FILE. Skipping."
    fi
done

# Step 3: Install Node dependencies
echo "Installing Node dependencies..."
npm install

# Step 4: Build projects using Nx
echo "Building projects with Nx..."
rm -rf dist/
npx nx run-many --target=build --projects=$(IFS=,; echo "${MICROFRONTENDS[*]}") --configuration=production

# Step 4.5: Copy the pre-existing Module Federation Manifest Files
echo " Copying pre-existing Module Federation manifest file from pipeline repo..."

# --- ⚠️ MODIFIED HERE ⚠️ ---
# The source for the manifest file is now explicitly set to the 'nrp-dev' folder,
# regardless of the chosen environment. This ensures relative paths are always used.
MANIFEST_SOURCE_FILE="$CONFIG_PIPELINE_BASE/nrp-dev/module-federation.manifest.json"

# Check if the standard manifest file exists
if [ ! -f "$MANIFEST_SOURCE_FILE" ]; then
    echo " Standard manifest file not found at '$MANIFEST_SOURCE_FILE'. Cannot proceed."
    exit 1
fi

# Destination paths remain the same
MANIFEST_DEST_ROOT="$REPO_DIR/dist/apps/module-federation.manifest.json"
MANIFEST_DEST_CONTAINER="$REPO_DIR/dist/apps/spriced-container/assets/module-federation.manifest.json"

# Copy the standard manifest file to both required locations
cp "$MANIFEST_SOURCE_FILE" "$MANIFEST_DEST_ROOT"
mkdir -p "$(dirname "$MANIFEST_DEST_CONTAINER")"
cp "$MANIFEST_SOURCE_FILE" "$MANIFEST_DEST_CONTAINER"

echo "  - Copied standard manifest file to '$MANIFEST_DEST_ROOT'."
echo "  - Copied standard manifest file to '$MANIFEST_DEST_CONTAINER'."

# Step 5: Copy build artifacts
echo " Copying build artifacts..."
# Remove the existing 'latest' directory before copying to ensure it's a fresh build.
if [ -d "$BUILD_DIR" ]; then
    rm -rf "$BUILD_DIR"
    echo "  - Removed old build directory: $BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
if [ ! -d "$REPO_DIR/dist/apps" ]; then
    echo " Nx build output not found. The build may have failed."
    exit 1
fi
cp -r "$REPO_DIR/dist/apps/"* "$BUILD_DIR/"

echo "UI build finished successfully."
