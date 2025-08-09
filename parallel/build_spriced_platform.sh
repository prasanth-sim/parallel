#!/bin/bash
# Enable strict error checking and a trap to report errors
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)" >&2' ERR

# --- Script Configuration ---
REPO="spriced-platform"
BRANCH="${1:-main}"
BASE_DIR="${2:-$HOME/projects}"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

# --- Directory Paths ---
LOG_DIR="$BASE_DIR/automationlogs"
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_DIR="$BASE_DIR/builds/$REPO/${BRANCH//\//_}_$DATE_TAG"
LATEST_LINK="$BASE_DIR/builds/$REPO/latest"

# Create necessary directories
mkdir -p "$LOG_DIR" "$BUILD_DIR"

echo "🚀 Starting build for [$REPO] on branch [$BRANCH]..."

# --- Git Operations ---
cd "$REPO_DIR"
echo "🔄 Fetching branch [$BRANCH] from origin..."
git fetch origin "$BRANCH"
git checkout "$BRANCH"
git reset --hard "origin/$BRANCH"

# --- Maven Build per Module ---
echo "🔧 Running Maven build for specified modules..."

# Declare an associative array to map repos to their modules
declare -A ARTIFACTS=(
  ["spriced-platform"]="orchestratorRest,flinkRestImage"
)

# Split the modules string into an array
IFS=',' read -ra MODULES <<< "${ARTIFACTS[$REPO]}"

# Loop through each module and run the Maven build command
for module in "${MODULES[@]}"; do
  echo "--- Building module: [$module] ---"
  # Change into the module's directory
  cd "$REPO_DIR/$module"
  # Run the Maven build for this specific module
  mvn clean install -DskipTests
  # Change back to the repository root for subsequent commands
  cd "$REPO_DIR"
done

# --- Artifact Copying ---
echo "📦 Copying build artifacts..."
# This part remains the same, it iterates through the modules again
# and copies the final JAR files to the build directory.

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
      # cp command no longer uses the -p flag to update timestamp
      cp "$jar" "$BUILD_DIR/"
      echo "✅ Copied: $(basename "$jar")"
    done <<< "$JAR_FILES"
  fi
done

# --- Final Steps ---
# Create a symbolic link to the latest build directory
ln -sfn "$BUILD_DIR" "$LATEST_LINK"
echo "✅ Build complete for [$REPO] on branch [$BRANCH]"
echo "🗂️ Artifacts: $BUILD_DIR"
