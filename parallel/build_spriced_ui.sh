#!/bin/bash
set -Eeuo pipefail

# Trap command that removes the build directory on script failure.
trap 'if [ -d "$BUILD_DIR" ]; then rm -rf "$BUILD_DIR"; echo "[❌ CLEANUP] Removed temporary build directory: $BUILD_DIR"; fi; exit 1' ERR

# === Script Arguments ===
# ENV: Environment name (e.g., dev, qa, prasanth) or full URL
ENV="${1:-}"
# BRANCH: Git branch to checkout
BRANCH="${2:-main}"
# URL_SEPARATOR: The character to use for the URL separator ('-' or '.')
URL_SEPARATOR="${3:-.}"
# BASE_DIR: Base directory for repos, builds, and logs
BASE_DIR="${4:-$HOME/automation_workspace}"

# === Input Validation ===
if [[ -z "$ENV" || -z "$BRANCH" || -z "$BASE_DIR" ]]; then
    echo " Missing required arguments. Usage: $0 <ENV> <BRANCH> <URL_SEPARATOR> <BASE_DIR>"
    exit 1
fi

# Check for npx command
command -v npx >/dev/null || { echo " 'npx' not found. Install Node.js first."; exit 1; }

# === Path Definitions ===
REPO="spriced-ui"
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_OUTPUT_ROOT_DIR="$BASE_DIR/builds/$REPO/$ENV"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BUILD_DIR="$BUILD_OUTPUT_ROOT_DIR/$TIMESTAMP"
# Determine the pipeline configuration directory
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

# === Script Execution Start ===
echo "Starting UI build for ENV='$ENV', BRANCH='$BRANCH'..."
echo "Build directory: $BUILD_DIR"

# Step 1: Prepare the repository
echo " Preparing '$REPO' repository..."
if [[ ! -d "$REPO_DIR/.git" ]]; then
    echo "  - Cloning from https://github.com/simaiserver/$REPO.git"
    git clone "https://github.com/simaiserver/$REPO.git" "$REPO_DIR"
fi
cd "$REPO_DIR"
git fetch origin
echo "  - Checking out branch: $BRANCH"
git checkout "$BRANCH"
git reset --hard "origin/$BRANCH"

# Step 2: Inject .env files for the build process
echo " Injecting environment files from spriced-pipeline into repository..."
# Check if the environment is a full URL or a standard name
if [[ "$ENV" =~ ^https?:\/\/.*simadvisory\.com$ ]]; then
    # Use 'dev' as the source for .env files when a full URL is provided
    SOURCE_ENV_DIR="$CONFIG_PIPELINE_BASE/nrp-dev"
else
    # Use the provided environment name for the source directory
    SOURCE_ENV_DIR="$CONFIG_PIPELINE_BASE/nrp-$ENV"
fi
if [ ! -d "$SOURCE_ENV_DIR" ]; then
    echo " Missing environment configuration directory: $SOURCE_ENV_DIR"
    exit 1
fi
for mf in "${MICROFRONTENDS[@]}"; do
    SRC_ENV_FILE="$SOURCE_ENV_DIR/$mf/.env"
    DEST_ENV_FILE="$REPO_DIR/apps/$mf/.env"
    if [[ -f "$SRC_ENV_FILE" ]]; then
        mkdir -p "$(dirname "$DEST_ENV_FILE")"
        cp "$SRC_ENV_FILE" "$DEST_ENV_FILE"
        echo "  - Applied env for '$mf' from '$SOURCE_ENV_DIR'."
    else
        echo "  - Missing .env for '$mf': $SRC_ENV_FILE. Skipping."
    fi
done

# Step 3: Install Node dependencies
echo "Installing Node dependencies..."
npm install

# Step 4: Build projects using Nx
echo "Building projects with Nx..."
rm -rf dist/
npx nx run-many --target=build --projects=$(IFS=,; echo "${MICROFRONTENDS[*]}") --configuration=production

# Step 5: Copy build artifacts and update URLs
echo " Copying build artifacts and updating URLs..."
mkdir -p "$BUILD_DIR"
if [ ! -d "$REPO_DIR/dist/apps" ]; then
    echo " Nx build output not found. The build may have failed."
    exit 1
fi
# Copy all the built applications
cp -r "$REPO_DIR/dist/apps/"* "$BUILD_DIR/"

# Copy .env files to the final build directory and update URLs
echo " Copying and updating .env files to final build directory..."
for mf in "${MICROFRONTENDS[@]}"; do
    DEST_ENV_DIR="$BUILD_DIR/$mf"
    mkdir -p "$DEST_ENV_DIR"
    cp "$REPO_DIR/apps/$mf/.env" "$DEST_ENV_DIR/"
done

# Determine the new URL based on user input for .env files
if [[ "$ENV" =~ ^https?:\/\/.*simadvisory\.com$ ]]; then
    NEW_URL_BASE=$(echo "$ENV" | sed -E 's#https?://(.*)#\1#')
    # Updated regex to match any subdomain under simadvisory.com, not just 'nrp'.
    REPLACE_REGEX="s#(https?|wss?)://[^/]+\.simadvisory\.com#\1://${NEW_URL_BASE}#g"
else
    # The replacement logic for non-URL environments remains specific to the 'nrp' subdomain.
    if [[ "$URL_SEPARATOR" == "-" ]]; then
        REPLACE_REGEX="s#(https?|wss?)://nrp[-.]?[^.]*\.simadvisory\.com#\1://nrp-${ENV}.alpha.simadvisory.com#g"
    else
        REPLACE_REGEX="s#(https?|wss?)://nrp[-.]?[^.]*\.simadvisory\.com#\1://nrp.${ENV}.simadvisory.com#g"
    fi
fi

# Process and update URLs in the .env files in the final build directory
echo " Processing and updating URLs in .env files in final build directories..."
for mf in "${MICROFRONTENDS[@]}"; do
    DEST_ENV_FILE="$BUILD_DIR/$mf/.env"
    if [[ -f "$DEST_ENV_FILE" ]]; then
        # This sed command applies the new regex to all lines except the one containing NX_KEY_CLOAK_URL
        sed -i -E "/NX_KEY_CLOAK_URL/!${REPLACE_REGEX}" "$DEST_ENV_FILE"
        echo "  - Processed and updated URLs in .env for '$mf'."
    else
        echo "  - .env file not found for '$mf'. Skipping URL update."
    fi
done

# === UPDATED LOGIC FOR MANIFEST FILE ===
# Copy the manifest file without changing its content.
echo " Copying manifest file without modification..."
MANIFEST_SOURCE="$SOURCE_ENV_DIR/module-federation.manifest.json"
cp "$MANIFEST_SOURCE" "$BUILD_DIR/module-federation.manifest.json"
echo "  - Manifest copied to build directory."

# Create a symlink to the latest build
LATEST_LINK="$BUILD_OUTPUT_ROOT_DIR/latest"
if [ -e "$LATEST_LINK" ]; then
    rm "$LATEST_LINK"
fi
ln -s "$BUILD_DIR" "$LATEST_LINK"

echo " Build of spriced-ui completed successfully."
echo "Final build output available at: $BUILD_DIR"
echo "Symbolic link 'latest' created at: $LATEST_LINK"
exit 0

