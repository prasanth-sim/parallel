#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -Eeuo pipefail

# Trap a command that fails and print an error message.
trap 'echo "[ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# === Script Arguments ===
# REPO_BRANCH: The git branch to checkout for spriced-ui
REPO_BRANCH="${1:-main}"
# UI_ENV: The environment name (e.g., dev, prasanth) or a full URL
UI_ENV="${2:-dev}"
# URL_SEPARATOR: The character for URL separation ('-' or '.')
URL_SEPARATOR="${3:-.}"
# BASE_DIR: Base directory for repos, builds, and logs
BASE_DIR="${4:-$HOME/automation_worklogs}"

# === Input Validation ===
if [[ -z "$REPO_BRANCH" || -z "$UI_ENV" || -z "$URL_SEPARATOR" || -z "$BASE_DIR" ]]; then
    echo "Missing required arguments."
    echo "Usage: $0 <REPO_BRANCH> <UI_ENV> <URL_SEPARATOR> <BASE_DIR>"
    exit 1
fi

# Check for required commands
command -v npm >/dev/null || { echo "'npm' not found. Please install Node.js."; exit 1; }
command -v npx >/dev/null || { echo "'npx' not found. Please install Node.js."; exit 1; }
command -v git >/dev/null || { echo "'git' not found. Please install Git."; exit 1; }

# === Path Definitions ===
REPO_NAME="spriced-ui"
REPO_DIR="$BASE_DIR/repos/$REPO_NAME"
# The build output directory is structured by the environment and branch.
BUILD_OUTPUT_DIR="$BASE_DIR/builds/$REPO_NAME/$UI_ENV/$REPO_BRANCH/latest"
PIPELINE_DIR="$BASE_DIR/spriced-pipeline"
CONFIG_PIPELINE_BASE="$PIPELINE_DIR/framework/frontend"

# List of microfrontends
MICROFRONTENDS=(
    "spriced-container"
    "spriced-data"
    "spriced-data-definition"
    "spriced-reports"
    "spriced-user-management"
)

# === Main Execution ===

# Step 1: Prepare the repository
echo "--- Preparing '$REPO_NAME' repository... ---"
if [[ ! -d "$REPO_DIR/.git" ]]; then
    echo "Cloning repository..."
    git clone "https://github.com/simaiserver/$REPO_NAME.git" "$REPO_DIR" || { echo "Failed to clone repository."; exit 1; }
fi

# Add a backup and restore mechanism before git checkout.
BACKUP_DIR="/tmp/spriced_ui_backup_$(date +%Y%m%d_%H%M%S)"
MANIFEST_FILE_TO_BACKUP="$REPO_DIR/apps/spriced-container/src/assets/module-federation.manifest.json"
echo "--- Backing up temporary files before branch switch... ---"
mkdir -p "$BACKUP_DIR"
if [ -f "$MANIFEST_FILE_TO_BACKUP" ]; then
    mv "$MANIFEST_FILE_TO_BACKUP" "$BACKUP_DIR/"
    echo "Backed up manifest file to $BACKUP_DIR."
fi

# Now perform the checkout
cd "$REPO_DIR"
echo "Fetching latest changes and checking out branch: $REPO_BRANCH"
git fetch origin
if git rev-parse --verify "origin/$REPO_BRANCH" >/dev/null 2>&1; then
    git checkout "$REPO_BRANCH"
    git reset --hard "origin/$REPO_BRANCH"
else
    echo "Remote branch 'origin/$REPO_BRANCH' not found. Exiting."
    exit 1
fi

# Restore the backed up manifest file after the checkout
echo "--- Restoring backed up files... ---"
if [ -f "$BACKUP_DIR/module-federation.manifest.json" ]; then
    mkdir -p "$(dirname "$MANIFEST_FILE_TO_BACKUP")"
    mv "$BACKUP_DIR/module-federation.manifest.json" "$MANIFEST_FILE_TO_BACKUP"
    echo "Restored manifest file from $BACKUP_DIR."
fi
rmdir "$BACKUP_DIR" # Clean up the backup directory

# Step 2: Inject .env files from the spriced-pipeline based on the chosen environment
echo "--- Injecting .env and manifest files from spriced-pipeline... ---"
SOURCE_ENV_DIR="$CONFIG_PIPELINE_BASE/nrp-dev" # Always use 'dev' as the base template

# Copy the environment-specific manifest file
MANIFEST_SOURCE_FILE="$SOURCE_ENV_DIR/module-federation.manifest.json"
MANIFEST_DEST_FILE="$REPO_DIR/apps/spriced-container/src/assets/module-federation.manifest.json"

if [ ! -f "$MANIFEST_SOURCE_FILE" ]; then
    echo "Error: Manifest file not found at '$MANIFEST_SOURCE_FILE'. Cannot proceed."
    exit 1
fi
mkdir -p "$(dirname "$MANIFEST_DEST_FILE")"
cp "$MANIFEST_SOURCE_FILE" "$MANIFEST_DEST_FILE"
echo "Successfully copied manifest file."

# Copy the .env files
for mf in "${MICROFRONTENDS[@]}"; do
    SRC_ENV_FILE="$SOURCE_ENV_DIR/$mf/.env"
    DEST_ENV_FILE="$REPO_DIR/apps/$mf/.env"
    if [[ -f "$SRC_ENV_FILE" ]]; then
        cp "$SRC_ENV_FILE" "$DEST_ENV_FILE"
        echo "Successfully copied .env for '$mf'."
    else
        echo "Warning: Missing .env for '$mf' at '$SRC_ENV_FILE'. Skipping."
    fi
done

# Perform URL replacement for all environments EXCEPT 'dev'
if [[ "$UI_ENV" != "dev" ]]; then
    echo "--- Updating .env files with new URLs for environment: $UI_ENV ---"
    
    # OLD URLS to be replaced
    OLD_NRP_URL="https://nrp.dev.simadvisory.com"
    OLD_REPORTS_URL="https://reports.spriced.dev.simadvisory.com"
    OLD_WS_URL="wss://nrp.dev.simadvisory.com"

    # Construct NEW URLs based on the UI_ENV and URL_SEPARATOR
    NEW_NRP_URL="https://nrp${URL_SEPARATOR}${UI_ENV}.simadvisory.com"
    NEW_REPORTS_URL="https://reports${URL_SEPARATOR}spriced${URL_SEPARATOR}${UI_ENV}.simadvisory.com"
    NEW_WS_URL="wss://nrp${URL_SEPARATOR}${UI_ENV}.simadvisory.com"
    
    # Iterate through all .env files and replace the URLs
    for mf in "${MICROFRONTENDS[@]}"; do
        ENV_FILE="$REPO_DIR/apps/$mf/.env"
        if [[ -f "$ENV_FILE" ]]; then
            # Use sed to perform multiple replacements in a single command for efficiency
            sed -i \
                -e "s|${OLD_NRP_URL}|${NEW_NRP_URL}|g" \
                -e "s|${OLD_REPORTS_URL}|${NEW_REPORTS_URL}|g" \
                -e "s|${OLD_WS_URL}|${NEW_WS_URL}|g" \
                "$ENV_FILE"
            echo "Successfully updated URLs in .env for '$mf'."
        fi
    done
fi

# Step 3: Install Node dependencies
echo "--- Installing Node dependencies... ---"
npm install --quiet

# Step 4: Build projects using Nx
echo "--- Building projects with Nx... ---"
rm -rf dist/
npx nx run-many --target=build --projects=$(IFS=,; echo "${MICROFRONTENDS[*]}") --configuration=production

# Step 5: Copy build artifacts to the final destination
echo "--- Copying build artifacts to final destination... ---"
# Clean up any previous builds
if [ -d "$BUILD_OUTPUT_DIR" ]; then
    rm -rf "$BUILD_OUTPUT_DIR"
    echo "Removed old build directory."
fi
mkdir -p "$BUILD_OUTPUT_DIR"

if [ ! -d "$REPO_DIR/dist/apps" ]; then
    echo "Build artifacts not found at '$REPO_DIR/dist/apps'. Build failed."
    exit 1
fi

cp -r "$REPO_DIR/dist/apps/." "$BUILD_OUTPUT_DIR/"
echo "Successfully copied all build artifacts to '$BUILD_OUTPUT_DIR'."

echo "--- Build process for spriced-ui completed successfully! ---"
