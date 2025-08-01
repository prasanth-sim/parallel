#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

CONFIG_FILE="$HOME/.repo_builder_config"

save_config() {
    echo "Saving current configuration to $CONFIG_FILE..."
    {
        echo "BASE_INPUT=$BASE_INPUT"
        echo "SELECTED_REPOS=${SELECTED[*]}"
        echo "UI_ENV=$UI_ENV"
        echo "UI_BRANCH=$UI_BRANCH"
        echo "CLIENT_PRICING_BRANCH=$CLIENT_PRICING_BRANCH"
        echo "BACKEND_DEP_BRANCH=$BACKEND_DEP_BRANCH"
        for repo in "${!BRANCH_CHOICES[@]}"; do
            local var_name="BRANCH_${repo//-/_}"
            echo "$var_name=${BRANCH_CHOICES[$repo]}"
        done
    } > "$CONFIG_FILE"
    echo "Configuration saved."
}

# === Function to load configuration ===
load_config() {
    # 'declare -g' makes them accessible outside the function.
    declare -g BASE_INPUT=""
    declare -g SELECTED=()
    declare -g UI_ENV=""
    declare -g UI_BRANCH=""
    declare -g CLIENT_PRICING_BRANCH=""
    declare -g BACKEND_DEP_BRANCH=""
    declare -gA BRANCH_CHOICES # Declare an associative array for other repo branches

    if [[ -f "$CONFIG_FILE" ]]; then
        echo "💡 Loading previous inputs from $CONFIG_FILE..."
        while IFS='=' read -r key value; do
            case "$key" in
                BASE_INPUT) BASE_INPUT="$value" ;;
                SELECTED_REPOS) IFS=' ' read -r -a SELECTED <<< "$value" ;; # Read space-separated values into array
                UI_ENV) UI_ENV="$value" ;;
                UI_BRANCH) UI_BRANCH="$value" ;;
                CLIENT_PRICING_BRANCH) CLIENT_PRICING_BRANCH="$value" ;;
                BACKEND_DEP_BRANCH) BACKEND_DEP_BRANCH="$value" ;;
                BRANCH_*)
                    # Extract original repo name by removing "BRANCH_" prefix and converting underscores back to hyphens
                    local repo_key="${key#BRANCH_}"
                    local repo_name="${repo_key//_/'-'}"
                    BRANCH_CHOICES["$repo_name"]="$value"
                    ;;
            esac
        done < "$CONFIG_FILE"
    fi
}

# === Load previous configuration at script start ===
load_config

# Determine the directory where this script is located.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRED_SETUP_SCRIPT="$SCRIPT_DIR/required-setup.sh"

# --- Prompt to run required-setup.sh ---
if [[ -f "$REQUIRED_SETUP_SCRIPT" ]]; then
    read -rp "Do you want to run '$REQUIRED_SETUP_SCRIPT' to ensure all tools are set up? (y/N): " RUN_SETUP
    if [[ "${RUN_SETUP,,}" == "y" ]]; then
        echo "Running $REQUIRED_SETUP_SCRIPT..."
        echo "required-setup.sh completed."
    else
        echo "Skipping required-setup.sh. Please ensure your environment is set up correctly."
    fi
else
    echo "⚠️ Warning: required-setup.sh not found at $REQUIRED_SETUP_SCRIPT. Please ensure all necessary tools are installed manually."
fi

# === Prompt for Base Directory ===
# Use the loaded BASE_INPUT as default, or "automation_workspace" if no previous input.
DEFAULT_BASE_INPUT="${BASE_INPUT:-"automation_workspace"}"
read -rp "📁 Enter base directory for cloning/building/logs (relative to ~) [default: $DEFAULT_BASE_INPUT]: " USER_BASE_INPUT
# If user input is empty, use the default.
BASE_INPUT="${USER_BASE_INPUT:-$DEFAULT_BASE_INPUT}"
BASE_DIR="$HOME/$BASE_INPUT"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

# === Paths Based on User Input ===
CLONE_DIR="$BASE_DIR/repos"
DEPLOY_DIR="$BASE_DIR/builds"
LOG_DIR="$BASE_DIR/automationlogs"
TRACKER_FILE="$LOG_DIR/build-tracker-${DATE_TAG}.csv"

# Create necessary directories if they don't exist
mkdir -p "$CLONE_DIR" "$DEPLOY_DIR" "$LOG_DIR"

# === Repo Configurations ===
declare -A REPO_URLS=(
    ["spriced-ui"]="https://github.com/simaiserver/spriced-ui.git"
    ["spriced-backend"]="https://github.com/simaiserver/spriced-backend.git"
    ["spriced-client-cummins-parts-pricing"]="https://github.com/simaiserver/spriced-client-cummins-parts-pricing.git"
    ["spriced-client-cummins-data-ingestion"]="https://github.com/simaiserver/spriced-client-cummins-data-ingestion.git"
    ["Stocking-Segmentation-Enhancement"]="https://github.com/simaiserver/Stocking-Segmentation-Enhancement.git"
    ["spriced-platform"]="https://github.com/simaiserver/spriced-platform.git"
    ["nrp-cummins-outbound"]="https://github.com/simaiserver/nrp-cummins-outbound.git"
)

declare -A DEFAULT_BRANCHES=(
    ["spriced-ui"]="main"
    ["spriced-backend"]="main"
    ["spriced-client-cummins-parts-pricing"]="main"
    ["spriced-client-cummins-data-ingestion"]="main"
    ["Stocking-Segmentation-Enhancement"]="main"
    ["spriced-platform"]="main"
    ["nrp-cummins-outbound"]="develop"
)

REPOS=(
    "spriced-platform"
    "nrp-cummins-outbound"
    "spriced-backend"
    "spriced-ui"
    "spriced-client-cummins-data-ingestion"
    "Stocking-Segmentation-Enhancement"
    "spriced-client-cummins-parts-pricing"
)

BUILD_SCRIPTS=(
    "$SCRIPT_DIR/build_spriced_platform.sh"
    "$SCRIPT_DIR/build_nrp_cummins_outbound.sh"
    "$SCRIPT_DIR/build_spriced_backend.sh"
    "$SCRIPT_DIR/build_spriced_ui.sh"
    "$SCRIPT_DIR/build_spriced_client_cummins_data_ingestion.sh"
    "$SCRIPT_DIR/build_stocking_segmentation_enhancement.sh"
    "$SCRIPT_DIR/build_spriced_client_cummins_parts_pricing.sh"
)

# === Display Repo Selection Menu ===
echo -e "\n📦 Available Repositories:"
for i in "${!REPOS[@]}"; do
    printf "  %d) %s\n" "$((i+1))" "${REPOS[$i]}"
done
echo "  0) ALL"

# Use previously selected repos as default, or '0' (ALL) if no previous selection.
DEFAULT_SELECTED_PROMPT="${SELECTED[*]:-0}"
read -rp $'\n📌 Enter repo numbers to build (space-separated or 0 for all) [default: '"$DEFAULT_SELECTED_PROMPT"']: ' -a USER_SELECTED_INPUT

# If user provided input, use it. Otherwise, stick with the loaded 'SELECTED' array.
if [[ -n "${USER_SELECTED_INPUT[*]}" ]]; then
    SELECTED=("${USER_SELECTED_INPUT[@]}")
fi

# Handle '0' or 'all' input to select all repositories.
if [[ "${SELECTED[0]}" == "0" || "${SELECTED[0],,}" == "all" ]]; then
    SELECTED=($(seq 1 ${#REPOS[@]}))
fi

# Array to store commands to be executed in parallel.
COMMANDS=()


# === Prepare Build Commands ===
# Loop through the selected repository indices.
for idx_str in "${SELECTED[@]}"; do
    # Convert string index to integer for array access and comparison.
    idx="$idx_str"

    # Validate the selected index.
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#REPOS[@]} )); then
        echo "⚠️ Invalid selection: $idx. Skipping..."
        continue
    fi

    # Calculate array index (0-based).
    i=$((idx - 1))
    REPO="${REPOS[$i]}"
    SCRIPT="${BUILD_SCRIPTS[$i]}"
    REPO_DIR="$CLONE_DIR/$REPO"
    DEFAULT_REPO_BRANCH="${DEFAULT_BRANCHES[$REPO]}" # Get the default branch for the current repo.

    echo -e "\n🚀 Checking '$REPO' repository..."

    # Clone or update the main repository.
    if [[ -d "$REPO_DIR/.git" ]]; then
        echo "🔄 Updating existing repo at $REPO_DIR"
        (
            cd "$REPO_DIR" || exit 1 # Navigate into the repo directory. Exit script on failure.
            git fetch origin --prune # Fetch latest changes, prune stale remote branches.
            git reset --hard HEAD # Discard local changes and reset to current HEAD.
            git clean -fd # Remove untracked files and directories.
            # Check if the default branch exists on the remote.
            if git rev-parse --verify "origin/$DEFAULT_REPO_BRANCH" >/dev/null 2>&1; then
                git checkout -B "$DEFAULT_REPO_BRANCH" "origin/$DEFAULT_REPO_BRANCH" # Checkout or create the branch tracking remote.
            else
                echo "❌ Remote branch origin/$DEFAULT_REPO_BRANCH not found. Skipping '$REPO'..."
                exit 1 # Exit subshell to skip this repo's command preparation.
            fi
        ) || continue # If the subshell exited with an error, continue to the next repo.
    else
        echo "📥 Cloning new repo from ${REPO_URLS[$REPO]} into $REPO_DIR"
        # If directory exists but isn't a git repo, clean it up before cloning.
        [[ -d "$REPO_DIR" && ! -d "$REPO_DIR/.git" ]] && rm -rf "$REPO_DIR"
        git clone "${REPO_URLS[$REPO]}" "$REPO_DIR" || { echo "❌ Failed to clone $REPO. Skipping build."; continue; }
        (
            cd "$REPO_DIR" || exit 1 # Navigate into the newly cloned repo.
        ) || continue # If cd fails, continue.
    fi

    # --- Special handling for 'spriced-ui' ---
    if [[ "$REPO" == "spriced-ui" ]]; then
        PIPELINE_DIR="$BASE_DIR/spriced-pipeline"
        PIPELINE_URL="https://github.com/simaiserver/spriced-pipeline.git"
        echo "Checking spriced-pipeline repository at $PIPELINE_DIR..."
        if [[ -d "$PIPELINE_DIR/.git" ]]; then
            echo "🔄 Updating existing spriced-pipeline repo."
            git -C "$PIPELINE_DIR" pull --quiet # Update spriced-pipeline without changing directory.
        else
            echo "📥 Cloning spriced-pipeline repo from $PIPELINE_URL into $PIPELINE_DIR." # Corrected: PIPELINE_URL
            git clone --quiet "$PIPELINE_URL" "$PIPELINE_DIR" || { echo "❌ Failed to clone spriced-pipeline. Skipping spriced-ui build."; continue; }
        fi

        echo -e "\n🌐 Choose environment for spriced-ui:"
        echo "  1) dev"
        echo "  2) qa"
        echo "  3) test"

        # Determine default environment number based on loaded UI_ENV.
        CURRENT_UI_ENV_LOADED="${UI_ENV:-}"
        DEFAULT_ENV_NUM=""
        case "$CURRENT_UI_ENV_LOADED" in
            "dev") DEFAULT_ENV_NUM="1" ;;
            "qa") DEFAULT_ENV_NUM="2" ;;
            "test") DEFAULT_ENV_NUM="3" ;;
            *) DEFAULT_ENV_NUM="1" ;; # Default to 'dev' if nothing saved or invalid.
        esac

        # Loop until a valid environment number is entered
        while true; do
            read -rp "📌 Enter environment number (1 for dev, 2 for qa, 3 for test) [default: $DEFAULT_ENV_NUM]: " ENV_NUM_INPUT
            ENV_NUM_CHOICE="${ENV_NUM_INPUT:-$DEFAULT_ENV_NUM}" # Use user input or default.

            ENV="" # Initialize ENV for the case statement.
            case "$ENV_NUM_CHOICE" in
                1) ENV="dev"; break ;; # Valid input, break loop
                2) ENV="qa"; break ;; # Valid input, break loop
                3) ENV="test"; break ;; # Valid input, break loop
                *) echo "❌ Invalid input. Please enter 1, 2, or 3." ;; # Invalid, re-prompt
            esac
        done
        UI_ENV="$ENV" # Store the chosen environment for saving.

        # Determine default UI branch.
        DEFAULT_UI_BRANCH="${UI_BRANCH:-$DEFAULT_REPO_BRANCH}"
        read -rp "🌿 Enter branch name for spriced-ui [default: $DEFAULT_UI_BRANCH]: " BRANCH_INPUT
        BRANCH="${BRANCH_INPUT:-$DEFAULT_UI_BRANCH}" # Use user input or default.
        UI_BRANCH="$BRANCH" # Store the chosen branch for saving.

        BACKUP_DIR="/tmp/spriced_ui_backup_$DATE_TAG"
        mkdir -p "$BACKUP_DIR"
        # Find .env files within 'apps/' subdirectories and move them to backup
        # '2>/dev/null || true' suppresses errors if files don't exist.
        find "$REPO_DIR/apps/" -maxdepth 2 -type f -name ".env" -exec mv {} "$BACKUP_DIR" \; 2>/dev/null || true
        mv "$REPO_DIR/package-lock.json" "$BACKUP_DIR/" 2>/dev/null || true

        (
            cd "$REPO_DIR" || exit 1
            git fetch origin # Fetch from origin to ensure the specified branch is available.
            if git rev-parse --verify origin/"$BRANCH" >/dev/null 2>&1; then
                echo "Switching to branch: $BRANCH"
                git checkout -B "$BRANCH" origin/"$BRANCH" # Checkout or create the branch.
            else
                echo "❌ Branch '$BRANCH' not found on origin. Skipping spriced-ui build."
                exit 1 # Exit subshell to skip this repo's command preparation.
            fi
        ) || continue

        echo "Restoring backed up .env files and package-lock.json..."
        find "$BACKUP_DIR" -maxdepth 1 -type f -name ".env" -exec cp {} "$REPO_DIR/apps/" \; 2>/dev/null || true
        cp "$BACKUP_DIR/package-lock.json" "$REPO_DIR/" 2>/dev/null || true
        # Clean up backup directory
        rm -rf "$BACKUP_DIR"

        LOG_FILE="$LOG_DIR/${REPO}_$(date +%Y%m%d%H%M%S).log"
        CMD="bash -c '${SCRIPT} \"${ENV}\" \"${BRANCH}\" \"${BASE_DIR}\" &>> \"${LOG_FILE}\" && echo \"${REPO},SUCCESS,${LOG_FILE}\" >> \"${TRACKER_FILE}\" || echo \"${REPO},FAIL,${LOG_FILE}\" >> \"${TRACKER_FILE}\"'"

    # --- Special handling for 'spriced-client-cummins-parts-pricing' ---
    elif [[ "$REPO" == "spriced-client-cummins-parts-pricing" ]]; then
        # Determine default client branch.
        DEFAULT_CLIENT_BRANCH="${CLIENT_PRICING_BRANCH:-$DEFAULT_REPO_BRANCH}"
        read -rp "🌿 Enter branch for ${REPO} [default: $DEFAULT_CLIENT_BRANCH]: " CLIENT_BRANCH_INPUT
        CLIENT_BRANCH="${CLIENT_BRANCH_INPUT:-$DEFAULT_CLIENT_BRANCH}" # Use user input or default.
        CLIENT_PRICING_BRANCH="$CLIENT_BRANCH" # Store for saving.

        DEFAULT_BACKEND_BRANCH_DEP="${BACKEND_DEP_BRANCH:-${DEFAULT_BRANCHES['spriced-backend']}}"
        read -rp "🌿 Enter branch for spriced-backend (dependency) [default: $DEFAULT_BACKEND_BRANCH_DEP]: " BACKEND_BRANCH_INPUT
        BACKEND_BRANCH="${BACKEND_BRANCH_INPUT:-$DEFAULT_BACKEND_BRANCH_DEP}" # Use user input or default.
        BACKEND_DEP_BRANCH="$BACKEND_BRANCH" # Store for saving.

        (
            cd "$REPO_DIR" || exit 1
            git fetch origin
            if git rev-parse --verify origin/"$CLIENT_BRANCH" >/dev/null 2>&1; then
                echo "Switching to branch: $CLIENT_BRANCH"
                git checkout -B "$CLIENT_BRANCH" origin/"$CLIENT_BRANCH"
            else
                echo "❌ Branch '$CLIENT_BRANCH' not found on origin. Skipping '$REPO' build."
                exit 1
            fi
        ) || continue

        LOG_FILE="$LOG_DIR/${REPO}_$(date +%Y%m%d%H%M%S).log"
        # Pass CLIENT_BRANCH, BASE_DIR, and BACKEND_BRANCH to the build script.
        CMD="bash -c '${SCRIPT} \"${CLIENT_BRANCH}\" \"${BASE_DIR}\" \"${BACKEND_BRANCH}\" &>> \"${LOG_FILE}\" && echo \"${REPO},SUCCESS,${LOG_FILE}\" >> \"${TRACKER_FILE}\" || echo \"${REPO},FAIL,${LOG_FILE}\" >> \"${TRACKER_FILE}\"'"

    # --- Generic handling for all other repositories ---
    else # This 'else' correctly pairs with the 'elif' above and the initial 'if'
        # Use previous branch choice if available, otherwise default for the repo.
        DEFAULT_GENERIC_BRANCH="${BRANCH_CHOICES[$REPO]:-$DEFAULT_REPO_BRANCH}"
        read -rp "🌿 Enter branch for ${REPO} [default: $DEFAULT_GENERIC_BRANCH]: " BRANCH_INPUT
        BRANCH="${BRANCH_INPUT:-$DEFAULT_GENERIC_BRANCH}" # Use user input or default.
        BRANCH_CHOICES["$REPO"]="$BRANCH" # Store for saving.

        (
            cd "$REPO_DIR" || exit 1
            git fetch origin
            if git rev-parse --verify origin/"$BRANCH" >/dev/null 2>&1; then
                echo "Switching to branch: $BRANCH"
                git checkout -B "$BRANCH" origin/"$BRANCH"
            else
                echo "❌ Branch '$BRANCH' not found on origin. Skipping '$REPO' build."
                exit 1
            fi
        ) || continue

        LOG_FILE="$LOG_DIR/${REPO}_$(date +%Y%m%d%H%M%S).log"
        # The build script will receive branch and base_dir.
        CMD="bash -c '${SCRIPT} \"${BRANCH}\" \"${BASE_DIR}\" &>> \"${LOG_FILE}\" && echo \"${REPO},SUCCESS,${LOG_FILE}\" >> \"${TRACKER_FILE}\" || echo \"${REPO},FAIL,${LOG_FILE}\" >> \"${TRACKER_FILE}\"'"
    fi # This 'fi' closes the outermost 'if' statement for special handling
    COMMANDS+=("$CMD")
done

# === Save configuration for next run ===
# This must be called after all inputs are gathered and processed successfully.
save_config

# === Parallel Execution ===
# Determine the number of CPU cores for parallel builds.
CPU_CORES=$(nproc)
echo -e "\n🚀 Running ${#COMMANDS[@]} builds in parallel using ${CPU_CORES} CPU cores...\n"

# Check if there are any commands to execute.
if [ ${#COMMANDS[@]} -eq 0 ]; then
    echo "No commands to execute. Exiting."
    exit 0
fi

# Execute commands in parallel using GNU Parallel.
# `printf "%s\n" "${COMMANDS[@]}"` prints each command on a new line.
# `parallel -j "$CPU_CORES" --no-notice --bar` runs them concurrently.
printf "%s\n" "${COMMANDS[@]}" | parallel -j "$CPU_CORES" --no-notice --bar

# === Summary Output ===
echo -e "\n🧾 Build Summary:\n"
# Check if the build tracker file exists.
if [[ -f "$TRACKER_FILE" ]]; then
    # Create a more readable summary CSV file for this run.
    SUMMARY_CSV_FILE="$LOG_DIR/build-summary-${DATE_TAG}.csv"
    echo "Status,Repository,Log File" > "$SUMMARY_CSV_FILE" # Write header.
    # Read the tracker file line by line and print summary.
    while IFS=',' read -r REPO STATUS LOGFILE; do
        if [[ "$STATUS" == "SUCCESS" ]]; then
            echo "[✔️ DONE] $REPO - see log: $LOGFILE"
        else
            echo "[❌ FAIL] $REPO - see log: $LOGFILE"
        fi
        echo "$STATUS,$REPO,$LOGFILE" >> "$SUMMARY_CSV_FILE" # Append to summary CSV.
    done < "$TRACKER_FILE"
else
    echo "⚠️ Build tracker not found: $TRACKER_FILE"
fi

echo -e "\n📄 Build tracker written to: $TRACKER_FILE"
echo "📄 Detailed build summary also available at: $SUMMARY_CSV_FILE"
echo -e "\n✅ Script execution complete."
