#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)" >&2; rm -rf "$BUILD_DIR"; exit 1' ERR

# === Script Arguments ===
CLIENT_BRANCH="${1:-main}"
BASE_DIR="${2:-$HOME/projects}"
BACKEND_BRANCH="${3:-main}" # This value now comes directly from main.sh

# === Path Definitions ===
REPO_NAME="spriced-client-cummins-parts-pricing"
REPO_URL="https://github.com/simaiserver/$REPO_NAME.git"
REPO_DIR="$BASE_DIR/repos/$REPO_NAME"

BACKEND_REPO_NAME="spriced-backend"
BACKEND_REPO_URL="https://github.com/simaiserver/$BACKEND_REPO_NAME.git"
BACKEND_REPO_DIR="$BASE_DIR/repos/$BACKEND_REPO_NAME"

BUILD_BASE="$BASE_DIR/builds/$REPO_NAME"
LOG_DIR="$BASE_DIR/automationlogs"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

BUILD_DIR="$BUILD_BASE/${CLIENT_BRANCH//\//_}_$DATE_TAG"
LOG_FILE="$LOG_DIR/${REPO_NAME}_${CLIENT_BRANCH//\//_}_$DATE_TAG.log"

# Create necessary directories
mkdir -p "$BUILD_DIR" "$LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "[ℹ️] Starting build for [$REPO_NAME] on branch [$CLIENT_BRANCH]..."
echo "DEBUG: BASE_DIR = '$BASE_DIR'"
echo "DEBUG: CLIENT_BRANCH = '$CLIENT_BRANCH'"
echo "DEBUG: BACKEND_BRANCH = '$BACKEND_BRANCH'" # Debug output for the backend branch

# === Handle spriced-backend dependency ===
echo "[⬇️] Checking and preparing [$BACKEND_REPO_NAME] repository..."
if [[ -d "$BACKEND_REPO_DIR/.git" ]]; then
  echo "🔄 Updating existing backend repo at $BACKEND_REPO_DIR"
  git -C "$BACKEND_REPO_DIR" fetch origin || { echo "❌ Failed to fetch updates for $BACKEND_REPO_NAME."; exit 1; }
  git -C "$BACKEND_REPO_DIR" reset --hard HEAD
  git -C "$BACKEND_REPO_DIR" clean -fd
  # Use the passed BACKEND_BRANCH for checkout
  if git -C "$BACKEND_REPO_DIR" rev-parse --verify "origin/$BACKEND_BRANCH" >/dev/null 2>&1; then
    git -C "$BACKEND_REPO_DIR" checkout -B "$BACKEND_BRANCH" "origin/$BACKEND_BRANCH" || { echo "❌ Failed to checkout backend branch $BACKEND_BRANCH."; exit 1; }
  else
    echo "❌ Remote branch origin/$BACKEND_BRANCH not found for $BACKEND_REPO_NAME. Cannot proceed."
    exit 1
  fi
else
  echo "📥 Cloning new backend repo from $BACKEND_REPO_URL into $BACKEND_REPO_DIR"
  [[ -d "$BACKEND_REPO_DIR" && ! -d "$BACKEND_REPO_DIR/.git" ]] && rm -rf "$BACKEND_REPO_DIR"
  git clone "$BACKEND_REPO_URL" "$BACKEND_REPO_DIR" || { echo "❌ Failed to clone $BACKEND_REPO_NAME."; exit 1; }
  git -C "$BACKEND_REPO_DIR" checkout -B "$BACKEND_BRANCH" "origin/$BACKEND_BRANCH" || { echo "❌ Failed to checkout backend branch $BACKEND_BRANCH after clone."; exit 1; }
fi

echo "DEBUG: Listing contents of $BACKEND_REPO_DIR after checkout:"
ls -l "$BACKEND_REPO_DIR" || true # Use || true to prevent script from exiting if ls fails

echo "[🛠️] Building required backend modules..."
BACKEND_MODULES=(
  "sim-spriced-api-client/sim-spriced-api-client-framework"
  "sim-spriced-notifications"
)

for module in "${BACKEND_MODULES[@]}"; do
  MODULE_PATH="$BACKEND_REPO_DIR/$module"
  if [[ -d "$MODULE_PATH" ]]; then
    echo "  -> Building backend module: $module"
    cd "$MODULE_PATH" || { echo "❌ Failed to change directory to $MODULE_PATH."; exit 1; }
    # Ensure mvnw is executable if it exists
    if [[ -f "./mvnw" ]]; then
        chmod +x ./mvnw
    fi
    ./mvnw clean install -Dmaven.test.skip=true || { echo "❌ Maven build failed for $module."; exit 1; }
    echo "  ✅ Module [$module] built successfully."
  else
    echo "  [⚠️] Backend module path not found: $MODULE_PATH. Skipping build for this module."
  fi
done

# Return to the main client repository directory before building it
cd "$REPO_DIR" || { echo "❌ Failed to return to client repo directory $REPO_DIR."; exit 1; }

# === Git operations for spriced-client-cummins-parts-pricing ===
echo "[⬇️] Checking and preparing [$REPO_NAME] repository..."
git reset --hard || { echo "❌ Failed to reset client repo."; exit 1; }
git fetch origin || { echo "❌ Failed to fetch updates for client repo."; exit 1; }
if git rev-parse --verify "origin/$CLIENT_BRANCH" >/dev/null 2>&1; then
  git checkout "$CLIENT_BRANCH" || { echo "❌ Failed to checkout client branch $CLIENT_BRANCH."; exit 1; }
  git pull origin "$CLIENT_BRANCH" || { echo "❌ Failed to pull client branch $CLIENT_BRANCH."; exit 1; }
else
  echo "❌ Remote branch origin/$CLIENT_BRANCH not found for $REPO_NAME. Cannot proceed."
  exit 1
fi
GIT_COMMIT=$(git rev-parse HEAD)
echo "[📌] Git commit used for $REPO_NAME: $GIT_COMMIT"


# === Maven build for spriced-client-cummins-parts-pricing ===
echo "🛠️ Running Maven build for [$REPO_NAME]..."
# Ensure mvnw is executable if it exists
if [[ -f "./mvnw" ]]; then
    chmod +x ./mvnw
fi
./mvnw clean install -Dmaven.test.skip=true || { echo "❌ Maven build failed for $REPO_NAME."; exit 1; }

# === Copy JAR ===
echo "[📦] Copying JAR artifact..."
JAR_PATH=$(find "$REPO_DIR/target" -name "*.jar" ! -name "*original*" | head -n1)
echo "DEBUG: Found JAR_PATH = '$JAR_PATH'"
if [[ -f "$JAR_PATH" ]]; then
  cp -p "$JAR_PATH" "$BUILD_DIR/" || { echo "❌ Failed to copy JAR."; exit 1; }
  echo "✅ Copied JAR: $(basename "$JAR_PATH") to $BUILD_DIR"
else
  echo "⚠️ No JAR found to copy for $REPO_NAME."
fi

# === Done ===
ln -snf "$BUILD_DIR" "$BUILD_BASE/latest"
echo "✅ Build completed at [$DATE_TAG]"
echo "📁 Artifacts in: $BUILD_DIR"
echo "📝 Log:    $LOG_FILE"
exit 0
