#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)" >&2; rm -rf "$BUILD_DIR"; exit 1' ERR

ENV="${1:-}"
BRANCH="${2:-main}"
BASE_DIR="${3:-$HOME/projects}"  # Accept from main script

VALID_ENVS=("dev" "qa" "test")
if [[ ! " ${VALID_ENVS[*]} " =~ " ${ENV} " ]]; then
  echo "❌ Invalid environment: '$ENV'. Use one of: ${VALID_ENVS[*]}"
  exit 1
fi

command -v npx >/dev/null || { echo "❌ 'npx' not found. Install Node.js first."; exit 1; }

REPO="spriced-ui"
REPO_URL="https://github.com/simaiserver/$REPO.git"
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_ROOT="$BASE_DIR/builds/$REPO/$ENV/latest"
LOG_DIR="$BASE_DIR/automationlogs"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BUILD_DIR="$BUILD_ROOT/${BRANCH}_${TIMESTAMP}"
LOG_FILE="$LOG_DIR/${REPO}_${ENV}_${BRANCH}_${TIMESTAMP}.log"

CONFIG_PIPELINE_BASE="$BASE_DIR/spriced-pipeline/framework/frontend/nrp-$ENV"
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
echo "[ℹ️] Starting UI build for ENV='$ENV', BRANCH='$BRANCH' at $TIMESTAMP"

# Clone or update repo
if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "[⬇️] Cloning $REPO..."
  git clone "$REPO_URL" "$REPO_DIR"
else
  echo "[📦] Repo exists. Fetching updates..."
  git -C "$REPO_DIR" fetch origin
fi

cd "$REPO_DIR"
git checkout "$BRANCH"
git reset --hard "origin/$BRANCH"
GIT_COMMIT=$(git rev-parse HEAD)
echo "[📌] Git commit used: $GIT_COMMIT"

# Inject .env files
echo "[🔧] Injecting environment files..."
for mf in "${MICROFRONTENDS[@]}"; do
  SRC_ENV_FILE="$CONFIG_PIPELINE_BASE/$mf.env"
  DEST_DIR="$REPO_DIR/apps/$mf"
  DEST_ENV_FILE="$DEST_DIR/.env"

  if [[ ! -f "$SRC_ENV_FILE" ]]; then
    echo "[⚠️] Missing env: $SRC_ENV_FILE"
    continue
  fi

  mkdir -p "$DEST_DIR"
  [[ -f "$DEST_ENV_FILE" ]] && cp "$DEST_ENV_FILE" "$DEST_ENV_FILE.bak.$(date +%s)"
  cp "$SRC_ENV_FILE" "$DEST_ENV_FILE"
  echo "[✅] Applied env for $mf"
done

# Install node_modules
if [ ! -d "node_modules" ]; then
  echo "[🧩] Installing node modules..."
  npm install
fi

# Build using Nx
echo "[🏗️] Building projects..."
rm -rf dist/
npx nx run-many --target=build --projects=$(IFS=,; echo "${MICROFRONTENDS[*]}")

# Copy artifacts
echo "[📂] Copying output to $BUILD_DIR"
for APP_DIR in dist/apps/*; do
  APP_NAME=$(basename "$APP_DIR")
  TARGET_DIR="$BUILD_DIR/$APP_NAME"
  mkdir -p "$TARGET_DIR"
  cp -r "$APP_DIR/"* "$TARGET_DIR/"

  ENV_FILE="$CONFIG_PIPELINE_BASE/$APP_NAME/.env"
  [[ -f "$ENV_FILE" ]] && cp "$ENV_FILE" "$TARGET_DIR/.env"
done

# Copy manifest
if [[ -f "$MANIFEST_SOURCE" ]]; then
  cp "$MANIFEST_SOURCE" "$BUILD_DIR/module-federation.manifest.json"
  echo "[📜] Manifest copied"
else
  echo "[❌] Manifest not found at $MANIFEST_SOURCE"
  exit 1
fi

echo "[✅] Build complete!"
echo "📁 Output: $BUILD_DIR"
echo "📝 Log:    $LOG_FILE"
exit 0
