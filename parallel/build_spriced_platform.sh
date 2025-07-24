#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)" >&2' ERR

# === Config ===
REPO="spriced-platform"
BRANCH="${1:-main}"  # Accept branch from input
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

LOG_DIR="$HOME/automationlogs"
REPO_DIR="$HOME/projects/repos/$REPO"
BUILD_ROOT="$HOME/projects/builds/$REPO"
BUILD_DIR="$BUILD_ROOT/${BRANCH}_${DATE_TAG}"
LATEST_LINK="$BUILD_ROOT/latest"

mkdir -p "$LOG_DIR" "$BUILD_DIR"

LOG_FILE="$LOG_DIR/${REPO}_${DATE_TAG}.log"

# === Logging Setup ===
exec > >(tee "$LOG_FILE") 2>&1
echo "📦 Starting build for [$REPO] on branch [$BRANCH]..."

# === Clone if not present ===
if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "📥 Cloning $REPO..."
  git clone "https://github.com/simaiserver/$REPO.git" "$REPO_DIR"
fi

cd "$REPO_DIR"
git fetch origin
git checkout "$BRANCH"
git pull origin "$BRANCH"

# === Build Root Project ===
echo "🔧 Building root project..."
mvn clean install -Dmaven.test.skip=true

# === Build Submodules ===
declare -A SUBMODULES=(
  ["orchestratorRest"]="flink_rest_integration"
  ["flinkRestImage"]="MyFlinkImage"
)

for mod in orchestratorRest flinkRestImage; do
  mod_path="$REPO_DIR/$mod"
  [[ -d "$mod_path" ]] && {
    echo "🔧 Building submodule: $mod"
    cd "$mod_path"
    mvn clean install -Dmaven.test.skip=true
    find target/ -type f -name "*.jar" ! -name "*original*" -exec cp -p {} "$BUILD_DIR/" \;
  }
done

# === Create/Update Symlink ===
ln -sfn "$BUILD_DIR" "$LATEST_LINK"

# === Final Output ===
echo "✅ Build complete for [$REPO] on branch [$BRANCH]"
echo "🗂️ Artifacts: $LATEST_LINK"
