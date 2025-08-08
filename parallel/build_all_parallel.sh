#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

CONFIG_FILE="$HOME/.repo_builder_config"

# === Function to save configuration ===
# Saves the current state of user inputs to a configuration file
save_config() {
    echo "Saving current configuration to $CONFIG_FILE..."
    {
        echo "BASE_INPUT=$BASE_INPUT"
        echo "SELECTED_REPOS=${SELECTED[*]}"
        echo "UI_ENV=$UI_ENV"
        echo "UI_BRANCH=$UI_BRANCH"
        echo "CLIENT_PRICING_BRANCH=$CLIENT_PRICING_BRANCH"
        echo "BACKEND_DEP_BRANCH=$BACKEND_DEP_BRANCH"
        # Iterate through the associative array of other repo branches
        for repo in "${!BRANCH_CHOICES[@]}"; do
            local var_name="BRANCH_${repo//-/_}" # Convert hyphens to underscores for variable name
            echo "$var_name=${BRANCH_CHOICES[$repo]}"
        done
    } > "$CONFIG_FILE" # Redirect all echoes to the config file
    echo "Configuration saved."
}

# === Function to load configuration ===
# Loads previous user inputs from the configuration file, if it exists
load_config() {
    # Declare global variables to make them accessible throughout the script
    declare -g BASE_INPUT=""
    declare -g SELECTED=() # Array for selected repo numbers
    declare -g UI_ENV=""
    declare -g UI_BRANCH=""
    declare -g CLIENT_PRICING_BRANCH=""
    declare -g BACKEND_DEP_BRANCH=""
    declare -gA BRANCH_CHOICES # Associative array for other repo branches

    if [[ -f "$CONFIG_FILE" ]]; then
        echo "💡 Loading previous inputs from $CONFIG_FILE..."
        while IFS='=' read -r key value; do # Read file line by line, splitting by '='
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

# Record the script start time for the build summary
START_TIME=$(date +"%Y-%m-%d %H:%M:%S")

# Determine the directory where this script is located (useful for relative paths to other scripts)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRED_SETUP_SCRIPT="$SCRIPT_DIR/required-setup.sh"

# --- Prompt to run required-setup.sh ---
# Asks the user if they want to run a setup script (if it exists)
if [[ -f "$REQUIRED_SETUP_SCRIPT" ]]; then
    read -rp "Do you want to run '$REQUIRED_SETUP_SCRIPT' to ensure all tools are set up? (y/N): " RUN_SETUP
    if [[ "${RUN_SETUP,,}" == "y" ]]; then # Convert input to lowercase for comparison
        echo "Running $REQUIRED_SETUP_SCRIPT..."
        "$REQUIRED_SETUP_SCRIPT" # Execute the setup script
        echo "required-setup.sh completed."
    else
        echo "Skipping required-setup.sh. Please ensure your environment is set up correctly."
    fi
else
    echo "⚠️ Warning: required-setup.sh not found at $REQUIRED_SETUP_SCRIPT. Please ensure all necessary tools are installed manually."
fi

# === Prompt for Base Directory ===
# Prompts the user for a base directory, using a loaded default or a hardcoded one
DEFAULT_BASE_INPUT="${BASE_INPUT:-"automation_workspace"}" # Use loaded BASE_INPUT as default, or "automation_workspace"
read -rp "📁 Enter base directory for cloning/building/logs (relative to ~) [default: $DEFAULT_BASE_INPUT]: " USER_BASE_INPUT
BASE_INPUT="${USER_BASE_INPUT:-$DEFAULT_BASE_INPUT}" # Use user input, or the default if input is empty
BASE_DIR="$HOME/$BASE_INPUT" # Construct the full absolute path
DATE_TAG=$(date +"%Y%m%d_%H%M%S") # Timestamp for unique build and log directories

# === Paths Based on User Input ===
CLONE_DIR="$BASE_DIR/repos"
DEPLOY_DIR="$BASE_DIR/builds"
LOG_DIR="$BASE_DIR/automationlogs"
TRACKER_FILE="$LOG_DIR/build-tracker-${DATE_TAG}.csv" # File to track build success/failure

# Create necessary directories if they don't exist
mkdir -p "$CLONE_DIR" "$DEPLOY_DIR" "$LOG_DIR"

# === Repo Configurations ===
# Associative array mapping repository names to their Git URLs
declare -A REPO_URLS=(
    ["spriced-ui"]="https://github.com/simaiserver/spriced-ui.git"
    ["spriced-backend"]="https://github.com/simaiserver/spriced-backend.git"
    ["spriced-client-cummins-parts-pricing"]="https://github.com/simaiserver/spriced-client-cummins-parts-pricing.git"
    ["spriced-client-cummins-data-ingestion"]="https://github.com/simaiserver/spriced-client-cummins-data-ingestion.git"
    ["Stocking-Segmentation-Enhancement"]="https://github.com/simaiserver/Stocking-Segmentation-Enhancement.git"
    ["spriced-platform"]="https://github.com/simaiserver/spriced-platform.git"
    ["nrp-cummins-outbound"]="https://github.com/simaiserver/nrp-cummins-outbound.git"
)

# Associative array mapping repository names to their default branches
declare -A DEFAULT_BRANCHES=(
    ["spriced-ui"]="main"
    ["spriced-backend"]="main"
    ["spriced-client-cummins-parts-pricing"]="main"
    ["spriced-client-cummins-data-ingestion"]="main"
    ["Stocking-Segmentation-Enhancement"]="main"
    ["spriced-platform"]="main"
    ["nrp-cummins-outbound"]="develop"
)

# Ordered list of repositories for display and processing
REPOS=(
    "spriced-backend"
    "spriced-platform"
    "nrp-cummins-outbound"
    "spriced-ui"
    "spriced-client-cummins-data-ingestion"
    "Stocking-Segmentation-Enhancement"
    "spriced-client-cummins-parts-pricing"
)

BUILD_SCRIPTS=(
    "$SCRIPT_DIR/build_spriced_backend.sh"
    "$SCRIPT_DIR/build_spriced_platform.sh"
    "$SCRIPT_DIR/build_nrp_cummins_outbound.sh"
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
echo "  0) ALL" # Option to select all repositories

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

# Helper function to build a single repo and log its output
# This function is exported so it can be used by GNU Parallel in subshells
build_and_log_repo() {
    local repo_name="$1"
    local script_path="$2"
    local log_file="$3" # Local variable for the log file path
    local tracker_file="$4" # Local variable for the tracker file path
    local base_dir_for_build_script="$5"
    shift 5 # Shift arguments to allow passing remaining arguments to the build script

    local script_output
    local script_exit_code

    # Add start timestamp to the log file
    echo "$(date +'%Y-%m-%d %H:%M:%S') --- Build started for $repo_name ---" >> "${log_file}"

    # Execute the specific build script and capture its output and exit status
    # The 'set +e' and 'set -e' around this block ensure that the script doesn't exit
    # if the command fails, allowing us to capture its exit code.
    set +e
    if script_output=$("${script_path}" "$@" "$base_dir_for_build_script" 2>&1); then
        script_exit_code=0
    else
        script_exit_code=$?
    fi
    set -e

    # Append timestamped output to the log file
    echo "$script_output" | while IFS= read -r line; do
        echo "$(date +'%Y-%m-%d %H:%M:%S') $line"
    done >> "${log_file}"

    # Record success or failure in the tracker file based on the script's exit code
    local status="FAIL"
    if [[ "$script_exit_code" -eq 0 ]]; then
        status="SUCCESS"
    fi
    echo "${repo_name},${status},${log_file}" >> "${tracker_file}" # Record success/failure in tracker

    # Add end timestamp and final status to the log file
    echo "$(date +'%Y-%m-%d %H:%M:%S') --- Build finished for $repo_name with status: $status ---" >> "${log_file}"
}
export -f build_and_log_repo # Export the function for parallel execution

# Track which repos are selected to avoid duplicate processing
declare -A SELECTED_REPOS_MAP
for idx_str in "${SELECTED[@]}"; do
    idx="$idx_str"
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#REPOS[@]} )); then
        echo "⚠️ Invalid selection: $idx. Skipping..."
        continue # Invalid selection, just skip
    fi
    i=$((idx - 1))
    SELECTED_REPOS_MAP["${REPOS[$i]}"]=1 # Mark repo as selected
done

# --- Phase 1: Git Operations and User Input Collection (for all selected repos) ---
# This loop performs git operations and collects all necessary branch/environment inputs upfront.
# It does NOT start any builds yet.
UI_BUILD_ENV_CHOSEN="" # Variable to store the chosen UI environment (used by build_spriced_ui.sh)

for repo_name_to_process in "${REPOS[@]}"; do # Iterate through the ordered list of all repos
    # --- FIX: Use -v to check if the key exists without triggering a nounset error ---
    if [[ -v SELECTED_REPOS_MAP["$repo_name_to_process"] ]]; then # Only process if it was selected by the user
        # Find the index of the current repo_name_to_process in the REPOS array
        i=-1
        for j in "${!REPOS[@]}"; do
            if [[ "${REPOS[$j]}" == "$repo_name_to_process" ]]; then
                i=$j
                break
            fi
        done

        if [[ "$i" -eq -1 ]]; then
            echo "Error: Could not find index for repo $repo_name_to_process. Skipping."
            unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue # Remove from selected if lookup fails
        fi

        REPO="${REPOS[$i]}"
        SCRIPT_PATH_FOR_REPO="${BUILD_SCRIPTS[$i]}" # Store script path for later use in build phase
        REPO_DIR="$CLONE_DIR/$REPO"
        DEFAULT_REPO_BRANCH="${DEFAULT_BRANCHES[$REPO]}"

        echo -e "\n🚀 Checking '$REPO' repository..."

        if [[ -d "$REPO_DIR/.git" ]]; then
            echo "🔄 Updating existing repo at $REPO_DIR"
            (
                cd "$REPO_DIR" || exit 1
                git fetch origin --prune
                git reset --hard HEAD
                git clean -fd
                if git rev-parse --verify "origin/$DEFAULT_REPO_BRANCH" >/dev/null 2>&1; then
                    git checkout -B "$DEFAULT_REPO_BRANCH" origin/"$DEFAULT_REPO_BRANCH"
                else
                    echo "❌ Remote branch origin/$DEFAULT_REPO_BRANCH not found. Skipping '$REPO'..."
                    exit 1
                fi
            ) || { echo "❌ Failed to prepare $REPO. Skipping its build."; unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue; }
        else
            echo "📥 Cloning new repo from ${REPO_URLS[$REPO]} into "$REPO_DIR""
            [[ -d "$REPO_DIR" && ! -d "$REPO_DIR/.git" ]] && rm -rf "$REPO_DIR"
            git clone "${REPO_URLS[$REPO]}" "$REPO_DIR" || { echo "❌ Failed to clone $REPO. Skipping its build."; unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue; }
            (cd "$REPO_DIR" || exit 1) || { echo "❌ Failed to enter $REPO directory. Skipping its build."; unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue; }
        fi

        # --- Collect user input for branch/environment ---
        if [[ "$REPO" == "spriced-ui" ]]; then
            PIPELINE_DIR="$BASE_DIR/spriced-pipeline"
            PIPELINE_URL="https://github.com/simaiserver/spriced-pipeline.git"
            echo "Checking spriced-pipeline repository at $PIPELINE_DIR..."
            if [[ -d "$PIPELINE_DIR/.git" ]]; then
                echo "🔄 Updating existing spriced-pipeline repo."
                git -C "$PIPELINE_DIR" pull --quiet
            else
                echo "📥 Cloning spriced-pipeline repo from $PIPELINE_URL into $PIPELINE_DIR."
                git clone --quiet "$PIPELINE_URL" "$PIPELINE_DIR" || { echo "❌ Failed to clone spriced-pipeline. Skipping spriced-ui build."; unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue; }
            fi

            declare -a AVAILABLE_ENVS=()
            PIPELINE_FRONTEND_DIR="$PIPELINE_DIR/framework/frontend"
            if [ ! -d "$PIPELINE_FRONTEND_DIR" ]; then
                echo "❌ Directory not found: $PIPELINE_FRONTEND_DIR. Cannot determine environments."
                unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue
            fi

            while IFS= read -r -d '' dir; do
                env_name=$(basename "$dir" | sed 's/nrp-//')
                AVAILABLE_ENVS+=("$env_name")
            done < <(find "$PIPELINE_FRONTEND_DIR" -maxdepth 1 -type d -name "nrp-*" -print0)

            echo -e "\n🌐 Choose environment for spriced-ui:"
            for env_idx in "${!AVAILABLE_ENVS[@]}"; do
                printf "  %d) %s\n" "$((env_idx+1))" "${AVAILABLE_ENVS[$env_idx]}"
            done
            echo "  $((${#AVAILABLE_ENVS[@]} + 1))) Create New..."

            DEFAULT_ENV_CHOICE=1
            if [[ -n "$UI_ENV" ]]; then
                for env_idx in "${!AVAILABLE_ENVS[@]}"; do
                    if [[ "${AVAILABLE_ENVS[$env_idx]}" == "$UI_ENV" ]]; then
                        DEFAULT_ENV_CHOICE=$((env_idx+1))
                        break
                    fi
                done
            fi

            while true; do
                read -rp "📌 Enter environment number [default: $DEFAULT_ENV_CHOICE]: " ENV_NUM_INPUT
                ENV_NUM_CHOICE="${ENV_NUM_INPUT:-$DEFAULT_ENV_CHOICE}"

                if [[ "$ENV_NUM_CHOICE" =~ ^[0-9]+$ ]] && (( ENV_NUM_CHOICE == ${#AVAILABLE_ENVS[@]} + 1 )); then
                    read -rp "📝 Enter new environment name (e.g., prasanth): " NEW_ENV_NAME
                    ENV_INPUT_COLLECTED="$NEW_ENV_NAME" # Use a temporary variable
                    if [ -z "$ENV_INPUT_COLLECTED" ]; then
                        echo "❌ Environment name cannot be empty. Please try again."
                        continue
                    fi
                    NEW_ENV_DIR="$PIPELINE_FRONTEND_DIR/nrp-$ENV_INPUT_COLLECTED"
                    if [ -d "$NEW_ENV_DIR" ]; then
                        echo "❌ Environment '$ENV_INPUT_COLLECTED' already exists. Please choose a different name."
                        continue
                    fi
                    mkdir -p "$NEW_ENV_DIR"
                    echo "✅ Created directory for new environment '$ENV_INPUT_COLLECTED' in spriced-pipeline."
                    if [ -d "$PIPELINE_FRONTEND_DIR/nrp-dev" ]; then
                        cp -r "$PIPELINE_FRONTEND_DIR/nrp-dev/"* "$NEW_ENV_DIR/"
                        echo "✅ Initial .env files copied from 'dev' to new environment."
                    else
                        echo "⚠️ Warning: 'nrp-dev' environment not found to copy initial .env files from."
                        echo "Please manually configure .env files and module-federation.manifest.json in '$NEW_ENV_DIR' for each microfrontend."
                    fi
                    break
                elif [[ "$ENV_NUM_CHOICE" =~ ^[0-9]+$ ]] && (( ENV_NUM_CHOICE >= 1 && ENV_NUM_CHOICE <= ${#AVAILABLE_ENVS[@]} )); then
                    ENV_INPUT_COLLECTED="${AVAILABLE_ENVS[$((ENV_NUM_CHOICE-1))]}" # Use a temporary variable
                    break
                else
                    echo "❌ Invalid input. Please enter a valid number."
                fi
            done
            UI_ENV="$ENV_INPUT_COLLECTED" # Store for saving config
            UI_BUILD_ENV_CHOSEN="$ENV_INPUT_COLLECTED" # Store for passing to build script

            DEFAULT_UI_BRANCH="${UI_BRANCH:-$DEFAULT_REPO_BRANCH}"
            read -rp "🌿 Enter branch name for spriced-ui [default: $DEFAULT_UI_BRANCH]: " BRANCH_INPUT_COLLECTED
            BRANCH_INPUT_COLLECTED="${BRANCH_INPUT_COLLECTED:-$DEFAULT_UI_BRANCH}"
            UI_BRANCH="$BRANCH_INPUT_COLLECTED" # Store for saving config
            BRANCH_CHOICES["$REPO"]="$BRANCH_INPUT_COLLECTED" # Also store in general branch choices

            # Backup and restore logic for package-lock.json and .env files in the repo
            BACKUP_DIR="/tmp/spriced_ui_backup_$DATE_TAG"
            mkdir -p "$BACKUP_DIR"
            find "$REPO_DIR/apps/" -maxdepth 2 -type f -name ".env" -exec mv {} "$BACKUP_DIR" \; 2>/dev/null || true
            mv "$REPO_DIR/package-lock.json" "$BACKUP_DIR/" 2>/dev/null || true

            # Checkout the chosen branch for spriced-ui
            (
                cd "$REPO_DIR" || exit 1
                git fetch origin
                if git rev-parse --verify origin/"$BRANCH_INPUT_COLLECTED" >/dev/null 2>&1; then
                    echo "Switching to branch: $BRANCH_INPUT_COLLECTED"
                    git checkout -B "$BRANCH_INPUT_COLLECTED" origin/"$BRANCH_INPUT_COLLECTED"
                else
                    echo "❌ Branch '$BRANCH_INPUT_COLLECTED' not found on origin. Skipping spriced-ui build."
                    exit 1
                fi
            ) || { unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue; }
            echo "Restoring backed up .env files and package-lock.json..."
            find "$BACKUP_DIR" -maxdepth 1 -type f -name ".env" -exec cp {} "$REPO_DIR/apps/" \; 2>/dev/null || true
            cp "$BACKUP_DIR/package-lock.json" "$REPO_DIR/" 2>/dev/null || true
            rm -rf "$BACKUP_DIR"

        # --- Special handling for 'spriced-client-cummins-parts-pricing' (collect branch input) ---
        elif [[ "$REPO" == "spriced-client-cummins-parts-pricing" ]]; then
            DEFAULT_CLIENT_BRANCH="${CLIENT_PRICING_BRANCH:-$DEFAULT_REPO_BRANCH}"
            read -rp "🌿 Enter branch for ${REPO} [default: $DEFAULT_CLIENT_BRANCH]: " CLIENT_BRANCH_INPUT_COLLECTED
            CLIENT_BRANCH_INPUT_COLLECTED="${CLIENT_BRANCH_INPUT_COLLECTED:-$DEFAULT_CLIENT_BRANCH}"
            CLIENT_PRICING_BRANCH="$CLIENT_BRANCH_INPUT_COLLECTED" # Store for saving config
            BRANCH_CHOICES["$REPO"]="$CLIENT_BRANCH_INPUT_COLLECTED" # Also store in general branch choices

            BACKEND_REPO_DIR="$CLONE_DIR/spriced-backend"
            while true; do
                DEFAULT_BACKEND_BRANCH_DEP="${BACKEND_DEP_BRANCH:-${DEFAULT_BRANCHES['spriced-backend']}}"
                read -rp "🌿 Enter branch for spriced-backend (dependency) [default: $DEFAULT_BACKEND_BRANCH_DEP]: " BACKEND_BRANCH_INPUT_COLLECTED
                BACKEND_BRANCH_INPUT_COLLECTED="${BACKEND_BRANCH_INPUT_COLLECTED:-$DEFAULT_BACKEND_BRANCH_DEP}"
                BACKEND_DEP_BRANCH="$BACKEND_BRANCH_INPUT_COLLECTED" # Store for saving config

                if [ -d "$BACKEND_REPO_DIR/.git" ]; then
                    if (cd "$BACKEND_REPO_DIR" && git fetch origin > /dev/null 2>&1 && git rev-parse --verify "origin/$BACKEND_BRANCH_INPUT_COLLECTED" >/dev/null 2>&1); then
                        break
                    else
                        echo "❌ Branch '$BACKEND_BRANCH_INPUT_COLLECTED' not found on origin/spriced-backend. Please enter a valid branch name."
                    fi
                else
                    echo "⚠️ Warning: spriced-backend repository not found. Cannot validate branch name."
                    break
                fi
            done

            # Checkout the chosen branch for parts-pricing
            (
                cd "$REPO_DIR" || exit 1
                git fetch origin
                if git rev-parse --verify origin/"$CLIENT_BRANCH_INPUT_COLLECTED" >/dev/null 2>&1; then
                    echo "Switching to branch: $CLIENT_BRANCH_INPUT_COLLECTED"
                    git checkout -B "$CLIENT_BRANCH_INPUT_COLLECTED" origin/"$CLIENT_BRANCH_INPUT_COLLECTED"
                else
                    echo "❌ Branch '$CLIENT_BRANCH_INPUT_COLLECTED' not found on origin. Skipping '$REPO' build."
                    exit 1
                fi
            ) || { unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue; }

        # --- Generic handling for all other repositories (collect branch input) ---
        else
            DEFAULT_GENERIC_BRANCH="${BRANCH_CHOICES[$REPO]:-$DEFAULT_REPO_BRANCH}"
            read -rp "🌿 Enter branch for ${REPO} [default: $DEFAULT_GENERIC_BRANCH]: " BRANCH_INPUT_COLLECTED
            BRANCH_INPUT_COLLECTED="${BRANCH_INPUT_COLLECTED:-$DEFAULT_GENERIC_BRANCH}"
            BRANCH_CHOICES["$REPO"]="$BRANCH_INPUT_COLLECTED" # Store for saving config

            # Checkout the chosen branch for generic repo
            (
                cd "$REPO_DIR" || exit 1
                git fetch origin
                if git rev-parse --verify origin/"$BRANCH_INPUT_COLLECTED" >/dev/null 2>&1; then
                    echo "Switching to branch: $BRANCH_INPUT_COLLECTED"
                    git checkout -B "$BRANCH_INPUT_COLLECTED" origin/"$BRANCH_INPUT_COLLECTED"
                else
                    echo "❌ Branch '$BRANCH_INPUT_COLLECTED' not found on origin. Skipping '$REPO' build."
                    exit 1
                fi
            ) || { unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue; }
        fi
    fi
done

# === Save configuration for next run (after all inputs are gathered) ===
save_config

# --- Phase 2: Sequential Build of 'spriced-backend' (if selected and prepared) ---
# This ensures spriced-backend is built and its artifacts are available before dependents.
if [[ -v SELECTED_REPOS_MAP["spriced-backend"] ]]; then
    REPO="spriced-backend"
    SCRIPT="$SCRIPT_DIR/build_spriced_backend.sh"
    REPO_DIR="$CLONE_DIR/$REPO" # Already prepared in Phase 1
    LOG_FILE="$LOG_DIR/${REPO}_$(date +%Y%m%d%H%M%S).log"
    BRANCH="${BRANCH_CHOICES[$REPO]}" # Get the branch from the collected inputs

    echo -e "\n🏗️ Building $REPO sequentially..."
    # Add start timestamp to the log file for sequential build
    echo "$(date +'%Y-%m-%d %H:%M:%S') --- Build started for $REPO ---" >> "${LOG_FILE}"

    set +e # Temporarily disable 'exit on error'
    if "$SCRIPT" "$BRANCH" "$BASE_DIR" 2>&1 | while IFS= read -r line; do
        echo "$(date +'%Y-%m-%d %H:%M:%S') $line"
    done >> "${LOG_FILE}"; then
        BACKEND_BUILD_STATUS="SUCCESS"
    else
        BACKEND_BUILD_STATUS="FAIL"
    fi
    set -e # Re-enable 'exit on error'

    echo "${REPO},${BACKEND_BUILD_STATUS},${LOG_FILE}" >> "${TRACKER_FILE}"

    # Add end timestamp to the log file for sequential build
    echo "$(date +'%Y-%m-%d %H:%M:%S') --- Build finished for $REPO with status: $BACKEND_BUILD_STATUS ---" >> "${LOG_FILE}"

    if [[ "$BACKEND_BUILD_STATUS" == "FAIL" ]]; then
        echo "❌ spriced-backend build failed. Dependent projects will be skipped."
        exit 1 # Exit the main script if backend fails
    fi
    echo "✅ spriced-backend build completed successfully."
    unset SELECTED_REPOS_MAP["spriced-backend"] # Mark as processed for parallel stage
fi

# --- Phase 3: Prepare Parallel Commands for Remaining Repos ---
# This loop constructs the actual commands to be run in parallel using the collected inputs.
COMMANDS=() # Re-initialize COMMANDS array for parallel execution

for repo_name in "${!SELECTED_REPOS_MAP[@]}"; do
    # Find the index of the current repo_name in the REPOS array
    i=-1
    for j in "${!REPOS[@]}"; do
        if [[ "${REPOS[$j]}" == "$repo_name" ]]; then
            i=$j
            break
        fi
    done

    if [[ "$i" -eq -1 ]]; then
        echo "Error: Could not find index for repo $repo_name. Skipping."
        continue
    fi

    REPO="${REPOS[$i]}"
    SCRIPT="${BUILD_SCRIPTS[$i]}"
    LOG_FILE="$LOG_DIR/${REPO}_$(date +%Y%m%d%H%M%S).log" # New log file for parallel build

    # Construct arguments based on repo type, using previously collected values
    if [[ "$REPO" == "spriced-ui" ]]; then
        BRANCH="${UI_BRANCH}" # Use collected UI_BRANCH
        ENV_ARG="${UI_BUILD_ENV_CHOSEN}" # Use collected UI_BUILD_ENV_CHOSEN
        COMMANDS+=("build_and_log_repo \"$REPO\" \"$SCRIPT\" \"$LOG_FILE\" \"$TRACKER_FILE\" \"$BASE_DIR\" \"$ENV_ARG\" \"$BRANCH\"")
    elif [[ "$REPO" == "spriced-client-cummins-parts-pricing" ]]; then
        CLIENT_BRANCH="${CLIENT_PRICING_BRANCH}" # Use collected CLIENT_PRICING_BRANCH
        BACKEND_BRANCH_ARG="${BACKEND_DEP_BRANCH}" # Use collected BACKEND_DEP_BRANCH
        COMMANDS+=("build_and_log_repo \"$REPO\" \"$SCRIPT\" \"$LOG_FILE\" \"$TRACKER_FILE\" \"$BASE_DIR\" \"${CLIENT_BRANCH}\" \"${BACKEND_BRANCH_ARG}\"")
    else
        BRANCH="${BRANCH_CHOICES[$REPO]}" # Use collected generic branch
        COMMANDS+=("build_and_log_repo \"$REPO\" \"$SCRIPT\" \"$LOG_FILE\" \"$TRACKER_FILE\" \"$BASE_DIR\" \"${BRANCH}\"")
    fi
done

# --- Phase 4: Parallel Execution ---
CPU_CORES=$(nproc)
# The `--load 100%` flag tells parallel not to start new jobs if the 1-minute load average
# is already at 100% of the number of cores. This helps prevent the system from being overloaded.
echo -e "\n🚀 Running ${#COMMANDS[@]} builds in parallel with load balancing to keep CPU usage below 100%..."

if [ ${#COMMANDS[@]} -eq 0 ]; then
    echo "No parallel commands to execute. Exiting."
    exit 0
fi

set +e # Temporarily disable 'exit on error' for the parallel command
printf "%s\n" "${COMMANDS[@]}" | parallel -j "$CPU_CORES" --load 100% --no-notice --bar
PARALLEL_EXIT_CODE=$?
set -e # Re-enable 'exit on error'

END_TIME=$(date +"%Y-%m-%d %H:%M:%S")

# === Phase 5: Summary Output ===
echo -e "\n🧾 Build Summary:\n"
SUMMARY_CSV_FILE="$LOG_DIR/build-summary-${DATE_TAG}.csv"

if [[ -f "$TRACKER_FILE" ]]; then
    echo "Script Start Time,$START_TIME" > "$SUMMARY_CSV_FILE"
    echo "Script End Time,$END_TIME" >> "$SUMMARY_CSV_FILE"
    echo "---" >> "$SUMMARY_CSV_FILE"
    echo "Status,Repository,Log File" >> "$SUMMARY_CSV_FILE"
    while IFS=',' read -r REPO STATUS LOGFILE; do
        if [[ "$STATUS" == "SUCCESS" ]]; then
            echo "[✔️ DONE] $REPO - see log: $LOGFILE"
        else
            echo "[❌ FAIL] $REPO - see log: $LOGFILE"
        fi
        echo "$STATUS,$REPO,$LOGFILE" >> "$SUMMARY_CSV_FILE"
    done < "$TRACKER_FILE"
else
    echo "⚠️ Build tracker not found: $TRACKER_FILE"
    echo "Script execution was likely interrupted. No summary was generated."
fi

echo "📄 Detailed build summary also available at: $SUMMARY_CSV_FILE"
echo -e "\n✅ Script execution complete."

exit $PARALLEL_EXIT_CODE
