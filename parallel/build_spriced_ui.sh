#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)" >&2; rm -rf "$BUILD_DIR"; exit 1' ERR

ENV="${1:-}"
BRANCH="${2:-main}"
VALID_ENVS=("dev" "qa" "test")

if [[ ! " ${VALID_ENVS[*]} " =~ " ${ENV} " ]]; then
  echo "❌ Invalid environment: '$ENV'. Use one of: ${VALID_ENVS[*]}"
  exit 1
fi

# Pre-check for required tools
command -v npx >/dev/null || { echo "❌ 'npx' not found. Install Node.js first."; exit 1; }

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
REPO="spriced-ui"
REPO_URL="https://github.com/simaiserver/$REPO.git"

BASE_DIR="$HOME/projects"
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_DIR="$BASE_DIR/builds/$REPO/$ENV/$TIMESTAMP"
LATEST_LINK="$BASE_DIR/builds/$REPO/$ENV/latest"
LOG_DIR="$HOME/automationlogs"
LOG_FILE="$LOG_DIR/${REPO}_${ENV}_${TIMESTAMP}.log"

CONFIG_PIPELINE_BASE="$HOME/projects/spriced-pipeline/framework/frontend/nrp-$ENV"
MANIFEST_SOURCE="$CONFIG_PIPELINE_BASE/module-federation.manifest.json"

MICROFRONTENDS=(
  "spriced-container"
  "spriced-data"
  "spriced-data-definition"
  "spriced-reports"
  "spriced-user-management"
)

mkdir -p "$BUILD_DIR" "$LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "[ℹ️] Starting UI build for '$ENV' branch '$BRANCH' at $TIMESTAMP"

# Clone or update repository
if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "[⬇️] Cloning $REPO..."
  git clone "$REPO_URL" "$REPO_DIR"
else
  echo "[📦] Repo exists. Fetching latest for $BRANCH..."
  git -C "$REPO_DIR" fetch origin
fi

cd "$REPO_DIR"
git checkout "$BRANCH"
git reset --hard "origin/$BRANCH"
GIT_COMMIT=$(git rev-parse HEAD)
echo "[📌] Git commit used: $GIT_COMMIT"

# Inject environment files
echo "[🔧] Injecting .env files for environment '$ENV'..."
for mf in "${MICROFRONTENDS[@]}"; do
  SRC_ENV_FILE="$CONFIG_PIPELINE_BASE/$mf.env"
  DEST_DIR="$REPO_DIR/apps/$mf"
  DEST_ENV_FILE="$DEST_DIR/.env"

  if [[ ! -f "$SRC_ENV_FILE" ]]; then
    echo "[⚠️] Missing source env file: $SRC_ENV_FILE (skipping)"
    continue
  fi

  if [[ ! -d "$DEST_DIR" ]]; then
    echo "[⚠️] Missing destination directory: $DEST_DIR (creating it)"
    mkdir -p "$DEST_DIR"
  fi

  if [[ -f "$DEST_ENV_FILE" ]]; then
    cp "$DEST_ENV_FILE" "$DEST_ENV_FILE.bak.$(date +%s)"
    echo "[🔁] Backup created for $DEST_ENV_FILE"
  fi

  cp "$SRC_ENV_FILE" "$DEST_ENV_FILE"
  echo "[✅] Copied $SRC_ENV_FILE to $DEST_ENV_FILE"
done

# Run Nx build
echo "[🏗️] Running Nx build for microfrontends..."
rm -rf dist/
npx nx run-many --target=build --projects=$(IFS=,; echo "${MICROFRONTENDS[*]}")

# Copy build artifacts
echo "[📦] Copying build output to $BUILD_DIR..."
rm -rf "$BUILD_DIR"/*
for APP_DIR in dist/apps/*; do
  APP_NAME=$(basename "$APP_DIR")
  mkdir -p "$BUILD_DIR/$APP_NAME"
  cp -r "$APP_DIR/"* "$BUILD_DIR/$APP_NAME/"
  echo "[🔄] Copied build output for $APP_NAME"

  ENV_FILE="$CONFIG_PIPELINE_BASE/$APP_NAME/.env"
  if [[ -f "$ENV_FILE" ]]; then
    cp "$ENV_FILE" "$BUILD_DIR/$APP_NAME/.env"
    echo "[📥] Copied .env for $APP_NAME to build output"
  else
    echo "[⚠️] No .env found for $APP_NAME to copy"
  fi
done

# Copy manifest
if [[ -f "$MANIFEST_SOURCE" ]]; then
  cp "$MANIFEST_SOURCE" "$BUILD_DIR/module-federation.manifest.json"
  echo "[✅] Copied manifest file to build output"
else
  echo "[❌] Manifest file not found at $MANIFEST_SOURCE"
  exit 1
fi

# Create/update symlink to latest
ln -sfn "$BUILD_DIR" "$LATEST_LINK"
echo "[🔗] Updated symlink: $LATEST_LINK -> $BUILD_DIR"

echo "[🎉] UI build completed successfully!"
echo "Output directory: $BUILD_DIR"
echo "Log file: $LOG_FILE"
exit 0
