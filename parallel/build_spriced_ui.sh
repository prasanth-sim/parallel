#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)" >&2' ERR

ENV="${1:-}"
BRANCH="${2:-main}"

VALID_ENVS=("dev" "qa" "test")
if [[ ! " ${VALID_ENVS[*]} " =~ " ${ENV} " ]]; then
  echo "❌ Invalid environment: '$ENV'. Use one of: ${VALID_ENVS[*]}"
  exit 1
fi

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
REPO="spriced-ui"
REPO_URL="https://github.com/simaiserver/$REPO.git"

BASE_DIR="$HOME/projects"
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_DIR="$BASE_DIR/builds/$REPO/$ENV"
LOG_DIR="$HOME/automationlogs"
LOG_FILE="$LOG_DIR/${REPO}_${ENV}_${TIMESTAMP}.log"

# Path to your frontend microservices repo containing env files and manifest
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

# Clone or update repo
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

# Inject .env files into each microfrontend folder
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

  # Backup old .env if exists
  if [[ -f "$DEST_ENV_FILE" ]]; then
    cp "$DEST_ENV_FILE" "$DEST_ENV_FILE.bak.$(date +%s)"
    echo "[🔁] Backup created for $DEST_ENV_FILE"
  fi

  cp "$SRC_ENV_FILE" "$DEST_ENV_FILE"
  echo "[✅] Copied $SRC_ENV_FILE to $DEST_ENV_FILE"
done

# Build all apps with Nx
echo "[🏗️] Running Nx build for all apps..."
rm -rf dist/
npx nx run-many --target=build --all

# Copy build output and .env files to build dir
echo "[📦] Copying build output to $BUILD_DIR..."
rm -rf "$BUILD_DIR"/*
for APP_DIR in dist/apps/*; do
  APP_NAME=$(basename "$APP_DIR")
  mkdir -p "$BUILD_DIR/$APP_NAME"
  cp -r "$APP_DIR/"* "$BUILD_DIR/$APP_NAME/"
  echo "[🔄] Copied build output for $APP_NAME"

  SRC_ENV_FILE="$CONFIG_PIPELINE_BASE/$APP_NAME/.env"
  if [[ -f "$SRC_ENV_FILE" ]]; then
    cp "$SRC_ENV_FILE" "$BUILD_DIR/$APP_NAME/.env"
    echo "[📥] Copied .env for $APP_NAME to build output"
  else
    echo "[⚠️] No .env found for $APP_NAME to copy"
  fi
done

# Copy manifest file
if [[ -f "$MANIFEST_SOURCE" ]]; then
  cp "$MANIFEST_SOURCE" "$BUILD_DIR/module-federation.manifest.json"
  echo "[✅] Copied manifest file to build output"
else
  echo "[❌] Manifest file not found at $MANIFEST_SOURCE"
  exit 1
fi

echo "[🎉] UI build completed successfully!"
echo "Output directory: $BUILD_DIR"
echo "Log file: $LOG_FILE"
