#!/bin/bash

# mac-cleanup.sh - A script to clean up cache and temporary files on macOS
# Usage: curl -s https://cdn.jsdelivr.net/gh/bipproduction/sh/mac-cleanup/pipe.sh | bash
# Author: bipproduction
# Version: 1.0.0

# Exit on error
set -e

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: This script is designed for macOS only."
    exit 1
fi

# Default parameters
SIZE=${SIZE:-100}  # File size threshold in MB
FORCE_CLEAN=${FORCE_CLEAN:-0}  # Force clean without prompts (0=off, 1=on)
LOG_FILE="$HOME/mac-cleanup-$(date +%Y%m%d-%H%M%S).log"

# Search directories (excluding /System/Volumes/Data/ to avoid redundancy)
SEARCH_DIRS=(
    "$HOME/Documents"
    "$HOME/Documents/projects"
    "$HOME/Desktop"
    "$HOME/Developer"
    "/private/var/www"
)

# Function to log messages to file and console
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to calculate directory size
calc_dir_size() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        sudo du -sh "$dir" 2>/dev/null | awk '{print $1}' || echo "0B"
    else
        echo "0B"
    fi
}

# Function to calculate size of files matching a pattern
calc_pattern_size() {
    local pattern="$1"
    local total=0
    local count=0
    for search_dir in "${SEARCH_DIRS[@]}"; do
        if [[ -d "$search_dir" ]]; then
            while IFS= read -r -d '' file; do
                if [[ -f "$file" ]] || [[ -d "$file" ]]; then
                    size_mb=$(sudo du -sm "$file" 2>/dev/null | cut -f1)
                    total=$((total + size_mb))
                    count=$((count + 1))
                fi
            done < <(sudo find "$search_dir" -name "$pattern" -print0 2>/dev/null)
        fi
    done
    echo "${total}MB (${count} items)"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE_CLEAN=1; shift ;;
        --size=*) SIZE="${1#*=}"; shift ;;
        --help)
            echo "Usage: $0 [--force] [--size=<MB>] [--help]"
            echo "  --force: Run cleanup without prompts (dangerous, use with caution)"
            echo "  --size=<MB>: Set file size threshold for scanning (default: 100MB)"
            echo "  --help: Show this help message"
            echo "Example: curl -s <URL> | bash -s --force --size=50"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Create log file
touch "$LOG_FILE"
log "Starting macOS cleanup script (v1.0.0)"

# Scan for large files
log "Scanning for files larger than ${SIZE}MB"
sudo find "${SEARCH_DIRS[@]}" -type f -size +${SIZE}M -exec ls -lh {} \; 2>/dev/null | head -20 >> "$LOG_FILE"

# Calculate cache sizes
log "Calculating cache sizes..."
USER_CACHE_SIZE=$(calc_dir_size ~/Library/Caches)
SYSTEM_CACHE_SIZE=$(calc_dir_size /Library/Caches)
NPM_CACHE_SIZE=$(calc_dir_size ~/.npm)
NPX_CACHE_SIZE=$(calc_dir_size ~/.npm/_npx)
YARN_CACHE_SIZE=$(calc_dir_size ~/.yarn/cache)
BUN_CACHE_SIZE=$(calc_dir_size ~/.bun/install/cache)
GRADLE_CACHE_SIZE=$(calc_dir_size ~/.gradle/caches)
VSCODE_EXT_SIZE=$(calc_dir_size ~/.vscode/extensions)
NEXT_CACHE_SIZE=$(calc_pattern_size ".next/cache")
NEXT_WEBPACK_SIZE=$(calc_pattern_size ".next/cache/webpack")
NEXT_SWC_SIZE=$(calc_pattern_size "next-swc.darwin-arm64.node")
BUN_NEXT_CACHE_SIZE=$(calc_pattern_size ".bun-cache")

# Display cache summary
log "=== CACHE SUMMARY ==="
log "User cache (~/Library/Caches): ${USER_CACHE_SIZE}"
log "System cache (/Library/Caches): ${SYSTEM_CACHE_SIZE}"
log "npm cache (~/.npm): ${NPM_CACHE_SIZE}"
log "NPX cache (~/.npm/_npx): ${NPX_CACHE_SIZE}"
log "Yarn cache (~/.yarn/cache): ${YARN_CACHE_SIZE}"
log "Bun cache (~/.bun/install/cache): ${BUN_CACHE_SIZE}"
log "Gradle cache (~/.gradle/caches): ${GRADLE_CACHE_SIZE}"
log "VS Code extensions (~/.vscode/extensions): ${VSCODE_EXT_SIZE}"
log "Next.js cache (.next/cache): ${NEXT_CACHE_SIZE}"
log "Next.js webpack cache (.next/cache/webpack): ${NEXT_WEBPACK_SIZE}"
log "Next.js SWC binaries (next-swc.darwin-arm64.node): ${NEXT_SWC_SIZE}"
log "Bun Next.js cache (.bun-cache): ${BUN_NEXT_CACHE_SIZE}"

# Cleanup functions
clean_standard_caches() {
    log "Cleaning standard caches..."
    sudo rm -rf ~/Library/Caches/* 2>/dev/null && log "Cleared ~/Library/Caches"
    sudo rm -rf /Library/Caches/* 2>/dev/null && log "Cleared /Library/Caches"
    if command -v npm >/dev/null 2>&1; then
        npm cache clean --force 2>/dev/null && log "Cleared npm cache"
        sudo rm -rf ~/.npm/_npx/* 2>/dev/null && log "Cleared NPX cache"
    fi
    if command -v yarn >/dev/null 2>&1; then
        yarn cache clean --force 2>/dev/null && log "Cleared yarn cache"
    fi
    sudo rm -rf ~/.bun/install/cache/* 2>/dev/null && log "Cleared bun cache"
    sudo rm -rf ~/.gradle/caches/* 2>/dev/null && log "Cleared Gradle cache"
}

clean_nextjs_caches() {
    log "Cleaning Next.js caches..."
    local NEXT_CLEANED=0
    local WEBPACK_CLEANED=0
    local BUN_CLEANED=0
    for search_dir in "${SEARCH_DIRS[@]}"; do
        if [[ -d "$search_dir" ]]; then
            while IFS= read -r -d '' next_dir; do
                cache_dir="$next_dir/cache"
                webpack_dir="$next_dir/cache/webpack"
                if [[ -d "$cache_dir" ]]; then
                    sudo rm -rf "$cache_dir" 2>/dev/null && ((NEXT_CLEANED++)) && log "Removed $cache_dir"
                fi
                if [[ -d "$webpack_dir" ]]; then
                    sudo rm -rf "$webpack_dir"/* 2>/dev/null && ((WEBPACK_CLEANED++)) && log "Removed $webpack_dir contents"
                fi
            done < <(sudo find "$search_dir" -type d -name ".next" -print0 2>/dev/null)
            while IFS= read -r -d '' bun_cache; do
                sudo rm -rf "$bun_cache" 2>/dev/null && ((BUN_CLEANED++)) && log "Removed $bun_cache"
            done < <(sudo find "$search_dir" -type d -name ".bun-cache" -print0 2>/dev/null)
        fi
    done
    log "✓ Cleaned ${NEXT_CLEANED} Next.js cache directories"
    log "✓ Cleaned ${WEBPACK_CLEANED} Next.js webpack cache directories"
    log "✓ Cleaned ${BUN_CLEANED} Bun Next.js cache directories"
}

clean_nextjs_swc_binaries() {
    log "Cleaning Next.js binary SWC binaries..."
    local SWC_COUNT=0
    local SWC_SIZE_FREED=0
    for search_dir in "${SEARCH_DIR[@]}"; do
        if [[ -d "$search_dir" ]]; then
            while IFS= read -r -r -d '' swc_file; do
                size_before=$(sudo du -sm "$swc_file" 2>/dev/null | cut -f1)
                sudo rm -f "$swc_file" 2>/dev/null && ((SWC_COUNT++)) && SWC_SIZE_FREED=$((SWC_SIZE_FREED + size_before)) && log "Removed $swc_file (${size_before}MB)"
            done < <(sudo find "$search_dir" -name "next-swc.darwin-arm64.node" -print0 2>/dev/null)
        fi
    done
    log "✓ Removed ${SWC_COUNT} SWC binary files"
    log "✓ Total SWC space freed: ${SWC_SIZE_FREED}MB"
}

clean_vscode_extensions() {
    log "Cleaning VS Code extensions..."
    local EXT_COUNT=0
    local EXT_SIZE_FREED=0
    if [[ -d ~/.vscode/extensions ]]; then
        while IFS= read -r -d '' ext_dir; do
            size_before=$(sudo du -sm "$ext_dir" 2>/dev/null | cut -f1)
            sudo rm -rf "$ext_dir" 2>/dev/null && ((EXT_COUNT++)) && ((EXT_SIZE_FREED+=size_before)) && log "Removed $ext_dir (${size_before}MB)"
        done < <(sudo find ~/.vscode/extensions -type d -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
    fi
    log "✓ Removed ${EXT_COUNT} VS Code extension directories"
    log "✓ Total VS Code extension space freed: ${EXT_SIZE_FREED}MB"
}

# Execute cleanup based on FORCE_CLEAN
if [[ $FORCE_CLEAN -eq 1 ]]; then
    log "Running in force clean mode (--force)"
    clean_standard_caches
    clean_nextjs_caches
    clean_nextjs_swc_binaries
    clean_vscode_extensions
else
    log "Running in safe mode (minimal cleanup)"
    clean_standard_caches  # Safe to always run
    log "For deeper cleanup (Next.js, VS Code extensions, etc.), use '--force' option"
fi

# Final summary
log "=== Cleanup completed ==="
log "Cleanup log saved to: $LOG_FILE"
log "Freed up space in:"
log "- Standard caches (user, system, npm, yarn, bun, Gradle)"
if [[ $FORCE_CLEAN -eq 1 ]]; then
    log "- Next.js caches and SWC binaries"
    log "- VS Code extensions"
fi
log "Note: Some files (e.g., Next.js caches, SWC binaries) will be regenerated automatically."
log "Run 'npm install' or 'bun install' in projects if node_modules were affected."
log "Backup important projects before running with --force."
log "To scan again, run: sudo find ${SEARCH_DIRS[*]} -type f -size +${SIZE}M -exec ls -lh {} \;"
