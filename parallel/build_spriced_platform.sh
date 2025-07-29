#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)" >&2' ERR

REPO="spriced-platform"
BRANCH="${1:-main}"
BASE_DIR="${2:-$HOME/projects}"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

LOG_DIR="$BASE_DIR/automationlogs"
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_DIR="$BASE_DIR/builds/$REPO/${BRANCH//\//_}_$DATE_TAG"
LATEST_LINK="$BASE_DIR/builds/$REPO/latest"

mkdir -p "$LOG_DIR" "$BUILD_DIR"

echo "🚀 Starting build for [$REPO] on branch [$BRANCH]..."

cd "$REPO_DIR"
echo "🔄 Fetching branch [$BRANCH] from origin..."
git fetch origin "$BRANCH"
git checkout "$BRANCH"
git reset --hard "origin/$BRANCH"

echo "🔧 Running Maven build..."
mvn clean install -DskipTests

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

ln -sfn "$BUILD_DIR" "$LATEST_LINK"
echo "✅ Build complete for [$REPO] on branch [$BRANCH]"
echo "🗂️ Artifacts: $BUILD_DIR"
