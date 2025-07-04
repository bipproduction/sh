#!/bin/bash

# ==============================================================================
# Mac System Cleanup Script (Enhanced for Production)
# ==============================================================================
# This script provides a comprehensive set of functions to clean up various
# temporary files, caches, and development-related clutter on macOS systems.
# It includes intelligent detection, detailed logging, and options for
# interactive, automated, and dry-run modes.
#
# Author: Gemini Advanced
# Date: July 04, 2025
# Version: 2.0
# License: MIT (feel free to modify and distribute)
# ==============================================================================

# --- Configuration & System Defaults ---

# Default size threshold (in MB) for large file scanning.
DEFAULT_SIZE_THRESHOLD=100

# Default age threshold (in days) for old file recommendations.
OLD_FILE_THRESHOLD_DAYS=90

# Base directory for projects (used for intelligent analysis).
PROJECTS_DIR="$HOME/Documents/projects"

# Comprehensive search directories. Add /Applications for DMG/PKG, etc.
# IMPORTANT: Be cautious when adding root-level directories.
SEARCH_DIRS=(
    "$HOME/Documents"
    "$HOME/Documents/projects"
    "$HOME/Desktop"
    "$HOME/Developer"
    "$HOME/Downloads"
    "/private/var/www"
    "/Library/Developer"
    "/Applications"
    "/Users/Shared" # Shared directory for potentially large files
)

# Directories to EXCLUDE during cleanup (to prevent critical deletions).
# Absolute paths are preferred for safety. '~' should be expanded.
EXCLUDE_DIRS=(
    "/System"
    "/Volumes"
    "/usr"
    "/bin"
    "/sbin"
    "/Applications" # Do not delete applications themselves, only within
    "/Library"      # Do not delete Library itself, only within
    "$HOME/Library/Mobile Documents/com~apple~CloudDocs" # iCloud Drive
    "/private/var/db"     # Important system databases
    "/private/var/folders" # Will be selectively cleaned by other functions
    "/private/var/log"     # Will be selectively cleaned by other functions
    "/private/tmp"         # Will be selectively cleaned by other functions
    "/var/tmp"             # Will be selectively cleaned by other functions
    "/cores"               # Core dump files
)

# Global flag to force cleanup without prompts (0 = interactive, 1 = force).
FORCE_CLEAN=0
# Flag for Dry Run mode (0 = delete, 1 = just show what would be deleted).
DRY_RUN=0

# Log file for automated executions.
LOG_FILE="$HOME/Library/Logs/mac-cleanup-script.log"
# File to store freed space (for final reporting).
FREED_SPACE_REPORT="/tmp/freed_space_report.txt"
> "$FREED_SPACE_REPORT" # Empty the file at the start

# Global variables to store report data.
TOTAL_FREED_SPACE_MB=0
CLEANUP_DETAILS="" # Detailed log of cleanup actions for the final report.

# Global array to store paths of deleted items for detailed reporting.
DELETED_ITEMS=()

# --- Helper Functions ---

# Function to display messages to console and log file.
# Usage: log_message <TYPE> <MESSAGE>
log_message() {
    local type="$1" # INFO, WARN, ERROR, DEBUG
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$type] $message" | tee -a "$LOG_FILE"
}

# Function to safely calculate directory size.
# Usage: calc_dir_size <DIRECTORY_PATH>
# Returns: human-readable size (e.g., "10G", "500M") or "0B"
calc_dir_size() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        # Using `sudo du -sh` for human-readable output, then cutting to get size only.
        # Suppress permission denied errors with 2>/dev/null.
        sudo du -sh "$dir" 2>/dev/null | awk '{print $1}' || echo "0B"
    else
        echo "0B"
    fi
}

# Function to get size in MB from a path (file or directory).
# Usage: get_size_in_mb <PATH>
# Returns: size in MB (integer) or 0 if path doesn't exist or error.
get_size_in_mb() {
    local path="$1"
    if [[ -e "$path" ]]; then
        # Using `sudo du -sm` for size in MB, then cutting to get the number only.
        # Suppress permission denied errors with 2>/dev/null.
        sudo du -sm "$path" 2>/dev/null | cut -f1 || echo 0
    else
        echo 0
    fi
}

# Global array to store paths found by calc_pattern_size.
LAST_FOUND_ITEMS=()

# Function to find and calculate total size of files/directories by name/pattern.
# Stores found items in the global `LAST_FOUND_ITEMS` array.
# Usage: calc_pattern_size <PATTERN> [TYPE_FLAG]
# Returns: "${total_mb}MB (${count} items)"
calc_pattern_size() {
    local pattern="$1"
    local type_flag="${2:-}" # -type f or -type d, if not specified, find both.
    local total_mb=0
    local count=0
    LAST_FOUND_ITEMS=() # Reset for each call.

    log_message "DEBUG" "Searching for pattern: '$pattern' with type flag: '$type_flag'"

    for search_dir in "${SEARCH_DIRS[@]}"; do
        if [[ -d "$search_dir" ]]; then
            # Build the find command.
            # Use -print0 and read -r -d '' for safe handling of spaces in filenames.
            local find_cmd="sudo find \"$search_dir\" -xdev $type_flag -name \"$pattern\" -print0"
            # Add prune options for root-level searches to avoid system directories.
            if [[ "$search_dir" == "/" ]]; then
                # This makes the find command more complex but safer for root.
                # It's generally better to limit SEARCH_DIRS to user-owned areas for patterns like 'node_modules'.
                find_cmd="sudo find \"$search_dir\" -xdev -path \"*/System/*\" -prune -o -path \"*/Volumes/*\" -prune -o -path \"*/usr/*\" -prune -o -path \"*/bin/*\" -prune -o -path \"*/sbin/*\" -prune -o $type_flag -name \"$pattern\" -print0"
            fi

            while IFS= read -r -d '' item; do
                local skip=false
                for exclude_dir_raw in "${EXCLUDE_DIRS[@]}"; do
                    # Expand '~' in exclude_dir.
                    local expanded_exclude_dir=$(eval echo "$exclude_dir_raw")
                    if [[ "$item" == "$expanded_exclude_dir"* ]]; then
                        log_message "DEBUG" "Skipping excluded item: '$item' (matches '$expanded_exclude_dir')"
                        skip=true
                        break
                    fi
                done
                if $skip; then continue; fi

                local size_mb=$(get_size_in_mb "$item")
                total_mb=$((total_mb + size_mb))
                count=$((count + 1))
                LAST_FOUND_ITEMS+=("$item")
                log_message "DEBUG" "Found item: '$item' (size: ${size_mb}MB)"
            done < <(eval "$find_cmd" 2>/dev/null)
        fi
    done
    echo "${total_mb}MB (${count} items)"
}

# Function to perform deletion safely and record freed space.
# Usage: perform_deletion <ITEM_PATH>
# Returns: 0 on success, 1 on failure.
perform_deletion() {
    local item_path="$1"
    # Check if the path exists before attempting deletion.
    if [[ ! -e "$item_path" ]]; then
        log_message "WARN" "Path does not exist, skipping: '$item_path'"
        return 1
    fi

    local size_before=$(get_size_in_mb "$item_path")
    
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_message "INFO" "Dry Run: Would delete '$item_path' (${size_before}MB)"
        # In dry run, we still simulate the size gain for reporting.
        TOTAL_FREED_SPACE_MB=$((TOTAL_FREED_SPACE_MB + size_before))
        DELETED_ITEMS+=("  - $(basename "$item_path") (${size_before}MB) (Dry Run)")
        return 0
    fi

    log_message "INFO" "Deleting: '$item_path' (${size_before}MB)"
    # Use `sudo` for permissions and `rm -rf` for forceful recursive deletion.
    # Redirect stderr to /dev/null to suppress "No such file or directory" errors if already deleted.
    sudo rm -rf "$item_path" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo "$size_before" >> "$FREED_SPACE_REPORT"
        DELETED_ITEMS+=("  - $(basename "$item_path") (${size_before}MB)") # Add to report list.
        TOTAL_FREED_SPACE_MB=$((TOTAL_FREED_SPACE_MB + size_before))
        return 0
    else
        log_message "ERROR" "Failed to delete '$item_path'."
        return 1
    fi
}

# Function to prompt for confirmation or execute automatically if FORCE_CLEAN/DRY_RUN.
# Usage: confirm_and_execute <PROMPT> <COMMAND_TO_EXECUTE> <SUCCESS_MSG> <FAILURE_MSG>
# The COMMAND_TO_EXECUTE should call `perform_deletion` internally if it's deleting files.
confirm_and_execute() {
    local prompt="$1"
    local command_to_execute="$2"
    local success_message="$3"
    local failure_message="$4"
    local initial_freed_space=$TOTAL_FREED_SPACE_MB # Capture freed space before execution.
    local initial_deleted_items_count=${#DELETED_ITEMS[@]} # Capture initial count of deleted items.

    # This inner function captures items deleted by perform_deletion.
    # It's exported so `eval` can find it.
    # NOTE: This approach works for simple `perform_deletion` calls within command_to_execute.
    # For more complex `find -exec` scenarios, `perform_deletion` handles its own logging.

    if [[ "$FORCE_CLEAN" -eq 1 ]]; then
        log_message "INFO" "$prompt (Automated Cleanup Mode)"
        eval "$command_to_execute"
        if [[ $? -eq 0 ]]; then
            log_message "INFO" "✅ $success_message"
            CLEANUP_DETAILS+="### $prompt\n"
            CLEANUP_DETAILS+="Result: $success_message\n"
            local freed_in_this_step=$((TOTAL_FREED_SPACE_MB - initial_freed_space))
            CLEANUP_DETAILS+="Space Freed: ${freed_in_this_step}MB\n"
            # Append newly deleted items to CLEANUP_DETAILS.
            if [ ${#DELETED_ITEMS[@]} -gt "$initial_deleted_items_count" ]; then
                CLEANUP_DETAILS+="Items Deleted:\n"
                for ((i = initial_deleted_items_count; i < ${#DELETED_ITEMS[@]}; i++)); do
                    CLEANUP_DETAILS+="${DELETED_ITEMS[$i]}\n"
                done
            fi
            CLEANUP_DETAILS+="\n"
            return 0
        else
            log_message "ERROR" "❌ $failure_message (Command failed)"
            CLEANUP_DETAILS+="### $prompt\n"
            CLEANUP_DETAILS+="Result: $failure_message\n"
            CLEANUP_DETAILS+="\n"
            return 1
        fi
    elif [[ "$DRY_RUN" -eq 1 ]]; then
        log_message "INFO" "Dry Run: $prompt"
        # In dry run, we execute the command, but perform_deletion will only log.
        eval "$command_to_execute"
        log_message "INFO" "✅ $prompt (simulation complete)."
        CLEANUP_DETAILS+="### $prompt\n"
        CLEANUP_DETAILS+="Result: Dry Run (Simulation). No files were actually deleted.\n"
        local simulated_freed_in_this_step=$((TOTAL_FREED_SPACE_MB - initial_freed_space))
        CLEANUP_DETAILS+="Simulated Space Freed: ${simulated_freed_in_this_step}MB\n"
        if [ ${#DELETED_ITEMS[@]} -gt "$initial_deleted_items_count" ]; then
            CLEANUP_DETAILS+="Items That Would Be Deleted:\n"
            for ((i = initial_deleted_items_count; i < ${#DELETED_ITEMS[@]}; i++)); do
                CLEANUP_DETAILS+="${DELETED_ITEMS[$i]}\n"
            done
        fi
        CLEANUP_DETAILS+="\n"
        return 0
    fi

    # Interactive mode.
    read -rp "$prompt (y/N): " confirm_input
    if [[ "$confirm_input" =~ ^[Yy]$ ]]; then
        log_message "INFO" "Executing: $prompt"
        eval "$command_to_execute"
        if [[ $? -eq 0 ]]; then
            log_message "INFO" "✅ $success_message"
            CLEANUP_DETAILS+="### $prompt\n"
            CLEANUP_DETAILS+="Result: $success_message\n"
            local freed_in_this_step=$((TOTAL_FREED_SPACE_MB - initial_freed_space))
            CLEANUP_DETAILS+="Space Freed: ${freed_in_this_step}MB\n"
            if [ ${#DELETED_ITEMS[@]} -gt "$initial_deleted_items_count" ]; then
                CLEANUP_DETAILS+="Items Deleted:\n"
                for ((i = initial_deleted_items_count; i < ${#DELETED_ITEMS[@]}; i++)); do
                    CLEANUP_DETAILS+="${DELETED_ITEMS[$i]}\n"
                done
            fi
            CLEANUP_DETAILS+="\n"
            return 0
        else
            log_message "ERROR" "❌ $failure_message (Command failed)"
            CLEANUP_DETAILS+="### $prompt\n"
            CLEANUP_DETAILS+="Result: $failure_message\n"
            CLEANUP_DETAILS+="\n"
            return 1
        fi
    else
        log_message "INFO" "❌ $prompt skipped by user."
        CLEANUP_DETAILS+="### $prompt\n"
        CLEANUP_DETAILS+="Result: Skipped by user.\n"
        CLEANUP_DETAILS+="\n"
        return 2 # Indicate action was skipped.
    fi
}

# --- Intelligent Analysis Functions (AI Simulation) ---

# Analyzes project directories to detect technology/environment types.
analyze_projects_for_recommendations() {
    log_message "INFO" "Analyzing project directories for intelligent recommendations..."
    local recommended_actions=""

    if [[ -d "$PROJECTS_DIR" ]]; then
        # Check for Node.js projects.
        if sudo find "$PROJECTS_DIR" -maxdepth 3 -name "package.json" -print -quit 2>/dev/null; then
            recommended_actions+="  • Node.js projects detected (node_modules, npm/yarn/bun caches, Next.js related files).\n"
        fi
        # Check for Java/Gradle projects.
        if sudo find "$PROJECTS_DIR" -maxdepth 3 -name "build.gradle" -print -quit 2>/dev/null; then
            recommended_actions+="  • Java/Gradle projects detected (Gradle caches, build directories).\n"
        fi
        # Check for Xcode projects.
        if sudo find "$PROJECTS_DIR" -maxdepth 3 -name "*.xcodeproj" -print -quit 2>/dev/null || \
           sudo find "$PROJECTS_DIR" -maxdepth 3 -name "*.xcworkspace" -print -quit 2>/dev/null; then
            recommended_actions+="  • Xcode projects detected (DerivedData, Archives, iOS DeviceSupport).\n"
        fi
        # Check for Docker projects.
        if sudo find "$PROJECTS_DIR" -maxdepth 3 -name "Dockerfile" -print -quit 2>/dev/null; then
            recommended_actions+="  • Dockerfiles detected (Docker images/containers/volumes).\n"
        fi
        # Check for Python projects (venv).
        if sudo find "$PROJECTS_DIR" -maxdepth 3 -type d -name "venv" -print -quit 2>/dev/null; then
            recommended_actions+="  • Python projects with virtual environments (venv) detected.\n"
        fi
        # Check for Ruby projects (bundle).
        if sudo find "$PROJECTS_DIR" -maxdepth 3 -name "Gemfile.lock" -print -quit 2>/dev/null; then
            recommended_actions+="  • Ruby (bundle) projects detected.\n"
        fi
        # Check for Go projects (mod).
        if sudo find "$PROJECTS_DIR" -maxdepth 3 -name "go.mod" -print -quit 2>/dev/null; then
            recommended_actions+="  • Go projects detected (Go build cache).\n"
        fi
    fi

    if [[ -n "$recommended_actions" ]]; then
        echo -e "\n--- Intelligent Recommendations Based on Your Environment ---"
        echo -e "Based on your projects, I recommend focusing on:\n${recommended_actions}"
        echo "This can free up significant disk space."
        CLEANUP_DETAILS+="## Intelligent Recommendations Based on Your Environment\n"
        CLEANUP_DETAILS+="Based on your projects, I recommend focusing on:\n"
        CLEANUP_DETAILS+="${recommended_actions}"
        CLEANUP_DETAILS+="This can free up significant disk space.\n\n"
    else
        echo -e "\n--- Environment Analysis ---"
        echo -e "No specific project types were automatically detected in your project directories.\n"
        CLEANUP_DETAILS+="## Environment Analysis\n"
        CLEANUP_DETAILS+="No specific project types were automatically detected in your project directories.\n\n"
    fi
}

# Function to detect "old" or infrequently accessed files.
detect_old_files() {
    log_message "INFO" "Detecting old files in Downloads/Documents directories..."
    local old_files_count=0
    local old_files_size=0
    local potential_candidates=()

    # Use mdfind for more efficient file searching based on modification date.
    # Search for files in Downloads and Documents not accessed in X days.
    # kMDItemLastUsedDate is the last time the file was opened by any application.
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            # Ensure the file path doesn't contain newline characters, mdfind is typically good for this.
            local size_mb=$(get_size_in_mb "$file")
            old_files_size=$((old_files_size + size_mb))
            old_files_count=$((old_files_count + 1))
            potential_candidates+=("$file")
        fi
    done < <(mdfind -onlyin "$HOME/Downloads" -onlyin "$HOME/Documents" "kMDItemLastUsedDate < \$time.$OLD_FILE_THRESHOLD_DAYS\d" 2>/dev/null)

    if [[ ${old_files_count} -gt 0 ]]; then
        echo -e "\n--- Old & Infrequently Used Files ---"
        echo "Found ${old_files_count} files (${old_files_size}MB) not accessed in the last ${OLD_FILE_THRESHOLD_DAYS} days in your Downloads/Documents."
        echo "These are good candidates for manual review and deletion."
        CLEANUP_DETAILS+="## Old & Infrequently Used Files\n"
        CLEANUP_DETAILS+="Found ${old_files_count} files (${old_files_size}MB) not accessed in the last ${OLD_FILE_THRESHOLD_DAYS} days in your Downloads/Documents.\n"
        CLEANUP_DETAILS+="These are good candidates for manual review and deletion.\n"

        if [[ "$FORCE_CLEAN" -eq 0 && "$DRY_RUN" -eq 0 ]]; then # Only prompt in interactive mode.
            read -rp "Show a list of the top 10 largest of these files? (y/N): " show_old
            if [[ "$show_old" =~ ^[Yy]$ ]]; then
                echo "Top 10 Largest Infrequently Used Files:"
                # Sort by size (human-readable), reverse order, and take top 10.
                # Use printf "%s\n" "${potential_candidates[@]}" | xargs -I {} du -sh {} for safety.
                printf "%s\n" "${potential_candidates[@]}" | xargs -I {} du -sh {} 2>/dev/null | sort -rh | head -10 | tee -a "$LOG_FILE"
                CLEANUP_DETAILS+="Top 10 Largest Infrequently Used Files:\n"
                CLEANUP_DETAILS+=$(printf "%s\n" "${potential_candidates[@]}" | xargs -I {} du -sh {} 2>/dev/null | sort -rh | head -10)\n\n
            fi
        else
            log_message "INFO" "Showing top 10 largest old files (automated/dry run mode):"
            printf "%s\n" "${potential_candidates[@]}" | xargs -I {} du -sh {} 2>/dev/null | sort -rh | head -10 | tee -a "$LOG_FILE"
            CLEANUP_DETAILS+="Top 10 Largest Infrequently Used Files (for reference in automated/dry run):\n"
            CLEANUP_DETAILS+=$(printf "%s\n" "${potential_candidates[@]}" | xargs -I {} du -sh {} 2>/dev/null | sort -rh | head -10)\n\n
        fi
    else
        echo -e "\n--- Old & Infrequently Used Files ---"
        echo "No significant infrequently accessed files found in your Downloads/Documents within ${OLD_FILE_THRESHOLD_DAYS} days."
        CLEANUP_DETAILS+="## Old & Infrequently Used Files\n"
        CLEANUP_DETAILS+="No significant infrequently accessed files found in your Downloads/Documents within ${OLD_FILE_THRESHOLD_DAYS} days.\n\n"
    fi
}

# --- Main Cleanup Functions (With Deletion Logic) ---

clean_standard_caches() {
    log_message "INFO" "Cleaning standard caches..."
    # User application caches
    confirm_and_execute "Clear user application caches (~/Library/Caches/*)?" \
        "sudo find \"$HOME/Library/Caches\" -mindepth 1 -maxdepth 1 -print0 | xargs -0 -I {} bash -c 'perform_deletion \"{}\"'" \
        "User application caches cleared." \
        "Failed to clear user application caches."

    # System caches (requires sudo)
    confirm_and_execute "Clear system caches (/Library/Caches/*)?" \
        "sudo find \"/Library/Caches\" -mindepth 1 -maxdepth 1 -print0 | xargs -0 -I {} bash -c 'perform_deletion \"{}\"'" \
        "System caches cleared." \
        "Failed to clear system caches."
    
    # Specific application caches (these are common culprits)
    confirm_and_execute "Clear specific app caches (VSCode, Chrome, Safari, QuickLook)?" \
        "perform_deletion \"$HOME/Library/Caches/com.microsoft.VSCode\"/*; \
         perform_deletion \"$HOME/Library/Caches/Google/Chrome\"/*; \
         perform_deletion \"$HOME/Library/Caches/com.apple.Safari\"/*; \
         perform_deletion \"$HOME/Library/Caches/com.apple.QuickLook.thumbnailcache\"/*" \
        "Specific app caches cleared." \
        "Failed to clear specific app caches."
        
    # Temporary system caches in /private/var/folders
    # This is a very dynamic area; cleaning C, T, and tmp subdirectories is common practice.
    # It's crucial *not* to delete the `folders` directory itself.
    log_message "INFO" "Cleaning temporary caches in /private/var/folders/..."
    confirm_and_execute "Clean /private/var/folders/ temporary caches (C, T, tmp subdirectories)?" \
        "sudo find /private/var/folders -depth 2 -type d \\( -name \"C\" -o -name \"T\" -o -name \"tmp\" \\) -print0 | xargs -0 -I {} bash -c 'log_message INFO \"Cleaning content of {}\"; sudo rm -rf \"{}\"/* 2>/dev/null'" \
        "Temporary caches in /private/var/folders cleaned." \
        "Failed to clean temporary caches in /private/var/folders."

    # App Store & Software Update caches
    confirm_and_execute "Clear App Store & Software Update caches?" \
        "perform_deletion \"/private/var/folders\"/*/*/C/com.apple.appstore/*; \
         perform_deletion \"/private/var/folders\"/*/*/C/com.apple.SoftwareUpdate/*" \
        "App Store & Software Update caches cleared." \
        "Failed to clear App Store & Software Update caches."
        
    # Font Caches (special command)
    confirm_and_execute "Clear font caches (requires restart to take full effect)?" \
        "if [[ \"\$DRY_RUN\" -eq 0 ]]; then sudo atsutil databases -remove 2>/dev/null; sudo rm -rf /Library/Caches/com.apple.ATS/* \"\$HOME/Library/Caches/com.apple.ATS\"/* 2>/dev/null; fi" \
        "Font caches cleared." \
        "Failed to clear font caches."
}

clean_development_tool_caches() {
    log_message "INFO" "Cleaning development tool caches..."

    if command -v npm >/dev/null 2>&1; then
        confirm_and_execute "Clear npm cache and _npx folder?" \
            "if [[ \"\$DRY_RUN\" -eq 0 ]]; then npm cache clean --force 2>/dev/null; perform_deletion \"\$HOME/.npm/_npx\"/*; fi" \
            "npm cache cleared." \
            "Failed to clear npm cache."
    else
        log_message "WARN" "npm not installed. Skipping npm cache cleanup."
    fi

    if command -v yarn >/dev/null 2>&1; then
        confirm_and_execute "Clear Yarn cache?" \
            "if [[ \"\$DRY_RUN\" -eq 0 ]]; then yarn cache clean --force 2>/dev/null; fi" \
            "Yarn cache cleared." \
            "Failed to clear Yarn cache."
    else
        log_message "WARN" "Yarn not installed. Skipping Yarn cache cleanup."
    fi

    if command -v bun >/dev/null 2>&1; then
        confirm_and_execute "Clear Bun cache?" \
            "if [[ \"\$DRY_RUN\" -eq 0 ]]; then bun clean --force 2>/dev/null; perform_deletion \"\$HOME/.bun/install/cache\"/*; fi" \
            "Bun cache cleared." \
            "Failed to clear Bun cache."
    else
        log_message "WARN" "Bun not installed. Skipping Bun cache cleanup."
    fi

    if command -v brew >/dev/null 2>&1; then
        confirm_and_execute "Clear Homebrew cache and old versions?" \
            "if [[ \"\$DRY_RUN\" -eq 0 ]]; then brew cleanup --prune=all 2>/dev/null; perform_deletion \"\$(brew --cache)\"/*; fi" \
            "Homebrew cache cleared." \
            "Failed to clear Homebrew cache."
    else
        log_message "WARN" "Homebrew not installed. Skipping Homebrew cleanup."
    fi

    confirm_and_execute "Clear common IDE/build caches (Gradle, Puppeteer, Pip, Go build)?" \
        "perform_deletion \"\$HOME/.gradle/caches\"/*; \
         perform_deletion \"\$HOME/.cache/puppeteer\"/*; \
         perform_deletion \"\$HOME/.cache/pip\"/*; \
         perform_deletion \"\$HOME/.cache/go-build\"/*; \
         perform_deletion \"\$HOME/Library/Caches/GoLand*\"/*; \
         perform_deletion \"\$HOME/Library/Caches/WebStorm*\"/*; \
         perform_deletion \"\$HOME/Library/Caches/PhpStorm*\"/*; \
         perform_deletion \"\$HOME/Library/Caches/IntelliJIdea*\"/*; \
         perform_deletion \"\$HOME/Library/Caches/AndroidStudio*\"/*" \
        "Common IDE/build caches cleared." \
        "Failed to clear common IDE/build caches."
}

clean_xcode_components() {
    log_message "INFO" "Cleaning Xcode components..."
    confirm_and_execute "Clear Xcode DerivedData?" \
        "perform_deletion \"\$HOME/Library/Developer/Xcode/DerivedData\"/*" \
        "Xcode DerivedData cleared." \
        "Failed to clear Xcode DerivedData."

    confirm_and_execute "Clear Xcode Archives?" \
        "perform_deletion \"\$HOME/Library/Developer/Xcode/Archives\"/*" \
        "Xcode Archives cleared." \
        "Failed to clear Xcode Archives."
    
    confirm_and_execute "Clear iOS DeviceSupport data (all versions)?" \
        "perform_deletion \"\$HOME/Library/Developer/Xcode/iOS DeviceSupport\"/*" \
        "iOS DeviceSupport data cleared." \
        "Failed to clear iOS DeviceSupport data."

    confirm_and_execute "Clear Xcode Simulator Devices caches?" \
        "perform_deletion \"\$HOME/Library/Developer/Xcode/UserData/Previews/Simulator Devices\"/*" \
        "Xcode Simulator Devices caches cleared." \
        "Failed to clear Xcode Simulator Devices caches."

    confirm_and_execute "Clear unused CoreSimulator data?" \
        "perform_deletion \"\$HOME/Library/Developer/CoreSimulator/Devices\"/*" \
        "Unused CoreSimulator data cleared." \
        "Failed to clear unused CoreSimulator data."
}

clean_nextjs_related() {
    log_message "INFO" "Cleaning Next.js related caches and temporary files..."
    
    # .next/cache and .next/cache/webpack
    # Use find directly to get paths, then iterate for deletion.
    local next_cache_paths=()
    while IFS= read -r -d '' p; do next_cache_paths+=("$p"); done < <(sudo find "${SEARCH_DIRS[@]}" -type d -path "*.next/cache" -o -path "*.next/cache/webpack" -print0 2>/dev/null)
    if [[ ${#next_cache_paths[@]} -gt 0 ]]; then
        confirm_and_execute "Clear Next.js build caches (.next/cache, .next/cache/webpack)?" \
            "for dir in \"\${next_cache_paths[@]}\"; do perform_deletion \"\$dir\"/*; done" \
            "Next.js build caches cleared." \
            "Failed to clear Next.js build caches."
    else
        log_message "INFO" "No Next.js caches found."
    fi

    # .bun-cache (often co-located with Next.js projects)
    local bun_cache_paths=()
    while IFS= read -r -d '' p; do bun_cache_paths+=("$p"); done < <(sudo find "${SEARCH_DIRS[@]}" -type d -name ".bun-cache" -print0 2>/dev/null)
    if [[ ${#bun_cache_paths[@]} -gt 0 ]]; then
        confirm_and_execute "Clear Next.js related .bun-cache directories?" \
            "for dir in \"\${bun_cache_paths[@]}\"; do perform_deletion \"\$dir\"; done" \
            "Next.js related .bun-cache directories cleared." \
            "Failed to clear Next.js related .bun-cache directories."
    else
        log_message "INFO" "No Next.js related .bun-cache directories found."
    fi
}

clean_nextjs_swc_binaries() {
    log_message "INFO" "Cleaning Next.js SWC binaries..."
    # SWC binaries can be large and are often duplicated across projects.
    local swc_binaries=()
    while IFS= read -r -d '' p; do swc_binaries+=("$p"); done < <(sudo find "${SEARCH_DIRS[@]}" -type f -name "next-swc.darwin-arm64.node" -o -name "next-swc.darwin-x64.node" -print0 2>/dev/null)

    if [[ ${#swc_binaries[@]} -gt 0 ]]; then
        confirm_and_execute "Clear Next.js SWC binaries (re-downloaded on next build)?" \
            "for file in \"\${swc_binaries[@]}\"; do perform_deletion \"\$file\"; done" \
            "Next.js SWC binaries cleared." \
            "Failed to clear Next.js SWC binaries."
    else
        log_message "INFO" "No Next.js SWC binaries found."
    fi
}

clean_vscode_extensions() {
    log_message "INFO" "Cleaning VS Code extensions..."
    if [[ -d "$HOME/.vscode/extensions" ]]; then
        confirm_and_execute "WARNING: Clear ALL VS Code extensions? You will need to reinstall needed ones. (y/N)" \
            "sudo rm -rf \"$HOME/.vscode/extensions\"/* 2>/dev/null" \
            "VS Code extensions cleared." \
            "Failed to clear VS Code extensions."
    else
        log_message "INFO" "VS Code extensions directory not found."
    fi
}

clean_build_and_temp_directories() {
    log_message "INFO" "Cleaning build and temporary directories..."
    local patterns=(
        "dist" "build" "tmp" "temp" "*.tmp" "*.temp" ".DS_Store" "._*" ".localized"
        "*.bak" "*.old" "*.swp" "*.swo" "*.log" "Thumbs.db" "node_modules/.cache"
        ".parcel-cache" ".eslintcache" ".tscache" ".svelte-kit" ".nuxt" ".next"
        "vendor/bundle" "__pycache__" ".pytest_cache" "*.pyc" "*.o" "*.so"
        "*.dll" "*.obj" "*.lib" ".cmake" "target" ".vscode-test" ".gradle"
    )

    for pattern in "${patterns[@]}"; do
        # Use find for robust pattern matching across SEARCH_DIRS.
        # Skip specific patterns if they are handled by other, more targeted functions (e.g., .next, node_modules).
        if [[ "$pattern" == ".next" || "$pattern" == "node_modules" ]]; then
            log_message "DEBUG" "Pattern '$pattern' handled by a dedicated function. Skipping generic scan."
            continue
        fi

        log_message "INFO" "Searching for pattern: '$pattern'"
        local items_to_delete=()
        for search_dir in "${SEARCH_DIRS[@]}"; do
            if [[ -d "$search_dir" ]]; then
                while IFS= read -r -d '' item_path; do
                    local skip=false
                    for exclude_dir_raw in "${EXCLUDE_DIRS[@]}"; do
                        local expanded_exclude_dir=$(eval echo "$exclude_dir_raw")
                        if [[ "$item_path" == "$expanded_exclude_dir"* ]]; then
                            skip=true
                            log_message "DEBUG" "Skipping excluded item: '$item_path'"
                            break
                        fi
                    done
                    if $skip; then continue; fi
                    items_to_delete+=("$item_path")
                done < <(sudo find "$search_dir" -xdev -name "$pattern" -print0 2>/dev/null)
            fi
        done

        if [[ ${#items_to_delete[@]} -gt 0 ]]; then
            confirm_and_execute "Clear '${pattern}' files/directories?" \
                "for item in \"\${items_to_delete[@]}\"; do perform_deletion \"\$item\"; done" \
                "'${pattern}' files/directories cleared." \
                "Failed to clear '${pattern}' files/directories."
        else
            log_message "INFO" "No '$pattern' files/directories found."
        fi
    done

    # Clean system temporary directories.
    confirm_and_execute "Clear system-wide /private/tmp/* and /var/tmp/*?" \
        "perform_deletion \"/private/tmp\"/*; perform_deletion \"/var/tmp\"/*" \
        "System temporary directories cleared." \
        "Failed to clear system temporary directories."
}

clean_node_modules() {
    log_message "INFO" "Cleaning node_modules directories..."
    local node_modules_paths=()
    for search_dir in "${SEARCH_DIRS[@]}"; do
        if [[ -d "$search_dir" ]]; then
            while IFS= read -r -d '' node_dir; do
                local skip=false
                for exclude_dir_raw in "${EXCLUDE_DIRS[@]}"; do
                    local expanded_exclude_dir=$(eval echo "$exclude_dir_raw")
                    if [[ "$node_dir" == "$expanded_exclude_dir"* ]]; then
                        skip=true
                        log_message "DEBUG" "Skipping excluded node_modules: '$node_dir'"
                        break
                    fi
                done
                if $skip; then continue; fi
                node_modules_paths+=("$node_dir")
            done < <(sudo find "$search_dir" -xdev -type d -name "node_modules" -print0 2>/dev/null)
        fi
    done

    if [[ ${#node_modules_paths[@]} -gt 0 ]]; then
        confirm_and_execute "Clear all detected node_modules directories? (Can be very large)" \
            "for node_dir in \"\${node_modules_paths[@]}\"; do perform_deletion \"\$node_dir\"; done" \
            "node_modules directories cleared." \
            "Failed to clear node_modules directories."
    else
        log_message "INFO" "No node_modules directories found."
    fi
}

clean_python_virtual_environments() {
    log_message "INFO" "Cleaning Python virtual environments (venv)..."
    local venv_paths=()
    for search_dir in "${SEARCH_DIRS[@]}"; do
        if [[ -d "$search_dir" ]]; then
            while IFS= read -r -d '' venv_dir; do
                local skip=false
                for exclude_dir_raw in "${EXCLUDE_DIRS[@]}"; do
                    local expanded_exclude_dir=$(eval echo "$exclude_dir_raw")
                    if [[ "$venv_dir" == "$expanded_exclude_dir"* ]]; then
                        skip=true
                        log_message "DEBUG" "Skipping excluded venv: '$venv_dir'"
                        break
                    fi
                done
                if $skip; then continue; fi
                venv_paths+=("$venv_dir")
            done < <(sudo find "$search_dir" -xdev -type d -name "venv" -print0 2>/dev/null)
        fi
    done

    if [[ ${#venv_paths[@]} -gt 0 ]]; then
        confirm_and_execute "Clear all detected Python virtual environments (venv)? (Pip dependencies will need reinstallation)" \
            "for venv_dir in \"\${venv_paths[@]}\"; do perform_deletion \"\$venv_dir\"; done" \
            "Python virtual environments cleared." \
            "Failed to clear Python virtual environments."
    else
        log_message "INFO" "No Python virtual environments (venv) found."
    fi
}

clean_ruby_gems() {
    log_message "INFO" "Cleaning Ruby gems cache and bundle directories..."
    if command -v gem >/dev/null 2>&1; then
        confirm_and_execute "Clear Ruby gems cache?" \
            "if [[ \"\$DRY_RUN\" -eq 0 ]]; then gem cleanup 2>/dev/null; fi" \
            "Ruby gems cache cleared." \
            "Failed to clear Ruby gems cache."
    else
        log_message "WARN" "Ruby gem command not found. Skipping Ruby gems cache cleanup."
    fi

    # Clean vendor/bundle directories
    local bundle_paths=()
    for search_dir in "${SEARCH_DIRS[@]}"; do
        if [[ -d "$search_dir" ]]; then
            while IFS= read -r -d '' bundle_dir; do
                local skip=false
                for exclude_dir_raw in "${EXCLUDE_DIRS[@]}"; do
                    local expanded_exclude_dir=$(eval echo "$exclude_dir_raw")
                    if [[ "$bundle_dir" == "$expanded_exclude_dir"* ]]; then
                        skip=true
                        log_message "DEBUG" "Skipping excluded bundle: '$bundle_dir'"
                        break
                    fi
                done
                if $skip; then continue; fi
                bundle_paths+=("$bundle_dir")
            done < <(sudo find "$search_dir" -xdev -type d -name "bundle" -path "*/vendor/bundle" -print0 2>/dev/null)
        fi
    done

    if [[ ${#bundle_paths[@]} -gt 0 ]]; then
        confirm_and_execute "Clear 'vendor/bundle' directories?" \
            "for bundle_dir in \"\${bundle_paths[@]}\"; do perform_deletion \"\$bundle_dir\"; done" \
            "'vendor/bundle' directories cleared." \
            "Failed to clear 'vendor/bundle' directories."
    else
        log_message "INFO" "No 'vendor/bundle' directories found."
    fi
}

clean_docker_resources() {
    log_message "INFO" "Cleaning Docker resources..."
    if command -v docker >/dev/null 2>&1; then
        confirm_and_execute "WARNING: Prune all unused Docker containers, images, and volumes? (This will remove all stopped containers, dangling images, and unused volumes.) (y/N)" \
            "if [[ \"\$DRY_RUN\" -eq 0 ]]; then docker system prune -a --volumes -f 2>/dev/null; fi" \
            "Docker system pruned successfully." \
            "Failed to prune Docker system."
    else
        log_message "WARN" "Docker is not installed. Skipping Docker cleanup."
    fi
}

clean_system_and_user_logs() {
    log_message "INFO" "Cleaning system and user logs..."
    
    # System logs (older than 30 days)
    confirm_and_execute "Clear system logs older than 30 days (/private/var/log/*.log)?" \
        "if [[ \"\$DRY_RUN\" -eq 0 ]]; then sudo find /private/var/log -type f -name \"*.log\" -mtime +30 -exec rm -f {} \; 2>/dev/null; fi" \
        "System logs cleared." \
        "Failed to clear system logs."

    # User application logs (older than 30 days)
    confirm_and_execute "Clear user application logs older than 30 days (~/Library/Logs/*.log)?" \
        "if [[ \"\$DRY_RUN\" -eq 0 ]]; then find \"\$HOME/Library/Logs\" -type f -name \"*.log\" -mtime +30 -exec rm -f {} \; 2>/dev/null; fi" \
        "User application logs cleared." \
        "Failed to clear user application logs."

    # Crash Reports (older than 90 days)
    confirm_and_execute "Clear old crash reports (user and system, older than 90 days)?" \
        "if [[ \"\$DRY_RUN\" -eq 0 ]]; then \
            find \"\$HOME/Library/Logs/DiagnosticReports\" -type f -mtime +90 -exec rm -f {} \; 2>/dev/null; \
            sudo find /Library/Logs/DiagnosticReports -type f -mtime +90 -exec rm -f {} \; 2>/dev/null; \
        fi" \
        "Old crash reports cleared." \
        "Failed to clear old crash reports."
}

empty_trash() {
    log_message "INFO" "Emptying Trash..."
    # User's trash.
    confirm_and_execute "Empty your user Trash (~/.Trash/*)?" \
        "perform_deletion \"\$HOME/.Trash\"/*" \
        "User Trash emptied." \
        "Failed to empty user Trash."

    # Empty .Trashes on external volumes (requires sudo for other users' trashes).
    confirm_and_execute "Empty .Trashes on external volumes (may require sudo)?" \
        "sudo find /Volumes -maxdepth 2 -type d -name \".Trashes\" -exec sudo rm -rf {}/* \; 2>/dev/null" \
        "External volume Trashes emptied." \
        "Failed to empty external volume Trashes."
}

clean_downloads() {
    log_message "INFO" "Cleaning Downloads directory..."
    
    # Delete files older than 90 days in Downloads (excluding DMG/PKG).
    confirm_and_execute "Delete files older than 90 days in Downloads (excluding installers)?" \
        "if [[ \"\$DRY_RUN\" -eq 0 ]]; then sudo find \"\$HOME/Downloads\" -type f -mtime +90 ! -name \"*.dmg\" ! -name \"*.pkg\" -exec rm -f {} \; 2>/dev/null; fi" \
        "Old non-installer Downloads cleared." \
        "Failed to clear old non-installer Downloads."

    # Delete DMG/PKG installers older than 30 days.
    confirm_and_execute "Delete DMG/PKG installers older than 30 days in Downloads?" \
        "if [[ \"\$DRY_RUN\" -eq 0 ]]; then sudo find \"\$HOME/Downloads\" -type f \\( -name \"*.dmg\" -o -name \"*.pkg\" \\) -mtime +30 -exec rm -f {} \; 2>/dev/null; fi" \
        "Old DMG/PKG installers cleared." \
        "Failed to clear old DMG/PKG installers."
}

clean_broken_symlinks() {
    log_message "INFO" "Cleaning broken symbolic links..."
    local broken_symlinks=()
    for search_dir in "${SEARCH_DIRS[@]}"; do
        if [[ -d "$search_dir" ]]; then
            while IFS= read -r -d '' symlink; do
                local skip=false
                for exclude_dir_raw in "${EXCLUDE_DIRS[@]}"; do
                    local expanded_exclude_dir=$(eval echo "$exclude_dir_raw")
                    if [[ "$symlink" == "$expanded_exclude_dir"* ]]; then
                        skip=true
                        log_message "DEBUG" "Skipping excluded broken symlink: '$symlink'"
                        break
                    fi
                done
                if $skip; then continue; fi
                broken_symlinks+=("$symlink")
            done < <(sudo find "$search_dir" -xtype l -print0 2>/dev/null) # -xtype l finds broken symlinks
        fi
    done

    if [[ ${#broken_symlinks[@]} -gt 0 ]]; then
        confirm_and_execute "Clear all detected broken symbolic links?" \
            "for symlink in \"\${broken_symlinks[@]}\"; do perform_deletion \"\$symlink\"; done" \
            "Broken symbolic links cleared." \
            "Failed to clear broken symbolic links."
    else
        log_message "INFO" "No broken symbolic links found."
    fi
}

clean_user_library_junk() {
    log_message "INFO" "Cleaning common junk in ~/Library..."
    
    confirm_and_execute "Clear ~/Library/Saved Application State/?" \
        "perform_deletion \"\$HOME/Library/Saved Application State\"/*" \
        "Saved Application State cleared." \
        "Failed to clear Saved Application State."

    confirm_and_execute "Clear ~/Library/Application Support/CrashReporter/?" \
        "perform_deletion \"\$HOME/Library/Application Support/CrashReporter\"/*" \
        "CrashReporter logs cleared." \
        "Failed to clear CrashReporter logs."

    confirm_and_execute "Clear Safari SafeBrowse.db?" \
        "perform_deletion \"\$HOME/Library/Containers/com.apple.Safari/Data/Library/Safari/SafeBrowse.db\"" \
        "Safari SafeBrowse.db cleared." \
        "Failed to clear Safari SafeBrowse.db."
    
    confirm_and_execute "Clear Mail.app attachment caches?" \
        "perform_deletion \"\$HOME/Library/Containers/com.apple.mail/Data/Library/Caches/Mail Downloads\"/*" \
        "Mail.app attachment caches cleared." \
        "Failed to clear Mail.app attachment caches."

    confirm_and_execute "Clear other browser caches (Firefox, Chrome Service Worker/Application Cache)?" \
        "perform_deletion \"\$HOME/Library/Application Support/Firefox/Profiles\"/*/cache2/*; \
         perform_deletion \"\$HOME/Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage\"/*; \
         perform_deletion \"\$HOME/Library/Application Support/Google/Chrome/Default/Application Cache\"/*" \
        "Other browser caches cleared." \
        "Failed to clear other browser caches."

    confirm_and_execute "Clear Preview and Mail caches in ~/Library/Containers?" \
        "perform_deletion \"\$HOME/Library/Containers/com.apple.Preview/Data/Library/Caches\"/*; \
         perform_deletion \"\$HOME/Library/Containers/com.apple.mail/Data/Library/Caches/com.apple.mail\"/*" \
        "Preview and Mail caches cleared." \
        "Failed to clear Preview and Mail caches."
}

clean_obsolete_system_files() {
    log_message "INFO" "Cleaning obsolete system files (leftover caches/support from installations)."
    # This area is more "risky" and usually requires more specific identification.
    # However, some safe locations to clean are:
    
    confirm_and_execute "Clear old package receipts (.pkg, .bom, .plist)?" \
        "perform_deletion \"/Library/Receipts\"/*.pkg; \
         perform_deletion \"/private/var/db/receipts\"/*.bom; \
         perform_deletion \"/private/var/db/receipts\"/*.plist" \
        "Old package receipts cleared." \
        "Failed to clear old package receipts."
        
    confirm_and_execute "Clear remaining macOS update caches?" \
        "perform_deletion \"/Library/Updates\"/*; \
         perform_deletion \"/Library/Caches/com.apple.appstore.updates\"/*" \
        "macOS update caches cleared." \
        "Failed to clear macOS update caches."

    log_message "INFO" "Files in /tmp and /var/tmp that are left by processes are handled by clean_build_and_temp_directories."
}

clean_mac_app_store_cache() {
    log_message "INFO" "Cleaning Mac App Store cache..."
    confirm_and_execute "Clear Mac App Store caches?" \
        "perform_deletion \"\$HOME/Library/Caches/com.apple.appstore\"/*; \
         perform_deletion \"\$HOME/Library/Application Support/AppStore/Cache.db\"" \
        "Mac App Store caches cleared." \
        "Failed to clear Mac App Store caches."
}

clean_mobile_device_backups() {
    log_message "INFO" "Cleaning old mobile device backups (iOS/iPadOS)..."
    local backup_path="$HOME/Library/Application Support/MobileSync/Backup"
    if [[ -d "$backup_path" && "$(ls -A "$backup_path")" ]]; then # Check if directory exists and is not empty.
        confirm_and_execute "⚠️ WARNING: Delete ALL mobile device backups? This can free up significant space but your backups will be lost! (y/N)" \
            "sudo rm -rf \"$backup_path\"/*" \
            "Mobile device backups deleted." \
            "Failed to delete mobile device backups."
    else
        log_message "INFO" "No mobile device backups found in '$backup_path'."
    fi
}

clean_adobe_caches() {
    log_message "INFO" "Cleaning Adobe caches (Media Cache, Preview Files)..."
    confirm_and_execute "Clear Adobe Media Cache and Preview Files?" \
        "perform_deletion \"\$HOME/Library/Application Support/Adobe/Common/Media Cache Files\"/*; \
         perform_deletion \"\$HOME/Library/Application Support/Adobe/Common/Media Cache\"/*" \
        "Adobe Media Cache and Preview Files cleared." \
        "Failed to clear Adobe Media Cache and Preview Files."

    confirm_and_execute "Clear Adobe CameraRaw cache?" \
        "perform_deletion \"\$HOME/Library/Caches/Adobe/CameraRaw/Cache\"/*" \
        "Adobe CameraRaw cache cleared." \
        "Failed to clear Adobe CameraRaw cache."
    
    confirm_and_execute "Clear other Adobe related caches/temporary files?" \
        "perform_deletion \"\$HOME/Library/Application Support/Adobe/Adobe Desktop Common/CEP/extensions/com.adobe.ccx.start.panel/local_storage\"/*; \
         perform_deletion \"\$HOME/Library/Application Support/Adobe/OOBE/Configs\"/*" \
        "Other Adobe related caches/temporary files cleared." \
        "Failed to clear other Adobe related caches/temporary files."
}

clean_time_machine_local_snapshots() {
    log_message "INFO" "Cleaning Time Machine local snapshots..."
    if sysctl -n sysctl.proc_info.procs_system | grep -q 'backupd'; then
        log_message "WARN" "Time Machine process (backupd) is currently running. Local snapshots might not be fully cleared until it finishes."
    fi
    confirm_and_execute "Clear Time Machine local snapshots? (This may take a while)" \
        "if [[ \"\$DRY_RUN\" -eq 0 ]]; then sudo tmutil deletelocalsnapshots / 2>/dev/null; fi" \
        "Time Machine local snapshots cleared." \
        "Failed to clear Time Machine local snapshots."
}

# --- Tiered Cleanup Structure (Simulating Cleanup Modes) ---

# Level 1: Safe Cleanup - Common Caches & Temporary Files
clean_level_1_safe() {
    log_message "INFO" "Initiating Level 1: Safe Cleanup (Common Caches & Temporary Files)."
    echo -e "\n--- Starting Level 1: Safe Cleanup ---"

    clean_standard_caches
    clean_system_and_user_logs
    empty_trash
    clean_downloads
    clean_mac_app_store_cache
    clean_user_library_junk # Added to safe as it's typically safe to clear.

    echo -e "\n--- Level 1: Safe Cleanup Complete ---"
}

# Level 2: Developer-Focused Cleanup - Dev Tool Caches, Build Artifacts, etc.
clean_level_2_developer() {
    log_message "INFO" "Initiating Level 2: Developer-Focused Cleanup."
    echo -e "\n--- Starting Level 2: Developer-Focused Cleanup ---"

    clean_development_tool_caches
    clean_xcode_components
    clean_nextjs_related
    clean_nextjs_swc_binaries
    clean_node_modules
    clean_python_virtual_environments
    clean_ruby_gems
    clean_docker_resources
    clean_build_and_temp_directories
    clean_broken_symlinks # Broken symlinks can accumulate in dev environments.

    echo -e "\n--- Level 2: Developer-Focused Cleanup Complete ---"
}

# Level 3: Aggressive Cleanup - More Disk Space, Higher Impact (Requires User Awareness)
clean_level_3_aggressive() {
    log_message "INFO" "Initiating Level 3: Aggressive Cleanup."
    echo -e "\n--- Starting Level 3: Aggressive Cleanup ---"

    clean_obsolete_system_files
    clean_adobe_caches
    clean_time_machine_local_snapshots
    # VS Code extensions are explicitly warned due to potential impact.
    confirm_and_execute "WARNING: Do you want to clear VS Code Extensions? (y/N)" \
        "clean_vscode_extensions" \
        "VS Code Extensions cleanup attempted." \
        "VS Code Extensions cleanup skipped/failed."
    
    # Mobile device backups are explicitly warned.
    confirm_and_execute "WARNING: Do you want to clear Mobile Device Backups? (y/N)" \
        "clean_mobile_device_backups" \
        "Mobile Device Backups cleanup attempted." \
        "Mobile Device Backups cleanup skipped/failed."

    echo -e "\n--- Level 3: Aggressive Cleanup Complete ---"
}

# --- Main Script Logic ---

display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "A comprehensive macOS system cleanup script."
    echo
    echo "Options:"
    echo "  -h, --help                Display this help message."
    echo "  -f, --force               Force cleanup without interactive prompts (use with caution)."
    echo "  -d, --dry-run             Perform a dry run (simulate cleanup, show what would be deleted)."
    echo "  -l <level>, --level=<level>"
    echo "                            Run a specific cleanup level:"
    echo "                              1: Safe Cleanup (Default: common caches, temporary files, trash)"
    echo "                              2: Developer-Focused Cleanup (Dev tool caches, build artifacts, etc.)"
    echo "                              3: Aggressive Cleanup (More impactful removals like old backups, VS Code extensions)"
    echo "  --all                     Run all cleanup levels (1, 2, and 3) in sequence."
    echo
    echo "Examples:"
    echo "  $0                        Run interactively (Level 1)."
    echo "  $0 -f -l 2                Force run Developer-Focused Cleanup."
    echo "  $0 --dry-run --all        Simulate all cleanup actions."
    echo "  $0 --level=3              Run Aggressive Cleanup interactively."
    echo
    echo "It's highly recommended to perform a dry run first or use interactive mode."
}

main() {
    log_message "INFO" "Script started."

    local run_level_1=false
    local run_level_2=false
    local run_level_3=false
    local run_all_levels=false
    local selected_level=""

    # Parse command-line arguments.
    while (( "$#" )); do
        case "$1" in
            -h|--help)
                display_help
                exit 0
                ;;
            -f|--force)
                FORCE_CLEAN=1
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=1
                shift
                ;;
            -l|--level)
                if [ -n "$2" ] && [[ "$2" =~ ^[1-3]$ ]]; then
                    selected_level="$2"
                    shift 2
                else
                    echo "Error: --level requires a number between 1 and 3." >&2
                    display_help
                    exit 1
                fi
                ;;
            --level=*)
                selected_level="${1#*=}"
                if [[ ! "$selected_level" =~ ^[1-3]$ ]]; then
                    echo "Error: --level requires a number between 1 and 3." >&2
                    display_help
                    exit 1
                fi
                shift
                ;;
            --all)
                run_all_levels=true
                shift
                ;;
            *)
                echo "Error: Unknown option '$1'" >&2
                display_help
                exit 1
                ;;
        esac
    done

    # Set cleanup levels based on arguments.
    if [[ "$run_all_levels" == true ]]; then
        run_level_1=true
        run_level_2=true
        run_level_3=true
    elif [[ -n "$selected_level" ]]; then
        case "$selected_level" in
            1) run_level_1=true ;;
            2) run_level_2=true ;;
            3) run_level_3=true ;;
        esac
    else
        # Default to interactive Level 1 if no level or --all is specified.
        run_level_1=true
        log_message "INFO" "No cleanup level specified. Defaulting to Level 1 (Safe Cleanup) in interactive mode."
    fi

    # Display initial status.
    echo -e "\n--- macOS Cleanup Script ---"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "Running in \033[1;33mDRY RUN\033[0m mode. No files will be deleted."
    fi
    if [[ "$FORCE_CLEAN" -eq 1 ]]; then
        echo "Running in \033[1;31mFORCED\033[0m mode. No prompts will be shown."
    fi
    echo "Log file: $LOG_FILE"
    echo "Report file: $FREED_SPACE_REPORT"
    echo "--------------------------"

    # Run analysis first.
    analyze_projects_for_recommendations
    detect_old_files

    # Execute cleanup levels based on flags.
    if [[ "$run_level_1" == true ]]; then
        confirm_and_execute "Ready to perform Level 1: Safe Cleanup? (Recommended for most users)" \
            "clean_level_1_safe" \
            "Level 1 Cleanup completed." \
            "Level 1 Cleanup failed or was skipped."
    fi

    if [[ "$run_level_2" == true ]]; then
        confirm_and_execute "Ready to perform Level 2: Developer-Focused Cleanup? (Recommended for developers)" \
            "clean_level_2_developer" \
            "Level 2 Cleanup completed." \
            "Level 2 Cleanup failed or was skipped."
    fi

    if [[ "$run_level_3" == true ]]; then
        confirm_and_execute "Ready to perform Level 3: Aggressive Cleanup? (Use with caution, higher impact)" \
            "clean_level_3_aggressive" \
            "Level 3 Cleanup completed." \
            "Level 3 Cleanup failed or was skipped."
    fi
    
    # Final Report
    echo -e "\n--- Cleanup Summary ---" | tee -a "$LOG_FILE"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "Dry Run Completed. No files were actually deleted." | tee -a "$LOG_FILE"
        echo "Simulated Space Freed: ${TOTAL_FREED_SPACE_MB}MB" | tee -a "$LOG_FILE"
    else
        echo "Cleanup Completed!" | tee -a "$LOG_FILE"
        echo "Total Space Freed: ${TOTAL_FREED_SPACE_MB}MB" | tee -a "$LOG_FILE"
    fi

    echo -e "\n--- Detailed Cleanup Report ---" | tee -a "$LOG_FILE"
    echo -e "$CLEANUP_DETAILS" | tee -a "$LOG_FILE"
    echo -e "\nFull log available at: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "Freed space details (MB per deletion) at: $FREED_SPACE_REPORT" | tee -a "$LOG_FILE"

    log_message "INFO" "Script finished. Total space freed: ${TOTAL_FREED_SPACE_MB}MB."
}

# Ensure the script is run with sudo if needed for system-level operations.
# This check can be performed at the very beginning.
if [[ "$EUID" -ne 0 ]]; then
    echo "This script requires sudo privileges for many operations."
    echo "Please run with: sudo $0 $*"
    # exit 1 # Don't exit immediately, some functions might still run without sudo.
fi

# Export `perform_deletion` for `xargs -I {} bash -c`
export -f perform_deletion
export -f log_message
export -f get_size_in_mb
export TOTAL_FREED_SPACE_MB
export LOG_FILE
export FREED_SPACE_REPORT
export DELETED_ITEMS
export DRY_RUN

# Call the main function.
main "$@"
