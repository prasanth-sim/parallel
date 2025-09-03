#!/bin/bash
set -Eeuo pipefail
trap 'echo "[ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# === INPUT ARGUMENTS ===
# The first argument is the branch name, defaulting to 'main'.
BRANCH="${1:-main}"
# The second argument is the base directory, defaulting to '$HOME/projects'.
BASE_DIR="${2:-$HOME/projects}"
REPO="spriced-client-cummins-data-ingestion"

# Create a timestamp for unique log and build directories.
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

# === Dynamic Paths ===
# Define the repository, build, and log directories based on the base path.
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_BASE="$BASE_DIR/builds/$REPO"
LOG_DIR="$BASE_DIR/automationlogs"

# Create the necessary directories if they don't already exist.
mkdir -p "$REPO_DIR" "$BUILD_BASE" "$LOG_DIR"

# Set up logging: all script output will be both displayed on the console and written to a log file.
LOG_FILE="$LOG_DIR/${REPO//\//-}_${BRANCH}_${DATE_TAG}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "--- Starting build for [$REPO] on branch [$BRANCH] at $(date) ---"

# === Clone or Update Repository ===
if [[ -d "$REPO_DIR/.git" ]]; then
    echo "Updating existing repo at $REPO_DIR"
    # Navigate to the repository directory.
    cd "$REPO_DIR"
    # Fetch all remote branches and prune any that no longer exist.
    git fetch origin --prune
    # The -B flag ensures we create/reset the branch to the remote branch, which is a safer operation.
    git checkout -B "$BRANCH" "origin/$BRANCH"
    # Pull any latest changes from the remote branch.
    git pull origin "$BRANCH"
else
    echo "Cloning repo to $REPO_DIR"
    # Clone the repository and immediately switch to the desired branch.
    git clone "https://github.com/simaiserver/$REPO.git" "$REPO_DIR"
    cd "$REPO_DIR"
    git checkout "$BRANCH"
fi

# === Build Project ===
echo "Running Maven build..."
# Execute the Maven build. The '-Dmaven.test.skip=true' flag skips the tests.
if ! mvn clean install -Dmaven.test.skip=true; then
    echo "[ERROR] Maven build failed. See log file for details."
    exit 1
fi

# === Artifact Copy ===
# Create a new, timestamped directory for the build artifacts.
BUILD_DIR="$BUILD_BASE/${BRANCH}_${DATE_TAG}"
mkdir -p "$BUILD_DIR"

echo "Searching and copying built JARs to [$BUILD_DIR]..."
# Find all JAR files in the 'target' subdirectories, excluding 'original' JARs.
# '|| true' prevents the script from exiting if no files are found.
FOUND_JARS=$(find "$REPO_DIR" -type f -path "*/target/*.jar" ! -name "*original*" || true)

if [[ -z "$FOUND_JARS" ]]; then
    echo "No usable JARs found in $REPO_DIR"
else
    # Loop through the found JARs and copy them to the build directory.
    echo "$FOUND_JARS" | while read -r JAR_PATH; do
        echo "Copying: $JAR_PATH"
        cp -p "$JAR_PATH" "$BUILD_DIR/"
    done
fi

# === Update 'latest' Symlink ===
echo "Updating 'latest' symlink..."
# Create a symbolic link pointing to the most recent build directory.
# The '-sfn' flags ensure it's a symbolic link, and it forces a new link even if one exists.
ln -sfn "$BUILD_DIR" "$BUILD_BASE/latest"

# === Done ===
echo "--- Build complete for [$REPO] on branch [$BRANCH] at $(date) ---"
echo "Artifacts stored at: $BUILD_DIR"
echo "Latest symlink: $BUILD_BASE/latest"
