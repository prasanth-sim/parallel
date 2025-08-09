kk#!/bin/bash
# Enable strict error checking and a trap to report errors
set -Eeuo pipefail
trap 'echo "[ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# === Inputs ===
BRANCH="${1:-main}"
BASE_DIR="${2:-$HOME/build-default}" # fallback if not passed
REPO="nrp-cummins-outbound"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

# === Derived Paths ===
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_DIR="$BASE_DIR/builds/$REPO/${BRANCH//\//_}_$DATE_TAG"
LATEST_LINK="$BASE_DIR/builds/$REPO/latest"
LOG_DIR="$BASE_DIR/automationlogs"
LOG_FILE="$LOG_DIR/${REPO}_${BRANCH//\//_}_$DATE_TAG.log"
GIT_URL="https://github.com/simaiserver/$REPO.git"

mkdir -p "$LOG_DIR" "$BUILD_DIR"

# Redirect all output to both log file and console
exec &> >(tee -a "$LOG_FILE")

echo "Starting build for [$REPO] on branch [$BRANCH]..."
echo "Timestamp: $DATE_TAG"

# === Git Clone or Pull ===
if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "Cloning repository from $GIT_URL..."
  git clone "$GIT_URL" "$REPO_DIR"
else
  echo "Repository already exists. Pulling latest..."
  git -C "$REPO_DIR" fetch origin
  git -C "$REPO_DIR" reset --hard "origin/$BRANCH"
fi

cd "$REPO_DIR"
echo "Checking out branch [$BRANCH]..."
git checkout "$BRANCH"
git reset --hard "origin/$BRANCH"

# === Maven Build ===
PARENT_MODULE="$REPO_DIR/spriced-client-cummins-outbound-parent"
echo "Building module: $PARENT_MODULE"
cd "$PARENT_MODULE"
# The maven.test.skip=true flag is used to skip tests
# It's important to build the parent module to build all child modules.
mvn clean install -Dmaven.test.skip=true

# === Define ARTIFACTS ===
# This associative array contains the modules we expect to find JARs for.
declare -A ARTIFACTS=(
  ["nrp-cummins-outbound"]="spriced-client-cummins-outbound-acknowledgement,spriced-client-cummins-outbound-basepricesap,spriced-client-cummins-outbound-ddc-uploadtosftp,spriced-client-cummins-outbound-erp-uploadtosftp,spriced-client-cummins-outbound-load-base-price,spriced-client-cummins-outbound-load-fixed-price,spriced-client-cummins-outbound-loadchannelintlow,spriced-client-cummins-outbound-loadimsrequest,spriced-client-cummins-outbound-loadpricelistauto,spriced-client-cummins-outbound-loadpricelistspecial,spriced-client-cummins-outbound-loadpricelistxrate,spriced-client-cummins-outbound-loadprimult,spriced-client-cummins-outbound-loadpvccodecreation,spriced-client-cummins-outbound-partsap,spriced-client-cummins-outbound-pvc,spriced-client-cummins-outbound-sap-uploadtosftp,spriced-client-cummins-outbound-upload-file-sftp,spriced-outbound-basepricesap-quarterly"
)

# === Copy Artifacts ===
echo "Copying JAR artifacts to: $BUILD_DIR"
IFS=',' read -ra MODULES <<< "${ARTIFACTS[$REPO]}"
for MODULE in "${MODULES[@]}"; do
  # Construct the specific path to the target directory for the current module.
  MOD_TARGET_DIR="$REPO_DIR/spriced-client-cummins-outbound-parent/$MODULE/target"

  # Check if the target directory exists before trying to find a JAR.
  # This prevents the script from reporting an error for modules that weren't built.
  if [[ -d "$MOD_TARGET_DIR" ]]; then
    # Search for the JAR file within the specific target directory
    JAR_PATH=$(find "$MOD_TARGET_DIR" -maxdepth 1 -type f -name "*.jar" ! -name "*-original-*" 2>/dev/null | head -n 1)
    if [[ -f "$JAR_PATH" ]]; then
      # -p flag ensures the permissions and timestamps are preserved
      cp -p "$JAR_PATH" "$BUILD_DIR/"
      echo "[SUCCESS] Copied: $(basename "$JAR_PATH")"
    else
      echo "[WARNING] Missing JAR file in [$MOD_TARGET_DIR] for module: $MODULE"
    fi
  else
    echo "[WARNING] Missing artifact for module: $MODULE (Target directory not found)"
  fi
done

# === Update latest symlink ===
# Creates or updates a symbolic link to the latest build directory
ln -snf "$BUILD_DIR" "$LATEST_LINK"

# === Summary ===
echo "[SUCCESS] Build complete for [$REPO] on branch [$BRANCH]"
echo "Artifacts stored at: $BUILD_DIR"
echo "Log saved at: $LOG_FILE"

