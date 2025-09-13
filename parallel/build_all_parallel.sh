#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -Eeuo pipefail
# Trap a command that fails and print an error message.
trap 'echo "[ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

CONFIG_FILE="$HOME/.repo_builder_config"

# --- GLOBAL VARIABLES ---
declare -g BASE_INPUT=""
declare -g SELECTED=()
declare -g UI_ENV=""
declare -g UI_BRANCH=""
declare -g UI_URL_SEPARATOR="."
declare -g CLIENT_PRICING_BRANCH=""
declare -g BACKEND_DEP_BRANCH=""
declare -g EXCEL_ADDIN_ENV=""
declare -gA BRANCH_CHOICES

save_config() {
    echo "Saving current configuration to $CONFIG_FILE..."
    {
        echo "BASE_INPUT=$BASE_INPUT"
        echo "SELECTED_REPOS=${SELECTED[*]}"
        echo "UI_ENV=$UI_ENV"
        echo "UI_BRANCH=$UI_BRANCH"
        echo "UI_URL_SEPARATOR=$UI_URL_SEPARATOR"
        echo "CLIENT_PRICING_BRANCH=$CLIENT_PRICING_BRANCH"
        echo "BACKEND_DEP_BRANCH=$BACKEND_DEP_BRANCH"
        echo "EXCEL_ADDIN_ENV=$EXCEL_ADDIN_ENV"
        for repo in "${!BRANCH_CHOICES[@]}"; do
            local var_name="BRANCH_${repo//-/_}"
            echo "$var_name=${BRANCH_CHOICES[$repo]}"
        done
    } > "$CONFIG_FILE"
    echo "Configuration saved."
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Loading previous inputs from $CONFIG_FILE..."
        while IFS='=' read -r key value; do
            case "$key" in
                BASE_INPUT) BASE_INPUT="$value" ;;
                SELECTED_REPOS) IFS=' ' read -r -a SELECTED <<< "$value" ;;
                UI_ENV) UI_ENV="$value" ;;
                UI_BRANCH) UI_BRANCH="$value" ;;
                UI_URL_SEPARATOR) UI_URL_SEPARATOR="$value" ;;
                CLIENT_PRICING_BRANCH) CLIENT_PRICING_BRANCH="$value" ;;
                BACKEND_DEP_BRANCH) BACKEND_DEP_BRANCH="$value" ;;
                EXCEL_ADDIN_ENV) EXCEL_ADDIN_ENV="$value" ;;
                BRANCH_*)
                    local repo_key="${key#BRANCH_}"
                    local repo_name="${repo_key//_/-}"
                    BRANCH_CHOICES["$repo_name"]="$value"
                    ;;
            esac
        done < "$CONFIG_FILE"
    fi
}

prepare_repo() {
    local repo_name="$1"
    local repo_dir="$2"
    local branch_to_checkout="$3"
    local repo_url="${REPO_URLS[$repo_name]}"
    echo "Checking '$repo_name' repository..."
    if [[ -d "$repo_dir/.git" ]]; then
        echo "Updating existing repo at $repo_dir"
        (
            cd "$repo_dir" || exit 1
            git fetch origin --prune
            git reset --hard HEAD
            git clean -fd
            if git rev-parse --verify "origin/$branch_to_checkout" >/dev/null 2>&1; then
                git checkout -B "$branch_to_checkout" "origin/$branch_to_checkout"
            else
                echo "Remote branch origin/$branch_to_checkout not found. Skipping '$repo_name'..."
                exit 1
            fi
        ) || { echo "Failed to prepare $repo_name. Skipping its build."; return 1; }
    else
        echo "Cloning new repo from $repo_url into $repo_dir"
        [[ -d "$repo_dir" && ! -d "$repo_dir/.git" ]] && rm -rf "$repo_dir"
        git clone "$repo_url" "$repo_dir" || { echo "Failed to clone $repo_name. Skipping its build."; return 1; }
        (cd "$repo_dir" && git checkout -B "$branch_to_checkout" "origin/$branch_to_checkout") || { echo "Failed to checkout branch in $repo_name. Skipping its build."; return 1; }
    fi
    return 0
}

build_and_log_repo() {
    local repo_name="$1"
    local script_path="$2"
    local log_file="$3"
    local tracker_file="$4"
    local base_dir_for_build_script="$5"
    shift 5
    local script_output
    local script_exit_code
    echo "$(date +'%Y-%m-%d %H:%M:%S') --- Build started for $repo_name ---" >> "${log_file}"
    set +e
    if script_output=$("${script_path}" "$@" "$base_dir_for_build_script" 2>&1); then
        script_exit_code=0
    else
        script_exit_code=$?
    fi
    set -e
    echo "$script_output" | while IFS= read -r line; do
        echo "$(date +'%Y-%m-%d %H:%M:%S') $line"
    done >> "${log_file}"
    local status="FAIL"
    if [[ "$script_exit_code" -eq 0 ]]; then
        status="SUCCESS"
    fi
    echo "${repo_name},${status},${log_file}" >> "${tracker_file}"
    echo "$(date +'%Y-%m-%d %H:%M:%S') --- Build finished for $repo_name with status: $status ---" >> "${log_file}"
}
export -f build_and_log_repo

load_config
START_TIME=$(date +"%Y-%m-%d %H:%M:%S")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRED_SETUP_SCRIPT="$SCRIPT_DIR/required-setup.sh"
if [[ -f "$REQUIRED_SETUP_SCRIPT" ]]; then
    read -rp "Do you want to run '$REQUIRED_SETUP_SCRIPT' to ensure all tools are set up? (y/N): " RUN_SETUP
    if [[ "${RUN_SETUP,,}" == "y" ]]; then
        echo "Running $REQUIRED_SETUP_SCRIPT..."
        "$REQUIRED_SETUP_SCRIPT"
        echo "required-setup.sh completed."
    else
        echo "Skipping required-setup.sh. Please ensure your environment is set up correctly."
    fi
else
    echo "Warning: required-setup.sh not found at $REQUIRED_SETUP_SCRIPT. Please ensure all necessary tools are installed manually."
fi

DEFAULT_BASE_INPUT="${BASE_INPUT:-"automation_worklogs"}"
read -rp "Enter base directory for cloning/building/logs (relative to ~) [default: $DEFAULT_BASE_INPUT]: " USER_BASE_INPUT
BASE_INPUT="${USER_BASE_INPUT:-$DEFAULT_BASE_INPUT}"
BASE_DIR="$HOME/$BASE_INPUT"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")
CLONE_DIR="$BASE_DIR/repos"
DEPLOY_DIR="$BASE_DIR/builds"
LOG_DIR="$BASE_DIR/automationlogs"
TRACKER_FILE="$LOG_DIR/build-tracker-${DATE_TAG}.csv"
mkdir -p "$CLONE_DIR" "$DEPLOY_DIR" "$LOG_DIR"

declare -A REPO_URLS=(
    ["spriced-ui"]="https://github.com/simaiserver/spriced-ui.git"
    ["spriced-backend"]="https://github.com/simaiserver/spriced-backend.git"
    ["spriced-client-cummins-parts-pricing"]="https://github.com/simaiserver/spriced-client-cummins-parts-pricing.git"
    ["spriced-client-cummins-data-ingestion"]="https://github.com/simaiserver/spriced-client-cummins-data-ingestion.git"
    ["Stocking-Segmentation-Enhancement"]="https://github.com/simaiserver/Stocking-Segmentation-Enhancement.git"
    ["spriced-platform"]="https://github.com/simaiserver/spriced-platform.git"
    ["nrp-cummins-outbound"]="https://github.com/simaiserver/nrp-cummins-outbound.git"
    ["spriced-excel-add-in"]="https://github.com/simaiserver/spriced-excel-add-in.git"
)
declare -A DEFAULT_BRANCHES=(
    ["spriced-ui"]="main"
    ["spriced-backend"]="main"
    ["spriced-client-cummins-parts-pricing"]="main"
    ["spriced-client-cummins-data-ingestion"]="main"
    ["Stocking-Segmentation-Enhancement"]="main"
    ["spriced-platform"]="main"
    ["nrp-cummins-outbound"]="develop"
    ["spriced-excel-add-in"]="develop"
)
export -A REPO_URLS
export -A DEFAULT_BRANCHES
export -A BRANCH_CHOICES

REPOS=(
    "spriced-backend"
    "spriced-platform"
    "nrp-cummins-outbound"
    "spriced-ui"
    "spriced-client-cummins-data-ingestion"
    "Stocking-Segmentation-Enhancement"
    "spriced-client-cummins-parts-pricing"
    "spriced-excel-add-in"
)

BUILD_SCRIPTS=(
    "$SCRIPT_DIR/build_spriced_backend.sh"
    "$SCRIPT_DIR/build_spriced_platform.sh"
    "$SCRIPT_DIR/build_nrp_cummins_outbound.sh"
    "$SCRIPT_DIR/build_spriced_ui.sh"
    "$SCRIPT_DIR/build_spriced_client_cummins_data_ingestion.sh"
    "$SCRIPT_DIR/build_stocking_segmentation_enhancement.sh"
    "$SCRIPT_DIR/build_spriced_client_cummins_parts_pricing.sh"
    "$SCRIPT_DIR/build_spriced_excel_add_in.sh"
)
echo -e "\n Available Repositories:"
for i in "${!REPOS[@]}"; do
    printf "  %d) %s\n" "$((i+1))" "${REPOS[$i]}"
done
echo "  0) ALL"
DEFAULT_SELECTED_PROMPT="${SELECTED[*]:-8}"
read -rp $'\n Enter repo numbers to build (space-separated or 0 for all) [default: '"$DEFAULT_SELECTED_PROMPT"']: ' -a USER_SELECTED_INPUT
if [[ -n "${USER_SELECTED_INPUT[*]}" ]]; then
    SELECTED=("${USER_SELECTED_INPUT[@]}")
fi
if [[ "${SELECTED[0]}" == "0" || "${SELECTED[0],,}" == "all" ]]; then
    SELECTED=($(seq 1 ${#REPOS[@]}))
fi
declare -A SELECTED_REPOS_MAP
for idx_str in "${SELECTED[@]}"; do
    idx="$idx_str"
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#REPOS[@]} )); then
        echo "Invalid selection: $idx. Skipping..."
        continue
    fi
    i=$((idx - 1))
    SELECTED_REPOS_MAP["${REPOS[$i]}"]=1
done

UI_BUILD_ENV_CHOSEN=""
for repo_name_to_process in "${REPOS[@]}"; do
    if [[ -v SELECTED_REPOS_MAP["$repo_name_to_process"] ]]; then
        i=-1
        for j in "${!REPOS[@]}"; do
            if [[ "${REPOS[$j]}" == "$repo_name_to_process" ]]; then
                i=$j
                break
            fi
        done

        if [[ "$i" -eq -1 ]]; then
            echo "Error: Could not find index for repo $repo_name_to_process. Skipping."
            unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue
        fi

        REPO="${REPOS[$i]}"
        SCRIPT_PATH_FOR_REPO="${BUILD_SCRIPTS[$i]}"
        REPO_DIR="$CLONE_DIR/$REPO"
        DEFAULT_REPO_BRANCH="${DEFAULT_BRANCHES[$REPO]}"

        echo -e "\nChecking '$REPO' repository..."
        if [[ -d "$REPO_DIR/.git" ]]; then
            echo "Updating existing repo at $REPO_DIR"
            (
                cd "$REPO_DIR" || exit 1
                git fetch origin --prune
                git reset --hard HEAD
                git clean -fd
                if git rev-parse --verify "origin/$DEFAULT_REPO_BRANCH" >/dev/null 2>&1; then
                    git checkout -B "$DEFAULT_REPO_BRANCH" origin/"$DEFAULT_REPO_BRANCH"
                else
                    echo "Remote branch origin/$DEFAULT_REPO_BRANCH not found. Skipping '$REPO'..."
                    exit 1
                fi
            ) || { echo "Failed to prepare $REPO. Skipping its build."; unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue; }
        else
            echo "Cloning new repo from ${REPO_URLS[$REPO]} into "$REPO_DIR""
            [[ -d "$REPO_DIR" && ! -d "$REPO_DIR/.git" ]] && rm -rf "$REPO_DIR"
            git clone "${REPO_URLS[$REPO]}" "$REPO_DIR" || { echo "Failed to clone $REPO. Skipping its build."; unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue; }
            (cd "$REPO_DIR" || exit 1) || { echo "Failed to enter $REPO directory. Skipping its build."; unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue; }
        fi

        # --- Collect user input for branch/environment ---
        if [[ "$REPO" == "spriced-ui" ]]; then
            PIPELINE_DIR="$BASE_DIR/spriced-pipeline"
            PIPELINE_URL="https://github.com/simaiserver/spriced-pipeline.git"

            echo "Checking spriced-pipeline repository at $PIPELINE_DIR..."
            if [[ -d "$PIPELINE_DIR/.git" ]]; then
                echo "Updating existing spriced-pipeline repo."
                git -C "$PIPELINE_DIR" pull --quiet
            else
                echo "Cloning spriced-pipeline repo from $PIPELINE_URL into $PIPELINE_DIR."
                git clone --quiet "$PIPELINE_URL" "$PIPELINE_DIR" || { echo "Failed to clone spriced-pipeline. Skipping spriced-ui build."; unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue; }
            fi

            declare -a AVAILABLE_ENVS=()
            PIPELINE_FRONTEND_DIR="$PIPELINE_DIR/framework/frontend"
            if [ ! -d "$PIPELINE_FRONTEND_DIR" ]; then
                echo "Directory not found: $PIPELINE_FRONTEND_DIR. Cannot determine environments."
                unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue
            fi

            while IFS= read -r -d '' dir; do
                env_name=$(basename "$dir" | sed 's/nrp-//')
                AVAILABLE_ENVS+=("$env_name")
            done < <(find "$PIPELINE_FRONTEND_DIR" -maxdepth 1 -type d -name "nrp-*" -print0)

            echo -e "\nChoose environment for spriced-ui:"
            for env_idx in "${!AVAILABLE_ENVS[@]}"; do
                printf "  %d) %s\n" "$((env_idx+1))" "${AVAILABLE_ENVS[$env_idx]}"
            done

            FULL_URL_OPTION=$(( ${#AVAILABLE_ENVS[@]} + 1 ))
            CREATE_NEW_OPTION=$(( ${#AVAILABLE_ENVS[@]} + 2 ))

            echo "  $FULL_URL_OPTION) Enter a full URL..."
            echo "  $CREATE_NEW_OPTION) Create New..."

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
                read -rp "Enter environment number [default: $DEFAULT_ENV_CHOICE]: " ENV_NUM_INPUT
                ENV_NUM_CHOICE="${ENV_NUM_INPUT:-$DEFAULT_ENV_CHOICE}"

                if [[ "$ENV_NUM_CHOICE" =~ ^[0-9]+$ ]] && (( ENV_NUM_CHOICE == FULL_URL_OPTION )); then
                    read -rp "Enter full URL (e.g., https://nrp-nitin.alpha.simadvisory.com): " FULL_URL_INPUT
                    ENV_INPUT_COLLECTED="$FULL_URL_INPUT"
                    if [[ -z "$ENV_INPUT_COLLECTED" ]]; then
                        echo "URL cannot be empty. Please try again."
                        continue
                    fi
                    UI_URL_SEPARATOR="."
                    break

                elif [[ "$ENV_NUM_CHOICE" =~ ^[0-9]+$ ]] && (( ENV_NUM_CHOICE == CREATE_NEW_OPTION )); then
                    read -rp "Enter new environment name (e.g., prasanth): " NEW_ENV_NAME
                    ENV_INPUT_COLLECTED="$NEW_ENV_NAME"
                    if [ -z "$ENV_INPUT_COLLECTED" ]; then
                        echo "Environment name cannot be empty. Please try again."
                        continue
                    fi
                    NEW_ENV_DIR="$PIPELINE_FRONTEND_DIR/nrp-$ENV_INPUT_COLLECTED"
                    if [ -d "$NEW_ENV_DIR" ]; then
                        echo "Environment '$ENV_INPUT_COLLECTED' already exists. Please choose a different name."
                        continue
                    fi
                    mkdir -p "$NEW_ENV_DIR"
                    echo "Created directory for new environment '$ENV_INPUT_COLLECTED' in spriced-pipeline."
                    if [ -d "$PIPELINE_FRONTEND_DIR/nrp-dev" ]; then
                        cp -r "$PIPELINE_FRONTEND_DIR/nrp-dev/"* "$NEW_ENV_DIR/"
                        echo "Initial .env files copied from 'dev' to new environment."
                    else
                        echo "warning: 'nrp-dev' environment not found to copy initial .env files from."
                        echo "Please manually configure .env files and module-federation.manifest.json in '$NEW_ENV_DIR' for each microfrontend."
                    fi
                    break
                elif [[ "$ENV_NUM_CHOICE" =~ ^[0-9]+$ ]] && (( ENV_NUM_CHOICE >= 1 && ENV_NUM_CHOICE <= ${#AVAILABLE_ENVS[@]} )); then
                    ENV_INPUT_COLLECTED="${AVAILABLE_ENVS[$((ENV_NUM_CHOICE-1))]}"
                    break
                else
                    echo "Invalid input. Please enter a valid number."
                fi
            done

            UI_ENV="$ENV_INPUT_COLLECTED"
            UI_BUILD_ENV_CHOSEN="$ENV_INPUT_COLLECTED"

            DEFAULT_UI_BRANCH="${UI_BRANCH:-$DEFAULT_REPO_BRANCH}"
            read -rp "Enter branch name for spriced-ui [default: $DEFAULT_UI_BRANCH]: " BRANCH_INPUT_COLLECTED
            BRANCH_INPUT_COLLECTED="${BRANCH_INPUT_COLLECTED:-$DEFAULT_UI_BRANCH}"
            UI_BRANCH="$BRANCH_INPUT_COLLECTED"
            BRANCH_CHOICES["$REPO"]="$BRANCH_INPUT_COLLECTED"

            if [[ ! "$UI_ENV" =~ ^https?:\/\/.*simadvisory\.com$ ]]; then
                DEFAULT_SEPARATOR="${UI_URL_SEPARATOR:-.}"
                read -rp "Choose URL separator for spriced-ui ('-' for hyphen, '.' for dot) [default: $DEFAULT_SEPARATOR]: " SEPARATOR_INPUT
                UI_URL_SEPARATOR="${SEPARATOR_INPUT:-$DEFAULT_SEPARATOR}"
            fi

            BACKUP_DIR="/tmp/spriced_ui_backup_$DATE_TAG"
            mkdir -p "$BACKUP_DIR"
            find "$REPO_DIR/apps/" -maxdepth 2 -type f -name ".env" -exec mv {} "$BACKUP_DIR" \; 2>/dev/null || true
            mv "$REPO_DIR/package-lock.json" "$BACKUP_DIR/" 2>/dev/null || true

            (
                cd "$REPO_DIR" || exit 1
                git fetch origin
                if git rev-parse --verify origin/"$BRANCH_INPUT_COLLECTED" >/dev/null 2>&1; then
                    echo "Switching to branch: $BRANCH_INPUT_COLLECTED"
                    git checkout -B "$BRANCH_INPUT_COLLECTED" origin/"$BRANCH_INPUT_COLLECTED"
                else
                    echo "Branch '$BRANCH_INPUT_COLLECTED' not found on origin. Skipping spriced-ui build."
                    exit 1
                fi
            ) || { unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue; }
            echo "Restoring backed up .env files and package-lock.json..."
            find "$BACKUP_DIR" -maxdepth 1 -type f -name ".env" -exec cp {} "$REPO_DIR/apps/" \; 2>/dev/null || true
            cp "$BACKUP_DIR/package-lock.json" "$REPO_DIR/" 2>/dev/null || true
            rm -rf "$BACKUP_DIR"
        # --- Special handling for 'spriced-client-cummins-parts-pricing' ---
        elif [[ "$REPO" == "spriced-client-cummins-parts-pricing" ]]; then
            DEFAULT_CLIENT_BRANCH="${CLIENT_PRICING_BRANCH:-$DEFAULT_REPO_BRANCH}"
            read -rp "Enter branch for ${REPO} [default: $DEFAULT_CLIENT_BRANCH]: " CLIENT_BRANCH_INPUT_COLLECTED
            CLIENT_BRANCH_INPUT_COLLECTED="${CLIENT_BRANCH_INPUT_COLLECTED:-$DEFAULT_CLIENT_BRANCH}"
            CLIENT_PRICING_BRANCH="$CLIENT_BRANCH_INPUT_COLLECTED"
            BRANCH_CHOICES["$REPO"]="$CLIENT_BRANCH_INPUT_COLLECTED"

            BACKEND_REPO_DIR="$CLONE_DIR/spriced-backend"
            while true; do
                DEFAULT_BACKEND_BRANCH_DEP="${BACKEND_DEP_BRANCH:-${DEFAULT_BRANCHES['spriced-backend']}}"
                read -rp "Enter branch for spriced-backend (dependency) [default: $DEFAULT_BACKEND_BRANCH_DEP]: " BACKEND_BRANCH_INPUT_COLLECTED
                BACKEND_BRANCH_INPUT_COLLECTED="${BACKEND_BRANCH_INPUT_COLLECTED:-$DEFAULT_BACKEND_BRANCH_DEP}"
                BACKEND_DEP_BRANCH="$BACKEND_BRANCH_INPUT_COLLECTED"
                if [ -d "$BACKEND_REPO_DIR/.git" ]; then
                    if (cd "$BACKEND_REPO_DIR" && git fetch origin > /dev/null 2>&1 && git rev-parse --verify "origin/$BACKEND_BRANCH_INPUT_COLLECTED" >/dev/null 2>&1); then
                        break
                    else
                        echo "Branch '$BACKEND_BRANCH_INPUT_COLLECTED' not found on origin/spriced-backend. Please enter a valid branch name."
                    fi
                else
                    echo "Warning: spriced-backend repository not found. Cannot validate branch name."
                    break
                fi
            done
            
            (
                cd "$REPO_DIR" || exit 1
                git fetch origin
                if git rev-parse --verify origin/"$CLIENT_BRANCH_INPUT_COLLECTED" >/dev/null 2>&1; then
                    echo "Switching to branch: $CLIENT_BRANCH_INPUT_COLLECTED"
                    git checkout -B "$CLIENT_BRANCH_INPUT_COLLECTED" origin/"$CLIENT_BRANCH_INPUT_COLLECTED"
                else
                    echo "Branch '$CLIENT_BRANCH_INPUT_COLLECTED' not found on origin. Skipping '$REPO' build."
                    exit 1
                fi
            ) || { unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue; }
        # --- Special handling for 'spriced-excel-add-in' ---
        elif [[ "$REPO" == "spriced-excel-add-in" ]]; then
            DEFAULT_EXCEL_BRANCH="${BRANCH_CHOICES[$REPO]:-$DEFAULT_REPO_BRANCH}"
            read -rp "Enter branch for ${REPO} [default: $DEFAULT_EXCEL_BRANCH]: " EXCEL_BRANCH_INPUT_COLLECTED
            EXCEL_BRANCH_INPUT_COLLECTED="${EXCEL_BRANCH_INPUT_COLLECTED:-$DEFAULT_EXCEL_BRANCH}"
            BRANCH_CHOICES["$REPO"]="$EXCEL_BRANCH_INPUT_COLLECTED"
            
            (
                cd "$REPO_DIR" || exit 1
                git fetch origin
                if git rev-parse --verify origin/"$EXCEL_BRANCH_INPUT_COLLECTED" >/dev/null 2>&1; then
                    echo "Switching to branch: $EXCEL_BRANCH_INPUT_COLLECTED"
                    git checkout -B "$EXCEL_BRANCH_INPUT_COLLECTED" origin/"$EXCEL_BRANCH_INPUT_COLLECTED"
                else
                    echo "Branch '$EXCEL_BRANCH_INPUT_COLLECTED' not found on origin. Skipping '$REPO' build."
                    exit 1
                fi
            ) || { unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue; }

            declare -a EXCEL_ENVS=("dev" "uat" "staging" "test" "qa" "prod")
            echo -e "\nAvailable environments for spriced-excel-add-in:"
            for env_idx in "${!EXCEL_ENVS[@]}"; do
                printf "  %d) %s\n" "$((env_idx+1))" "${EXCEL_ENVS[$env_idx]}"
            done

            DEFAULT_ENV_CHOICE=1
            if [[ -n "$EXCEL_ADDIN_ENV" ]]; then
                for env_idx in "${!EXCEL_ENVS[@]}"; do
                    if [[ "${EXCEL_ENVS[$env_idx]}" == "$EXCEL_ADDIN_ENV" ]]; then
                        DEFAULT_ENV_CHOICE=$((env_idx+1))
                        break
                    fi
                done
            fi

            while true; do
                read -rp "Enter environment number [default: $DEFAULT_ENV_CHOICE]: " ENV_NUM_INPUT
                ENV_NUM_CHOICE="${ENV_NUM_INPUT:-$DEFAULT_ENV_CHOICE}"

                if [[ "$ENV_NUM_CHOICE" =~ ^[0-9]+$ ]] && (( ENV_NUM_CHOICE >= 1 && ENV_NUM_CHOICE <= ${#EXCEL_ENVS[@]} )); then
                    EXCEL_ADDIN_ENV="${EXCEL_ENVS[$((ENV_NUM_CHOICE-1))]}"
                    break
                else
                    echo "Invalid input. Please enter a valid number."
                fi
            done
        # --- Generic handling for all other repositories ---
        else
            DEFAULT_GENERIC_BRANCH="${BRANCH_CHOICES[$REPO]:-$DEFAULT_REPO_BRANCH}"
            read -rp "Enter branch for ${REPO} [default: $DEFAULT_GENERIC_BRANCH]: " BRANCH_INPUT_COLLECTED
            BRANCH_INPUT_COLLECTED="${BRANCH_INPUT_COLLECTED:-$DEFAULT_GENERIC_BRANCH}"
            BRANCH_CHOICES["$REPO"]="$BRANCH_INPUT_COLLECTED"
            
            (
                cd "$REPO_DIR" || exit 1
                git fetch origin
                if git rev-parse --verify origin/"$BRANCH_INPUT_COLLECTED" >/dev/null 2>&1; then
                    echo "Switching to branch: $BRANCH_INPUT_COLLECTED"
                    git checkout -B "$BRANCH_INPUT_COLLECTED" origin/"$BRANCH_INPUT_COLLECTED"
                else
                    echo "Branch '$BRANCH_INPUT_COLLECTED' not found on origin. Skipping '$REPO' build."
                    exit 1
                fi
            ) || { unset SELECTED_REPOS_MAP["$repo_name_to_process"]; continue; }
        fi
    fi
done

save_config

if [[ -v SELECTED_REPOS_MAP["spriced-backend"] ]]; then
    REPO="spriced-backend"
    SCRIPT="$SCRIPT_DIR/build_spriced_backend.sh"
    LOG_FILE="$LOG_DIR/${REPO}_$(date +%Y%m%d%H%M%S).log"
    BRANCH="${BRANCH_CHOICES[$REPO]}"
    echo -e "\nBuilding $REPO sequentially..."
    echo "$(date +'%Y-%m-%d %H:%M:%S') --- Build started for $REPO ---" >> "${LOG_FILE}"
    set +e
    if "$SCRIPT" "$BRANCH" "$BASE_DIR" 2>&1 | while IFS= read -r line; do
        echo "$(date +'%Y-%m-%d %H:%M:%S') $line"
    done >> "${LOG_FILE}"; then
        BACKEND_BUILD_STATUS="SUCCESS"
    else
        BACKEND_BUILD_STATUS="FAIL"
    fi
    set -e
    echo "${REPO},${BACKEND_BUILD_STATUS},${LOG_FILE}" >> "${TRACKER_FILE}"
    echo "$(date +'%Y-%m-%d %H:%M:%S') --- Build finished for $REPO with status: $BACKEND_BUILD_STATUS ---" >> "${LOG_FILE}"
    if [[ "$BACKEND_BUILD_STATUS" == "FAIL" ]]; then
        echo "spriced-backend build failed. Dependent projects will be skipped."
        exit 1
    fi
    echo "spriced-backend build completed successfully."
    unset SELECTED_REPOS_MAP["spriced-backend"]
fi

COMMANDS=()
for repo_name in "${!SELECTED_REPOS_MAP[@]}"; do
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
    LOG_FILE="$LOG_DIR/${REPO}_$(date +%Y%m%d%H%M%S).log"
    current_repo_branch="${BRANCH_CHOICES[$REPO]:-${DEFAULT_BRANCHES[$REPO]}}"
    if [[ "$REPO" == "spriced-ui" ]]; then
        COMMANDS+=("build_and_log_repo \"$REPO\" \"$SCRIPT\" \"$LOG_FILE\" \"$TRACKER_FILE\" \"$BASE_DIR\" \"$UI_BUILD_ENV_CHOSEN\" \"$current_repo_branch\" \"$UI_URL_SEPARATOR\"")
    elif [[ "$REPO" == "spriced-client-cummins-parts-pricing" ]]; then
        COMMANDS+=("build_and_log_repo \"$REPO\" \"$SCRIPT\" \"$LOG_FILE\" \"$TRACKER_FILE\" \"$BASE_DIR\" \"$CLIENT_PRICING_BRANCH\" \"$BACKEND_DEP_BRANCH\"")
    elif [[ "$REPO" == "spriced-excel-add-in" ]]; then
        COMMANDS+=("build_and_log_repo \"$REPO\" \"$SCRIPT\" \"$LOG_FILE\" \"$TRACKER_FILE\" \"$BASE_DIR\" \"$current_repo_branch\" \"$EXCEL_ADDIN_ENV\"")
    else
        COMMANDS+=("build_and_log_repo \"$REPO\" \"$SCRIPT\" \"$LOG_FILE\" \"$TRACKER_FILE\" \"$BASE_DIR\" \"$current_repo_branch\"")
    fi
done

CPU_CORES=$(nproc)
MAX_JOBS=$(( (CPU_CORES * 80 + 99) / 100 ))
echo -e "\n🚀 Running ${#COMMANDS[@]} builds in parallel, limited to ~80% of CPU capacity..."

if [ ${#COMMANDS[@]} -eq 0 ]; then
    echo "No parallel commands to execute. Exiting."
    exit 0
fi

set +e
printf "%s\n" "${COMMANDS[@]}" | parallel -j "$MAX_JOBS" --load 80% --no-notice --bar
PARALLEL_EXIT_CODE=$?
set -e

END_TIME=$(date +"%Y-%m-%d %H:%M:%S")

echo -e "\n Build Summary:\n"

SUMMARY_CSV_FILE="$LOG_DIR/build-summary-${DATE_TAG}.csv"

if [[ -f "$TRACKER_FILE" ]]; then
    echo "Script Start Time,$START_TIME" > "$SUMMARY_CSV_FILE"
    echo "Script End Time,$END_TIME" >> "$SUMMARY_CSV_FILE"
    echo "---" >> "$SUMMARY_CSV_FILE"
    echo "Status,Repository,Log File" >> "$SUMMARY_CSV_FILE"
    while IFS=',' read -r REPO STATUS LOGFILE; do
        if [[ "$STATUS" == "SUCCESS" ]]; then
            echo "[DONE] $REPO - see log: $LOGFILE"
        else
            echo "[FAIL] $REPO - see log: $LOGFILE"
        fi
        echo "$STATUS,$REPO,$LOGFILE" >> "$SUMMARY_CSV_FILE"
    done < "$TRACKER_FILE"
else
    echo "Build tracker not found: $TRACKER_FILE"
    echo "Script execution was likely interrupted. No summary was generated."
fi

echo "Detailed build summary also available at: $SUMMARY_CSV_FILE"
echo -e "\n Script execution complete."
exit $PARALLEL_EXIT_CODE
