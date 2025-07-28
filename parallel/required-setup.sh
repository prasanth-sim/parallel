#!/bin/bash
set -Eeuo pipefail

LOG_PREFIX="[env-setup]"
NODE_VERSION="18.20.6"
ENV_FILE="$HOME/.env"

log() {
  echo "$LOG_PREFIX $(date +'%F %T') $*"
}

log "🔧 Updating package list..."
sudo apt-get update -y

log "📦 Installing Git, curl, unzip, and essential tools..."
sudo apt-get install -y git curl unzip software-properties-common

log "☕ Installing OpenJDK 17..."
sudo apt-get install -y openjdk-17-jdk

log "🛠️ Installing Maven..."
sudo apt-get install -y maven

log "🟩 Installing Node.js $NODE_VERSION..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

log "⚙️ Installing GNU Parallel..."
sudo apt-get install -y parallel

log "📁 Creating required folder structures..."
mkdir -p ~/projects/repos ~/projects/builds ~/automationlogs

log "📝 Setting up .env file for Git credentials..."
if [[ ! -f "$ENV_FILE" ]]; then
  read -p "🔐 Enter your GitHub username: " GIT_USERNAME
  read -s -p "🔑 Enter your GitHub personal access token (PAT): " GIT_TOKEN
  echo
  echo "GIT_USERNAME=$GIT_USERNAME" >> "$ENV_FILE"
  echo "GIT_TOKEN=$GIT_TOKEN" >> "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  log "✅ .env file created at $ENV_FILE"
else
  log "ℹ️ .env file already exists at $ENV_FILE"
fi

log "🔧 Configuring Git to use stored credentials..."
source "$ENV_FILE"
GIT_CREDENTIALS_FILE="$HOME/.git-credentials"
echo "https://$GIT_USERNAME:$GIT_TOKEN@github.com" > "$GIT_CREDENTIALS_FILE"
git config --global credential.helper store
git config --global user.name "$GIT_USERNAME"
chmod 600 "$GIT_CREDENTIALS_FILE"
log "✅ Git credential helper configured"

log "🧪 Checking versions..."
java -version
mvn -v
node -v
npm -v
git --version
parallel --version

log "✅ Environment setup completed successfully."
