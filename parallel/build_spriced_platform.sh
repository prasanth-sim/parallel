#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)" >&2' ERR

# === Configuration ===
REPO="spriced-platform"
BRANCH="${1:-main}"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

# Paths
LOG_DIR="$HOME/automationlogs"
REPO_DIR="$HOME/projects/repos/$REPO"
BUILD_BASE="$HOME/projects/builds/$REPO"
BUILD_DIR="$BUILD_BASE/${BRANCH//\//_}_$DATE_TAG"
LATEST_LINK="$BUILD_BASE/latest"

# Artifact Modules by Repo
declare -A ARTIFACTS=(
  ["spriced-platform"]="orchestratorRest,flinkRestImage"
)

mkdir -p "$LOG_DIR" "$BUILD_DIR"
LOG_FILE="$LOG_DIR/${REPO}_${DATE_TAG}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "🚀 Starting build for [$REPO] on branch [$BRANCH]..."

# === Clone Fresh Repository ===
if [[ -d "$REPO_DIR" ]]; then
  echo "🧹 Removing existing repository directory: $REPO_DIR"
  rm -rf "$REPO_DIR"
fi

echo "🔽 Cloning repository from GitHub..."
git clone "https://github.com/simaiserver/$REPO.git" "$REPO_DIR"
cd "$REPO_DIR"

# === Fetch and Checkout Branch ===
echo "🔄 Fetching branch [$BRANCH] from origin..."
git fetch origin

if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  echo "✅ Branch [$BRANCH] exists. Checking out..."
  git checkout -B "$BRANCH" "origin/$BRANCH"
else
  echo "[❌ ERROR] Branch [$BRANCH] not found in remote."
  echo "🔍 Searching for similar branches..."
  SIMILAR=$(git branch -r | sed 's|origin/||' | grep -i "$BRANCH" || true)
  if [[ -n "$SIMILAR" ]]; then
    echo "🔎 Similar branches found:"
    echo "$SIMILAR"
  else
    echo "❗ No similar branches found. Exiting."
  fi
  exit 1
fi

# === Full Maven Build (optional) ===
echo "🧱 Running full Maven build (skip tests)..."
mvn clean install -Dmaven.test.skip=true

# === Determine modules from ARTIFACTS array ===
IFS=',' read -ra MODULES <<< "${ARTIFACTS[$REPO]}"

# === Build Specific Modules and Copy JARs ===
for module in "${MODULES[@]}"; do
  MODULE_PATH="$REPO_DIR/$module"
  if [[ -d "$MODULE_PATH" ]]; then
    echo "⚙️ Building module: $module"
    cd "$MODULE_PATH"
    mvn clean install -Dmaven.test.skip=true

    echo "📦 Searching JAR in: $MODULE_PATH/target/"
    ARTIFACT=$(find target/ -maxdepth 1 -type f -name "*.jar" ! -name "*sources*" ! -name "*javadoc*" | head -n1)
    if [[ -f "$ARTIFACT" ]]; then
      cp -p "$ARTIFACT" "$BUILD_DIR/"
      echo "✅ Copied: $(basename "$ARTIFACT")"
    else
      echo "⚠️ No artifact found for $module"
    fi
  else
    echo "⚠️ Module directory not found: $module"
  fi
done

# === Update Symlink to Latest ===
echo "🔗 Updating 'latest' symlink..."
ln -sfn "$BUILD_DIR" "$LATEST_LINK"

# === Completion ===
echo "✅ Build complete for [$REPO] on branch [$BRANCH]"
echo "📁 Artifacts available at: $BUILD_DIR"
echo "🔗 Latest symlink points to: $LATEST_LINK"
