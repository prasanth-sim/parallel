#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# === Inputs ===
BRANCH="${1:-main}"
BASE_DIR="${2:-$HOME/build-default}"  # fallback if not passed
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

echo "🔧 Starting build for [$REPO] on branch [$BRANCH]..."
echo "📅 Timestamp: $DATE_TAG"

# === Git Clone or Pull ===
if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "🚀 Cloning repository from $GIT_URL ..."
  git clone "$GIT_URL" "$REPO_DIR"
else
  echo "📁 Repository already exists. Pulling latest..."
  git -C "$REPO_DIR" fetch origin
  git -C "$REPO_DIR" reset --hard "origin/$BRANCH"
fi

cd "$REPO_DIR"
echo "🌐 Checking out branch [$BRANCH]..."
git checkout "$BRANCH"
git reset --hard "origin/$BRANCH"

# === Maven Build ===
PARENT_MODULE="$REPO_DIR/spriced-client-cummins-outbound-parent"
echo "🔨 Building module: $PARENT_MODULE"
cd "$PARENT_MODULE"
mvn clean install -Dmaven.test.skip=true

# === Define ARTIFACTS ===
declare -A ARTIFACTS=(
  ["nrp-cummins-outbound"]="spriced-client-cummins-outbound-acknowledgement,spriced-client-cummins-outbound-basepricesap,spriced-client-cummins-outbound-ddc-uploadtosftp,spriced-client-cummins-outbound-erp-uploadtosftp,spriced-client-cummins-outbound-load-base-price,spriced-client-cummins-outbound-load-fixed-price,spriced-client-cummins-outbound-loadchannelintlow,spriced-client-cummins-outbound-loadimsrequest,spriced-client-cummins-outbound-loadpricelistauto,spriced-client-cummins-outbound-loadpricelistspecial,spriced-client-cummins-outbound-loadpricelistxrate,spriced-client-cummins-outbound-loadprimult,spriced-client-cummins-outbound-loadpvccodecreation,spriced-client-cummins-outbound-partsap,spriced-client-cummins-outbound-pvc,spriced-client-cummins-outbound-sap-uploadtosftp,spriced-client-cummins-outbound-upload-file-sftp,spriced-outbound-basepricesap-quarterly"
)

# === Copy Artifacts ===
echo "📦 Copying JAR artifacts to: $BUILD_DIR"
IFS=',' read -ra MODULES <<< "${ARTIFACTS[$REPO]}"
for MODULE in "${MODULES[@]}"; do
  JAR_PATH=$(find "$REPO_DIR" -path "*/$MODULE/target/*.jar" ! -name "original-*.jar" 2>/dev/null | head -n 1)
  if [[ -f "$JAR_PATH" ]]; then
    cp -p "$JAR_PATH" "$BUILD_DIR/"
    echo "✅ Copied: $(basename "$JAR_PATH")"
  else
    echo "⚠️  Missing artifact for module: $MODULE"
  fi
done

# === Update latest symlink ===
ln -snf "$BUILD_DIR" "$LATEST_LINK"

# === Summary ===
echo "✅ Build complete for [$REPO] on branch [$BRANCH]"
echo "📁 Artifacts stored at: $BUILD_DIR"
echo "📄 Log saved at: $LOG_FILE"
