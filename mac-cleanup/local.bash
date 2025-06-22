#!/bin/bash

# Default file size threshold (in MB) if not provided as argument
SIZE=${1:-100}

# Base directory for projects (adjust to your username/path)
PROJECTS_DIR="$HOME/Documents/projects"

# Additional search directories for comprehensive cleaning
# Exclude /System/Volumes/Data/ to avoid redundancy
SEARCH_DIRS=(
    "$HOME/Documents"
    "$HOME/Documents/projects"
    "$HOME/Desktop"
    "$HOME/Developer"
    "/private/var/www"
)

# Check if projects directory exists, if not use home directory
if [ ! -d "$PROJECTS_DIR" ]; then
    PROJECTS_DIR="$HOME"
    echo "Note: Using $HOME as projects directory since $HOME/Documents/projects doesn't exist"
fi

# Force clean option (set to 1 to skip prompts)
FORCE_CLEAN=${FORCE_CLEAN:-0}

echo "=== Scanning for files larger than ${SIZE}MB ==="
# Find files larger than specified size, suppress permission denied errors
sudo find "${SEARCH_DIRS[@]}" -type f -size +${SIZE}M -exec ls -lh {} \; 2>/dev/null | head -20

echo -e "\n=== Analyzing folder sizes in /Users ==="
# Analyze folder sizes in /Users, sorted by size
sudo du -sh /Users/* 2>/dev/null | sort -hr

echo -e "\n=== Disk usage summary ==="
# Display disk usage
df -h

echo -e "\n=== Memory (RAM) usage summary ==="
# Display memory usage using vm_stat
echo "Memory Stats (via vm_stat):"
vm_stat | grep -E "Pages free|Pages active|Pages inactive|Pages wired down|Pageins|Pageouts"
echo -e "\nTop 5 processes by memory usage (via top):"
top -l 1 -o mem -n 5 | head -n 15 | tail -n 5

echo -e "\n=== Calculating cache and temporary file sizes ==="

# Function to calculate directory size safely
calc_dir_size() {
    local dir="$1"
    if [ -d "$dir" ]; then
        sudo du -sh "$dir" 2>/dev/null | awk '{print $1}'
    else
        echo "0B"
    fi
}

# Function to find and calculate total size of specific files/directories
calc_pattern_size() {
    local pattern="$1"
    local total=0
    local count=0
    
    for search_dir in "${SEARCH_DIRS[@]}"; do
        if [ -d "$search_dir" ]; then
            while IFS= read -r -d '' file; do
                if [ -f "$file" ] || [ -d "$file" ]; then
                    size_mb=$(sudo du -sm "$file" 2>/dev/null | cut -f1)
                    total=$((total + size_mb))
                    count=$((count + 1))
                fi
            done < <(sudo find "$search_dir" -name "$pattern" -print0 2>/dev/null)
        fi
    done
    
    echo "${total}MB (${count} items)"
}

# Calculate cache sizes
USER_CACHE_SIZE=$(calc_dir_size ~/Library/Caches)
SYSTEM_CACHE_SIZE=$(sudo du -sh /Library/Caches 2>/dev/null | awk '{print $1}')
PUPPETEER_CACHE_SIZE=$(calc_dir_size ~/.cache/puppeteer)
NPM_CACHE_SIZE=$(calc_dir_size ~/.npm)
BUN_CACHE_SIZE=$(calc_dir_size ~/.bun/install/cache)
BREW_CACHE_SIZE=$(calc_dir_size ~/Library/Caches/Homebrew)
GRADLE_CACHE_SIZE=$(calc_dir_size ~/.gradle/caches)
NPX_CACHE_SIZE=$(calc_dir_size ~/.npm/_npx)
VSCODE_CACHE_SIZE=$(calc_dir_size ~/Library/Caches/com.microsoft.VSCode)
VSCODE_EXT_SIZE=$(calc_dir_size ~/.vscode/extensions)
CHROME_CACHE_SIZE=$(calc_dir_size ~/Library/Caches/Google/Chrome)
SAFARI_CACHE_SIZE=$(calc_dir_size ~/Library/Caches/com.apple.Safari)
QUICKLOOK_CACHE_SIZE=$(calc_dir_size ~/Library/Caches/com.apple.QuickLook.thumbnailcache)
SPOTLIGHT_CACHE_SIZE=$(sudo du -sh /.Spotlight-V100 2>/dev/null | awk '{print $1}')

# Enhanced Yarn cache calculation
YARN_CACHE_SIZE="0B"
YARN_TOTAL=0
for yarn_dir in ~/.cache/yarn ~/.yarn/cache; do
    if [ -d "$yarn_dir" ]; then
        size_mb=$(sudo du -sm "$yarn_dir" 2>/dev/null | cut -f1)
        YARN_TOTAL=$((YARN_TOTAL + size_mb))
    fi
done
if [ $YARN_TOTAL -gt 0 ]; then
    YARN_CACHE_SIZE="${YARN_TOTAL}MB"
fi

# Calculate Next.js related caches
NEXT_CACHE_SIZE="0B"
NEXT_CACHE_TOTAL=0
NEXT_WEBPACK_SIZE="0B"
NEXT_WEBPACK_TOTAL=0
for search_dir in "${SEARCH_DIRS[@]}"; do
    if [ -d "$search_dir" ]; then
        while IFS= read -r -d '' next_dir; do
            # Calculate general Next.js cache size
            cache_dir="$next_dir/cache"
            if [ -d "$cache_dir" ]; then
                size_mb=$(sudo du -sm "$cache_dir" 2>/dev/null | cut -f1)
                NEXT_CACHE_TOTAL=$((NEXT_CACHE_TOTAL + size_mb))
            fi
            
            # Calculate webpack cache size specifically
            webpack_dir="$next_dir/cache/webpack"
            if [ -d "$webpack_dir" ]; then
                webpack_size_mb=$(sudo du -sm "$webpack_dir" 2>/dev/null | cut -f1)
                NEXT_WEBPACK_TOTAL=$((NEXT_WEBPACK_TOTAL + webpack_size_mb))
            fi
        done < <(sudo find "$search_dir" -type d -name ".next" -print0 2>/dev/null)
    fi
done
if [ $NEXT_CACHE_TOTAL -gt 0 ]; then
    NEXT_CACHE_SIZE="${NEXT_CACHE_TOTAL}MB"
fi
if [ $NEXT_WEBPACK_TOTAL -gt 0 ]; then
    NEXT_WEBPACK_SIZE="${NEXT_WEBPACK_TOTAL}MB"
fi

# Calculate node_modules size
NODE_MODULES_SIZE=$(calc_pattern_size "node_modules")

# Calculate Next.js SWC binary files size
NEXT_SWC_SIZE=$(calc_pattern_size "next-swc.darwin-arm64.node")

# Calculate Bun cache for Next.js SWC
BUN_NEXT_CACHE_SIZE=$(calc_pattern_size ".bun-cache")

# Calculate temporary build files
TEMP_BUILD_SIZE=$(calc_pattern_size "*.tmp")
DIST_SIZE=$(calc_pattern_size "dist")
BUILD_SIZE=$(calc_pattern_size "build")

# Check Docker
if command -v docker >/dev/null 2>&1; then
    DOCKER_SIZE=$(docker system df --format '{{.Total}}' 2>/dev/null || echo "0B")
else
    DOCKER_SIZE="Docker not installed"
fi

# System files
LOG_SIZE=$(sudo du -sh /private/var/log 2>/dev/null | awk '{print $1}')
TRASH_SIZE=$(calc_dir_size ~/.Trash)
DOWNLOADS_SIZE=$(calc_dir_size ~/Downloads)

echo "=== CACHE AND TEMPORARY FILES SUMMARY ==="
echo "📁 Standard Caches:"
echo "  User cache (~/Library/Caches): ${USER_CACHE_SIZE:-0B}"
echo "  System cache (/Library/Caches): ${SYSTEM_CACHE_SIZE:-0B}"
echo "  Chrome cache: ${CHROME_CACHE_SIZE:-0B}"
echo "  Safari cache: ${SAFARI_CACHE_SIZE:-0B}"
echo "  VS Code cache: ${VSCODE_CACHE_SIZE:-0B}"
echo "  VS Code extensions: ${VSCODE_EXT_SIZE:-0B}"
echo "  QuickLook thumbnails: ${QUICKLOOK_CACHE_SIZE:-0B}"
echo ""
echo "🔧 Development Caches:"
echo "  npm cache (~/.npm): ${NPM_CACHE_SIZE:-0B}"
echo "  NPX cache (~/.npm/_npx): ${NPX_CACHE_SIZE:-0B}"
echo "  Yarn cache: ${YARN_CACHE_SIZE:-0B}"
echo "  Bun install cache (~/.bun/install/cache): ${BUN_CACHE_SIZE:-0B}"
echo "  Puppeteer cache: ${PUPPETEER_CACHE_SIZE:-0B}"
echo "  Homebrew cache: ${BREW_CACHE_SIZE:-0B}"
echo "  Gradle cache (~/.gradle/caches): ${GRADLE_CACHE_SIZE:-0B}"
echo ""
echo "⚛️ Next.js Related:"
echo "  Next.js cache (.next/cache): ${NEXT_CACHE_SIZE:-0B}"
echo "  Next.js webpack cache (.next/cache/webpack): ${NEXT_WEBPACK_SIZE:-0B}"
echo "  Next.js SWC binaries (next-swc.darwin-arm64.node): ${NEXT_SWC_SIZE:-0B}"
echo "  Bun Next.js cache (.bun-cache): ${BUN_NEXT_CACHE_SIZE:-0B}"
echo ""
echo "📦 Project Files:"
echo "  node_modules directories: ${NODE_MODULES_SIZE:-0B}"
echo "  dist directories: ${DIST_SIZE:-0B}"
echo "  build directories: ${BUILD_SIZE:-0B}"
echo ""
echo "🐳 Container & System:"
echo "  Docker (containers, images, volumes): ${DOCKER_SIZE:-0B}"
echo "  System logs (/private/var/log): ${LOG_SIZE:-0B}"
echo "  Trash (~/.Trash): ${TRASH_SIZE:-0B}"
echo "  Downloads (~/Downloads): ${DOWNLOADS_SIZE:-0B}"

# Enhanced cleaning function
clean_caches() {
    echo "🧹 Cleaning standard caches..."
    sudo rm -rf ~/Library/Caches/* 2>/dev/null
    sudo rm -rf /Library/Caches/* 2>/dev/null
    sudo rm -rf ~/.cache/puppeteer/* 2>/dev/null
    
    # Clean application caches
    sudo rm -rf ~/Library/Caches/com.microsoft.VSCode/* 2>/dev/null
    sudo rm -rf ~/Library/Caches/Google/Chrome/* 2>/dev/null
    sudo rm -rf ~/Library/Caches/com.apple.Safari/* 2>/dev/null
    sudo rm -rf ~/Library/Caches/com.apple.QuickLook.thumbnailcache/* 2>/dev/null
    
    if command -v npm >/dev/null 2>&1; then
        echo "🚀 Cleaning npm cache..."
        npm cache clean --force 2>/dev/null
        sudo rm -rf ~/.npm/_npx/* 2>/dev/null
    fi
    
    if command -v yarn >/dev/null 2>&1; then
        echo "🚀 Cleaning yarn cache..."
        yarn cache clean --force 2>/dev/null
    fi
    
    echo "🚀 Cleaning bun cache..."
    sudo rm -rf ~/.bun/install/cache/* 2>/dev/null
    
    if command -v brew >/dev/null 2>&1; then
        echo "🚖 Cleaning homebrew cache..."
        brew cleanup --prune=all 2>/dev/null
    fi
    
    echo "🚀 Cleaning Gradle cache..."
    sudo rm -rf ~/.gradle/caches/* 2>/dev/null
}

clean_nextjs_related() {
    echo "⚛️ Cleaning Next.js caches..."
    local NEXT_CLEANED=0
    local WEBPACK_CLEANED=0
    for search_dir in "${SEARCH_DIRS[@]}"; do
        if [ -d "$search_dir" ]; then
            while IFS= read -r -d '' next_dir; do
                cache_dir="$next_dir/cache"
                webpack_dir="$next_dir/cache/webpack"
                if [ -d "$cache_dir" ]; then
                    echo "🔍 Removing: ${cache_dir}"
                    sudo rm -rf "${cache_dir}" 2>/dev/null
                    if [[ $? -eq 0 ]]; then
                        NEXT_CLEANED=$((NEXT_CLEANED + 1))
                    fi
                fi
                if [ -d "$webpack_dir" ]; then
                    echo "🔍 Removing: ${webpack_dir}"
                    sudo rm -rf "${webpack_dir}"/* 2>/dev/null
                    if [[ $? -eq 0 ]]; then
                        WEBPACK_CLEANED=$((WEBPACK_CLEANED + 1))
                    fi
                fi
            done < <(sudo find "$search_dir" -type d -name ".next" -print0 2>/dev/null)
        fi
    done
    
    echo "⚛️ Cleaning Bun Next.js caches..."
    local BUN_CLEANED=0
    for search_dir in "${SEARCH_DIRS[@]}"; do
        if [ -d "$search_dir" ]; then
            while IFS= read -r -d '' bun_cache; do
                echo "🔍 Removing ${bun_cache}"
                sudo rm -rf "$bun_cache" 2>/dev/null
                if [[ $? -eq 0 ]]; then
                    BUN_CLEANED=$((BUN_CLEANED + 1))
                fi
            done < <(sudo find "$search_dir" -type d -name ".bun-cache" -print0 2>/dev/null)
        fi
    done
    
    echo "✅ Cleaned $NEXT_CLEANED Next.js cache directories"
    echo "✅ Cleaned $WEBPACK_CLEANED Next.js webpack directories"
    echo "✅ Cleaned $BUN_CLEANED Bun cache directories"
}

clean_nextjs_swc_binaries() {
    echo "⚛️ Cleaning Next.js SWC binary files..."
    local SWC_CLEANED=0
    local SWC_SIZE_FREED=0
    
    for search_dir in "${SEARCH_DIRS[@]}"; do
        if [ -d "$search_dir" ]; then
            while IFS= read -r -d '' swc_file; do
                size_before=$(sudo du -sm "$swc_file" 2>/dev/null | cut -f1)
                echo "  Removing: $swc_file (${size_before}MB)"
                sudo rm -f "$swc_file" 2>/dev/null
                if [[ $? -eq 0 ]]; then
                    SWC_CLEANED=$((SWC_CLEANED + 1))
                    SWC_SIZE_FREED=$((SWC_SIZE_FREED + size_before))
                fi
            done < <(sudo find "$search_dir" -name "next-swc.darwin-arm64.node" -print0 2>/dev/null)
        fi
    done
    
    echo "✅ Removed $SWC_CLEANED SWC binary files"
    echo "✅ Total SWC space freed: ${SWC_SIZE_FREED}MB"
}

clean_vscode_extensions() {
    echo "📝 Cleaning VS Code extensions..."
    local EXT_CLEANED=0
    local EXT_SIZE_FREED=0
    if [ -d ~/.vscode/extensions ]; then
        while IFS= read -r -d '' ext_dir; do
            size_before=$(sudo du -sm "$ext_dir" 2>/dev/null | cut -f1)
            echo "  Removing: $ext_dir (${size_before}MB)"
            sudo rm -rf "$ext_dir" 2>/dev/null
            if [[ $? -eq 0 ]]; then
                EXT_CLEANED=$((EXT_CLEANED + 1))
                EXT_SIZE_FREED=$((EXT_SIZE_FREED + size_before))
            fi
        done < <(sudo find ~/.vscode/extensions -type d -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
    fi
    echo "✅ Removed $EXT_CLEANED VS Code extension directories"
    echo "✅ Total VS Code extension space freed: ${EXT_SIZE_FREED}MB"
}

clean_build_directories() {
    echo "🏗️ Cleaning build directories..."
    local BUILD_CLEANED=0
    for search_dir in "${SEARCH_DIRS[@]}"; do
        if [ -d "$search_dir" ]; then
            # Clean dist directories
            while IFS= read -r -d '' dist_dir; do
                echo "🔍 Removing ${dist_dir}"
                sudo rm -rf "$dist_dir" 2>/dev/null
                if [[ $? -eq 0 ]]; then
                    BUILD_CLEANED=$((BUILD_CLEANED + 1))
                fi
            done < <(sudo find "$search_dir" -type d -name "dist" -print0 2>/dev/null)
            
            # Clean build directories
            while IFS= read -r -d '' build_dir; do
                if [[ "$build_dir" != *"/node_modules/"* ]] && [[ "$build_dir" != "/usr/"* ]] && [[ "$build_dir" != "/System/"* ]]; then
                    echo "🔍 Removing ${build_dir}"
                    sudo rm -rf "$build_dir" 2>/dev/null
                    if [[ $? -eq 0 ]]; then
                        BUILD_CLEANED=$((BUILD_CLEANED + 1))
                    fi
                fi
            done < <(sudo find "$search_dir" -type d -name "build" -print0 2>/dev/null)
        fi
    done
    echo "✅ Cleaned $BUILD_CLEANED build/dist directories"
}

# Function to prompt for confirmation unless FORCE_CLEAN is set
confirm_action() {
    local prompt="$1"
    local action="$2"
    if [[ $FORCE_CLEAN -eq 1 ]]; then
        eval "$action"
        return 0
    fi
    read -p "$prompt (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        eval "$action"
        echo "✅ $prompt completed."
    else
        echo "❌ $prompt skipped."
    fi
}

# Interactive cleaning prompts
echo -e "\n=== CLEANING OPTIONS ==="
confirm_action "🧹 Clean all standard caches (user, system, browser, development tools)?" "clean_caches"
confirm_action "⚛️ Clean Next.js caches (.next/cache and .bun-cache directories)?" "clean_nextjs_related"
confirm_action "🔧 Clean Next.js SWC binary files (next-swc.darwin-arm64.node)?" "clean_nextjs_swc_binaries"
confirm_action "📝 Clean VS Code extensions (~/.vscode/extensions)?" "clean_vscode_extensions"
confirm_action "🏗️ Clean build/dist directories?" "clean_build_directories"

confirm_action "📦 Delete node_modules directories? (WARNING: Only for inactive projects)" \
    'echo "🗑️ Deleting node_modules directories..."; NODE_CLEANED=0; for search_dir in "${SEARCH_DIRS[@]}"; do if [ -d "$search_dir" ]; then while IFS= read -r -d "" node_dir; do echo "  Removing: $node_dir"; sudo rm -rf "$node_dir" 2>/dev/null; if [[ $? -eq 0 ]]; then NODE_CLEANED=$((NODE_CLEANED + 1)); fi; done < <(sudo find "$search_dir" -type d -name "node_modules" -print0 2>/dev/null); fi; done; echo "✅ Cleaned $NODE_CLEANED node_modules directories."'

if command -v docker >/dev/null 2>&1; then
    confirm_action "🐳 Clean unused Docker containers, images, and volumes?" \
        'echo "🐳 Cleaning Docker..."; docker system prune -a --volumes -f 2>/dev/null; echo "✅ Docker cleaning completed."'
fi

confirm_action "📝 Delete system logs older than 30 days?" \
    'echo "📝 Cleaning old system logs..."; sudo find /private/var/log -type f -name "*.log" -mtime +30 -exec rm -f {} \; 2>/dev/null; echo "✅ Log cleaning completed."'

confirm_action "🗑️ Empty Trash?" \
    'echo "🗑️ Emptying Trash..."; sudo rm -rf ~/.Trash/* 2>/dev/null; echo "✅ Trash cleaning completed."'

confirm_action "📥 Delete Downloads files older than 90 days?" \
    'echo "📥 Cleaning old Downloads..."; sudo find ~/Downloads -type f -mtime +90 -exec rm -f {} \; 2>/dev/null; echo "✅ Downloads cleaning completed."'

# Interactive disk analysis
echo -e "\n=== INTERACTIVE DISK ANALYSIS ==="
if [[ $FORCE_CLEAN -eq 0 ]]; then
    read -p "🔍 Run ncdu for interactive disk usage analysis? (y/N): " ncdu_confirm
    if [[ "$ncdu_confirm" =~ ^[Yy]$ ]]; then
        if command -v ncdu >/dev/null 2>&1; then
            echo "Choose directory to analyze:"
            echo "1) Home directory ($HOME)"
            echo "2) Documents ($HOME/Documents)" 
            echo "3) Projects ($PROJECTS_DIR)"
            echo "4) Root directory (/)"
            read -p "Enter choice (1-4, default: 2): " ncdu_choice
            
            case $ncdu_choice in
                1) ncdu_dir="$HOME" ;;
                3) ncdu_dir="$PROJECTS_DIR" ;;
                4) ncdu_dir="/" ;;
                *) ncdu_dir="$HOME/Documents" ;;
            esac
            
            echo "Running ncdu on $ncdu_dir (use 'd' to delete, 'q' to quit)..."
            if [ "$ncdu_dir" = "/" ]; then
                sudo ncdu "$ncdu_dir"
            else
                ncdu "$ncdu_dir"
            fi
        else
            echo "❌ ncdu not installed. Install with: brew install ncdu"
        fi
    else
        echo "❌ ncdu analysis skipped."
    fi
fi

echo -e "\n=== 🎉 CLEANUP SUMMARY 🎉 ==="
echo "✅ Script completed successfully!"
echo ""
echo "💡 What was cleaned:"
echo "   • Standard caches (browser, system, development tools)"
echo "   • Next.js build caches and webpack files"
echo "   • Next.js SWC binary files"
echo "   • Bun caches for Next.js projects"
echo "   • VS Code extensions"
echo "   • Build and dist directories"
echo "   • Optional: node_modules, Docker resources, logs, trash"
echo ""
echo "🔄 Auto-regenerated files:"
echo "   • All caches will be rebuilt automatically when needed"
echo "   • SWC binaries will be re-downloaded on next Next.js build"
echo "   • Build directories will be recreated on next build"
echo ""
echo "⚠️ Remember:"
echo "   • Run 'npm install' or 'bun install' in projects where node_modules were deleted"
echo "   • First Next.js build after cleanup may take longer due to cache rebuild"
echo "   • Backup important projects before running this script"
echo ""
echo "📁 Search directories used:"
for dir in "${SEARCH_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "  ✅ $dir"
    else
        echo "  ❌ $dir (not found)"
    fi
done
