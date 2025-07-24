#!/bin/bash
set -Eeuo pipefail
trap 'echo "[ERROR] Line $LINENO: $BASH_COMMAND (exit $?)" >&2' ERR

# === Setup ===
repo="nrp-cummins-outbound"
branch="${1:-main}"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="$HOME/automationlogs"
REPO_DIR="$HOME/projects/repos/$repo"
BUILD_DIR="$HOME/projects/builds/$repo/${branch//\//_}_$DATE_TAG"
LATEST_LINK="$HOME/projects/builds/$repo/latest"

mkdir -p "$LOG_DIR" "$BUILD_DIR"

LOG_FILE="$LOG_DIR/${repo}_${branch//\//_}_$DATE_TAG.log"
exec &> >(tee -a "$LOG_FILE")

echo " Starting build for [$repo] on branch [$branch]..."

# === Git checkout ===
cd "$REPO_DIR"
echo " Fetching latest from origin/$branch..."
git fetch origin "$branch"
git checkout "$branch"
git reset --hard "origin/$branch"

# === Maven Build ===
echo " Building spriced-client-cummins-outbound-parent..."
cd "$REPO_DIR/spriced-client-cummins-outbound-parent"
mvn clean install -Dmaven.test.skip=true

# === Define ARTIFACTS ===
declare -A ARTIFACTS=(
  ["nrp-cummins-outbound"]="spriced-client-cummins-outbound-acknowledgement,spriced-client-cummins-outbound-basepricesap,spriced-client-cummins-outbound-ddc-uploadtosftp,spriced-client-cummins-outbound-erp-uploadtosftp,spriced-client-cummins-outbound-load-base-price,spriced-client-cummins-outbound-load-fixed-price,spriced-client-cummins-outbound-loadchannelintlow,spriced-client-cummins-outbound-loadimsrequest,spriced-client-cummins-outbound-loadpricelistauto,spriced-client-cummins-outbound-loadpricelistspecial,spriced-client-cummins-outbound-loadpricelistxrate,spriced-client-cummins-outbound-loadprimult,spriced-client-cummins-outbound-loadpvccodecreation,spriced-client-cummins-outbound-partsap,spriced-client-cummins-outbound-pvc,spriced-client-cummins-outbound-sap-uploadtosftp,spriced-client-cummins-outbound-upload-file-sftp,spriced-outbound-basepricesap-quarterly"
)

# === Copy Artifacts ===
echo " Copying build artifacts to: $BUILD_DIR"
IFS=',' read -ra MODULES <<< "${ARTIFACTS[$repo]}"
for module in "${MODULES[@]}"; do
  jar_path=$(find "$REPO_DIR" -path "*/$module/target/*.jar" ! -name "*original*" 2>/dev/null | head -n1)
  if [[ -f "$jar_path" ]]; then
    cp -p "$jar_path" "$BUILD_DIR/"
    echo " Copied: $(basename "$jar_path")"
  else
    echo "Missing artifact for module: $module"
  fi
done

# === Update latest symlink ===
ln -snf "$BUILD_DIR" "$LATEST_LINK"

echo "✅ Build completed for [$repo] at [$DATE_TAG]"
echo "📁 Artifacts available in: $BUILD_DIR"
echo "📄 Log saved to: $LOG_FILE"

