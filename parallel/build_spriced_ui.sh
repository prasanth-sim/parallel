#!/bin/bash
set -Eeuo pipefail
# Trap errors: log the error, remove the build directory, and exit with failure.
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)" >&2; rm -rf "$BUILD_DIR"; exit 1' ERR

# === Script Arguments ===
# ENV: Environment (dev, qa, test) - required
ENV="${1:-}"
# BRANCH: Git branch to checkout - defaults to 'main'
BRANCH="${2:-main}"
# BASE_DIR: Base directory for repos, builds, and logs - defaults to $HOME/projects
BASE_DIR="${3:-$HOME/projects}"

# === Input Validation and Safety Checks ===
VALID_ENVS=("dev" "qa" "test")
if [[ ! " ${VALID_ENVS[*]} " =~ " ${ENV} " ]]; then
  echo "❌ Invalid environment: '$ENV'. Use one of: ${VALID_ENVS[*]}"
  exit 1
fi

# Ensure BASE_DIR is not empty after argument processing
if [[ -z "$BASE_DIR" ]]; then
  echo "❌ BASE_DIR is empty. This should not happen. Please check script arguments or default value."
  exit 1
fi

# Check for npx command
command -v npx >/dev/null || { echo "❌ 'npx' not found. Install Node.js first."; exit 1; }

# === Path Definitions ===
REPO="spriced-ui"
REPO_URL="https://github.com/simaiserver/$REPO.git"
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_ROOT="$BASE_DIR/builds/$REPO/$ENV/latest"
LOG_DIR="$BASE_DIR/automationlogs"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BUILD_DIR="$BUILD_ROOT/${BRANCH}_${TIMESTAMP}"
LOG_FILE="$LOG_DIR/${REPO}_${ENV}_${BRANCH}_${TIMESTAMP}.log"

# Base path for environment configurations within the spriced-pipeline repository
# This assumes spriced-pipeline is cloned at $BASE_DIR/spriced-pipeline
CONFIG_PIPELINE_BASE="$BASE_DIR/spriced-pipeline/framework/frontend/nrp-$ENV"

# Define MANIFEST_SOURCE after CONFIG_PIPELINE_BASE is set
MANIFEST_SOURCE="$CONFIG_PIPELINE_BASE/module-federation.manifest.json"

# List of microfrontends that need their respective .env files
MICROFRONTENDS=(
  "spriced-container"
  "spriced-data"
  "spriced-data-definition"
  "spriced-reports"
  "spriced-user-management"
)

# Create necessary directories
mkdir -p "$BUILD_DIR" "$LOG_DIR"

# Redirect all script output (stdout and stderr) to both console and log file
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[ℹ️] Starting UI build for ENV='$ENV', BRANCH='$BRANCH' at $TIMESTAMP"
echo "DEBUG: BASE_DIR = '$BASE_DIR'"
echo "DEBUG: ENV = '$ENV'"
echo "DEBUG: CONFIG_PIPELINE_BASE = '$CONFIG_PIPELINE_BASE'"
echo "DEBUG: MANIFEST_SOURCE (after definition) = '$MANIFEST_SOURCE'"


# === Git Operations for spriced-ui ===
# Clone or update spriced-ui repository
if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "[⬇️] Cloning $REPO..."
  git clone "$REPO_URL" "$REPO_DIR" || { echo "❌ Failed to clone $REPO."; exit 1; }
else
  echo "[📦] Repo exists. Fetching updates..."
  git -C "$REPO_DIR" fetch origin || { echo "❌ Failed to fetch updates for $REPO."; exit 1; }
fi

# Change to the repository directory
cd "$REPO_DIR" || { echo "❌ Failed to change directory to $REPO_DIR."; exit 1; }

# Checkout the specified branch and hard reset
echo "[🌿] Checking out branch: $BRANCH"
git checkout "$BRANCH" || { echo "❌ Failed to checkout branch $BRANCH."; exit 1; }
git reset --hard "origin/$BRANCH" || { echo "❌ Failed to hard reset branch $BRANCH."; exit 1; }
GIT_COMMIT=$(git rev-parse HEAD)
echo "[📌] Git commit used: $GIT_COMMIT"

# === Inject .env files from spriced-pipeline ===
echo "[🔧] Injecting environment files from spriced-pipeline..."
for mf in "${MICROFRONTENDS[@]}"; do
  # IMPORTANT: This path assumes .env files are located in subdirectories
  # within spriced-pipeline, e.g., 'spriced-pipeline/.../nrp-dev/spriced-container/.env'
  SRC_ENV_FILE="$CONFIG_PIPELINE_BASE/$mf/.env"
  # Destination directory for the .env file within the spriced-ui repository
  DEST_DIR="$REPO_DIR/apps/$mf"
  DEST_ENV_FILE="$DEST_DIR/.env"

  if [[ ! -f "$SRC_ENV_FILE" ]]; then
    echo "[⚠️] Missing env for $mf: $SRC_ENV_FILE"
    continue # Skip to the next microfrontend if its .env file is not found
  fi

  # Ensure the destination directory exists in spriced-ui
  mkdir -p "$DEST_DIR"

  # Backup existing .env file in spriced-ui before overwriting
  if [[ -f "$DEST_ENV_FILE" ]]; then
    cp "$DEST_ENV_FILE" "$DEST_ENV_FILE.bak.$(date +%s)"
    echo "[ℹ️] Backed up existing .env for $mf to $DEST_ENV_FILE.bak"
  fi

  # Copy the environment file
  cp "$SRC_ENV_FILE" "$DEST_ENV_FILE"
  echo "[✅] Applied env for $mf from $SRC_ENV_FILE to $DEST_ENV_FILE"
done

# === Install Node Modules ===
if [ ! -d "node_modules" ]; then
  echo "[🧩] Installing node modules..."
  npm install || { echo "❌ npm install failed."; exit 1; }
else
  echo "[🧩] node_modules already exists. Skipping npm install."
fi

# === Build Projects using Nx ===
echo "[🏗️] Building projects..."
rm -rf dist/ # Clean previous build artifacts
# Build all specified microfrontends using Nx
npx nx run-many --target=build --projects=$(IFS=,; echo "${MICROFRONTENDS[*]}") || { echo "❌ Nx build failed."; exit 1; }

# === Copy Build Artifacts ===
echo "[📂] Copying output to $BUILD_DIR"
for APP_DIR in dist/apps/*; do
  # Extract the application name from the path (e.g., 'spriced-container')
  APP_NAME=$(basename "$APP_DIR")
  TARGET_DIR="$BUILD_DIR/$APP_NAME"
  mkdir -p "$TARGET_DIR"
  # Copy all contents from the built app directory to the target build directory
  cp -r "$APP_DIR/"* "$TARGET_DIR/" || { echo "❌ Failed to copy artifacts for $APP_NAME."; exit 1; }

  # Optional: Copy the specific .env file to the deployed artifact directory as well
  # This might be useful for debugging or if the deployed app needs to access its .env file directly.
  # This path is the same as where it was copied to in the REPO_DIR/apps/$mf/.env
  ENV_FILE_IN_REPO="$REPO_DIR/apps/$APP_NAME/.env"
  if [[ -f "$ENV_FILE_IN_REPO" ]]; then
    cp "$ENV_FILE_IN_REPO" "$TARGET_DIR/.env"
    echo "[✅] Copied $APP_NAME/.env to deployed artifact."
  fi
done

# === Copy Module Federation Manifest ===
echo "[📜] Copying module-federation.manifest.json..."
# DEBUG: Check MANIFEST_SOURCE right before its usage
echo "DEBUG (Before Manifest Copy Check): MANIFEST_SOURCE = '$MANIFEST_SOURCE'"
if [[ -f "$MANIFEST_SOURCE" ]]; then
  cp "$MANIFEST_SOURCE" "$BUILD_DIR/module-federation.manifest.json" || { echo "❌ Failed to copy manifest."; exit 1; }
  echo "[✅] Manifest copied"
else
  echo "[❌] Module federation manifest not found at $MANIFEST_SOURCE"
  exit 1
fi

echo "[✅] Build complete!"
echo "📁 Output: $BUILD_DIR"
echo "📝 Log:    $LOG_FILE"
exit 0
