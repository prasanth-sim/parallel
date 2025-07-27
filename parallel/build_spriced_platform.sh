#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)" >&2' ERR

# === Config ===
REPO="spriced-platform"
BRANCH="${1:-main}"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

LOG_DIR="$HOME/automationlogs"
REPO_DIR="$HOME/projects/repos/$REPO"
BUILD_DIR="$HOME/projects/builds/$REPO/${BRANCH//\//_}_$DATE_TAG"
LATEST_LINK="$HOME/projects/builds/$REPO/latest"

mkdir -p "$LOG_DIR" "$BUILD_DIR"
LOG_FILE="$LOG_DIR/${REPO}_${DATE_TAG}.log"
exec &> >(tee -a "$LOG_FILE")

echo "🚀 Starting build for [$REPO] on branch [$BRANCH]..."

# === Git checkout ===
cd "$REPO_DIR"
echo "🔄 Fetching branch [$BRANCH] from origin..."
git fetch origin "$BRANCH"
git checkout "$BRANCH"
git reset --hard "origin/$BRANCH"

# === Maven Build ===
echo "🔧 Running Maven build..."
mvn clean install -DskipTests

# === Copy Artifacts ===
echo "📦 Copying build artifacts..."

declare -A ARTIFACTS=(
  ["spriced-platform"]="orchestratorRest,flinkRestImage"
)

IFS=',' read -ra MODULES <<< "${ARTIFACTS[$REPO]}"

for module in "${MODULES[@]}"; do
  MOD_PATH="$REPO_DIR/$module/target"

  if [[ ! -d "$MOD_PATH" ]]; then
    echo "⚠️ Target folder missing for module [$module], skipping..."
    continue
  fi

  echo "📦 Copying artifact for $module from [$MOD_PATH]..."
  JAR_FILES=$(find "$MOD_PATH" -maxdepth 1 -type f -name "*.jar" \
    ! -name "*original*" ! -name "*sources*" ! -name "*javadoc*" \
    | sort)

  if [[ -z "$JAR_FILES" ]]; then
    echo "⚠️ No valid JAR found in [$MOD_PATH]"
  else
    while IFS= read -r jar; do
      cp -p "$jar" "$BUILD_DIR/"
      echo "✅ Copied: $(basename "$jar")"
    done <<< "$JAR_FILES"
  fi
done

# === Update latest symlink
ln -sfn "$BUILD_DIR" "$LATEST_LINK"

echo "✅ Build complete for [$REPO] on branch [$BRANCH]"
echo "🗂️ Artifacts: $BUILD_DIR"
