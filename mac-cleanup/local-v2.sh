#!/bin/bash

# --- Konfigurasi & Default Sistem ---

# Ambang batas ukuran file default (dalam MB) untuk pemindaian file besar
DEFAULT_SIZE_THRESHOLD=100

# Ambang batas usia file lama (dalam hari) untuk rekomendasi pembersihan
OLD_FILE_THRESHOLD_DAYS=90

# Direktori dasar untuk proyek
PROJECTS_DIR="$HOME/Documents/projects"

# Direktori pencarian komprehensif. Tambahan: /Applications untuk DMG/PKG
SEARCH_DIRS=(
    "$HOME/Documents"
    "$HOME/Documents/projects"
    "$HOME/Desktop"
    "$HOME/Developer"
    "$HOME/Downloads"
    "/private/var/www"
    "/Library/Developer"
    "/Applications"
)

# Direktori yang HARUS DIHINDARI saat membersihkan (untuk mencegah penghapusan kritis)
EXCLUDE_DIRS=(
    "/System"
    "/Volumes"
    "/usr"
    "/bin"
    "/sbin"
    "/Applications" # Jangan hapus aplikasi itu sendiri, hanya di dalamnya
    "/Library"      # Jangan hapus Library itu sendiri, hanya di dalamnya
    "~/Library/Mobile Documents/com~apple~CloudDocs" # iCloud Drive
    "/private/var/db" # Database sistem penting
)

# Bendera global untuk memaksa pembersihan tanpa prompt (0 = interaktif, 1 = paksa)
FORCE_CLEAN=0
# Bendera untuk mode Dry Run (0 = hapus, 1 = hanya tampilkan)
DRY_RUN=0

# File log untuk eksekusi otomatis
LOG_FILE="$HOME/Library/Logs/mac-ai-cleanup-script.log"
# File untuk menyimpan ruang yang dibebaskan (untuk pelaporan akhir)
FREED_SPACE_REPORT="/tmp/freed_space_report.txt"
echo "" > "$FREED_SPACE_REPORT" # Kosongkan file di awal

# --- Fungsi Pembantu Utama ---

# Fungsi untuk menampilkan pesan ke konsol dan log file
log_message() {
    local type="$1" # INFO, WARN, ERROR, DEBUG
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$type] $message" | tee -a "$LOG_FILE"
}

# Fungsi untuk menghitung ukuran direktori dengan aman
calc_dir_size() {
    local dir="$1"
    if [ -d "$dir" ]; then
        # Menggunakan `du -sh` untuk human-readable output, lalu memotong untuk mendapatkan ukuran saja
        sudo du -sh "$dir" 2>/dev/null | awk '{print $1}' || echo "0B"
    else
        echo "0B"
    fi
}

# Fungsi untuk menghitung ukuran dalam MB dari sebuah path (file atau direktori)
get_size_in_mb() {
    local path="$1"
    if [ -e "$path" ]; then
        sudo du -sm "$path" 2>/dev/null | cut -f1 || echo 0
    else
        echo 0
    fi
}

# Fungsi untuk mencari dan menghitung total ukuran file/direktori berdasarkan nama/pola
# Mengembalikan ukuran dan jumlah item. Item yang ditemukan disimpan di array global `LAST_FOUND_ITEMS`.
LAST_FOUND_ITEMS=() # Global array to store paths found by calc_pattern_size
calc_pattern_size() {
    local pattern="$1"
    local type_flag="${2:-}" # -type f or -type d, if not specified, find both
    local total_mb=0
    local count=0
    LAST_FOUND_ITEMS=() # Reset for each call

    for search_dir in "${SEARCH_DIRS[@]}"; do
        if [ -d "$search_dir" ]; then
            local find_cmd="sudo find \"$search_dir\" $type_flag -name \"$pattern\" -print0"
            if [[ "$search_dir" == "/" ]]; then # Tambahkan pengecualian untuk pencarian root
                find_cmd="sudo find \"$search_dir\" -path \"*/System/*\" -prune -o -path \"*/Volumes/*\" -prune -o -path \"*/usr/*\" -prune -o $type_flag -name \"$pattern\" -print0"
            fi

            while IFS= read -r -d '' item; do
                local skip=false
                for exclude_dir in "${EXCLUDE_DIRS[@]}"; do
                    local expanded_exclude_dir=$(eval echo "$exclude_dir")
                    if [[ "$item" == "$expanded_exclude_dir"* ]]; then
                        skip=true
                        break
                    fi
                done
                if $skip; then continue; fi

                local size_mb=$(get_size_in_mb "$item")
                total_mb=$((total_mb + size_mb))
                count=$((count + 1))
                LAST_FOUND_ITEMS+=("$item")
            done < <(eval "$find_cmd" 2>/dev/null)
        fi
    done
    echo "${total_mb}MB (${count} items)"
}

# Fungsi untuk menjalankan perintah penghapusan dengan aman dan mencatat ruang yang dibebaskan
perform_deletion() {
    local item_path="$1"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_message "INFO" "Dry Run: Akan menghapus '$item_path'"
        return 0
    fi

    local size_before=$(get_size_in_mb "$item_path")
    log_message "INFO" "Menghapus: '$item_path' (${size_before}MB)"
    sudo rm -rf "$item_path" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo "$size_before" >> "$FREED_SPACE_REPORT"
        return 0
    else
        log_message "ERROR" "Gagal menghapus '$item_path'."
        return 1
    fi
}

# Fungsi untuk meminta konfirmasi atau menjalankan otomatis jika FORCE_CLEAN/DRY_RUN
confirm_and_execute() {
    local prompt="$1"
    local command_to_execute="$2"
    local success_message="$3"
    local failure_message="$4"

    if [[ "$FORCE_CLEAN" -eq 1 ]]; then
        log_message "INFO" "$prompt (Mode Pembersihan Otomatis)"
        eval "$command_to_execute"
        if [[ $? -eq 0 ]]; then
            log_message "INFO" "✅ $success_message"
            return 0
        else
            log_message "ERROR" "❌ $failure_message (Perintah gagal)"
            return 1
        fi
    elif [[ "$DRY_RUN" -eq 1 ]]; then
        log_message "INFO" "Dry Run: $prompt"
        # Dalam dry run, kita tidak mengeksekusi perintah penghapusan, hanya menampilkan
        # apa yang akan dihapus jika DRY_RUN tidak aktif.
        eval "$command_to_execute" # Ini akan memanggil perform_deletion yang akan melaporkan dry run
        log_message "INFO" "✅ $prompt (simulasi selesai)."
        return 0
    fi

    read -p "$prompt (y/N): " confirm_input
    if [[ "$confirm_input" =~ ^[Yy]$ ]]; then
        log_message "INFO" "Mengeksekusi: $prompt"
        eval "$command_to_execute"
        if [[ $? -eq 0 ]]; then
            log_message "INFO" "✅ $success_message"
            return 0
        else
            log_message "ERROR" "❌ $failure_message (Perintah gagal)"
            return 1
        fi
    else
        log_message "INFO" "❌ $prompt dilewati oleh pengguna."
        return 2 # Menunjukkan tindakan dilewati
    fi
}

# --- Fungsi Analisis Cerdas (Simulasi AI) ---

# Menganalisis direktori proyek untuk mendeteksi jenis teknologi/lingkungan
analyze_projects_for_recommendations() {
    log_message "INFO" "Menganalisis direktori proyek untuk rekomendasi cerdas..."
    local recommended_actions=""

    if [ -d "$PROJECTS_DIR" ]; then
        # Deteksi proyek Node.js
        if sudo find "$PROJECTS_DIR" -maxdepth 3 -name "package.json" -print -quit 2>/dev/null; then
            recommended_actions+="  • Proyek Node.js terdeteksi (direktori node_modules, cache npm/yarn/bun, Next.js).\n"
        fi
        # Deteksi proyek Java/Gradle
        if sudo find "$PROJECTS_DIR" -maxdepth 3 -name "build.gradle" -print -quit 2>/dev/null; then
            recommended_actions+="  • Proyek Java/Gradle terdeteksi (cache Gradle, direktori build).\n"
        fi
        # Deteksi proyek Xcode
        if sudo find "$PROJECTS_DIR" -maxdepth 3 -name "*.xcodeproj" -print -quit 2>/dev/null || \
           sudo find "$PROJECTS_DIR" -maxdepth 3 -name "*.xcworkspace" -print -quit 2>/dev/null; then
            recommended_actions+="  • Proyek Xcode terdeteksi (DerivedData, Archives, iOS DeviceSupport).\n"
        fi
        # Deteksi proyek Docker
        if sudo find "$PROJECTS_DIR" -maxdepth 3 -name "Dockerfile" -print -quit 2>/dev/null; then
            recommended_actions+="  • Dockerfiles terdeteksi (gambar/kontainer/volume Docker).\n"
        fi
    fi

    if [ -n "$recommended_actions" ]; then
        echo -e "\n--- Rekomendasi Cerdas Berdasarkan Lingkungan Anda ---"
        echo -e "Berdasarkan proyek Anda, saya merekomendasikan untuk fokus pada:\n${recommended_actions}"
        echo "Ini dapat membebaskan ruang disk signifikan."
    else
        echo -e "\n--- Analisis Lingkungan ---"
        echo "Tidak ada jenis proyek spesifik yang terdeteksi secara otomatis di direktori proyek Anda."
    fi
}

# Fungsi untuk mendeteksi file "lama" atau jarang diakses
detect_old_files() {
    log_message "INFO" "Mendeteksi file lama di Direktori Unduhan/Dokumen..."
    local old_files_count=0
    local old_files_size=0
    local potential_candidates=()

    # Gunakan mdfind untuk pencarian file yang lebih efisien berdasarkan tanggal modifikasi
    # Pencarian file di Downloads dan Documents yang tidak diakses dalam X hari
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            size_mb=$(get_size_in_mb "$file")
            old_files_size=$((old_files_size + size_mb))
            old_files_count=$((old_files_count + 1))
            potential_candidates+=("$file")
        fi
    done < <(mdfind -onlyin "$HOME/Downloads" -onlyin "$HOME/Documents" "kMDItemLastUsedDate < \$time.$OLD_FILE_THRESHOLD_DAYS\d" 2>/dev/null)

    if [ ${old_files_count} -gt 0 ]; then
        echo -e "\n--- File Lama & Jarang Digunakan ---"
        echo "Ditemukan ${old_files_count} file (${old_files_size}MB) yang tidak diakses dalam ${OLD_FILE_THRESHOLD_DAYS} hari terakhir di Unduhan/Dokumen Anda."
        echo "Ini adalah kandidat yang baik untuk ditinjau dan dihapus secara manual."
        if [[ "$FORCE_CLEAN" -eq 0 ]]; then
            read -p "Tampilkan daftar 10 file teratas ini? (y/N): " show_old
            if [[ "$show_old" =~ ^[Yy]$ ]]; then
                # Urutkan berdasarkan ukuran dan tampilkan 10 teratas
                printf "%s\n" "${potential_candidates[@]}" | xargs -I {} du -sh {} 2>/dev/null | sort -rh | head -10
            fi
        fi
    else
        echo -e "\n--- File Lama & Jarang Digunakan ---"
        echo "Tidak ada file signifikan yang jarang diakses ditemukan di Unduhan/Dokumen Anda dalam ${OLD_FILE_THRESHOLD_DAYS} hari."
    fi
}


# --- Fungsi Pembersihan Utama (Dengan Logic Penghapusan) ---

clean_standard_caches() {
    perform_deletion ~/Library/Caches/*
    perform_deletion /Library/Caches/*
    perform_deletion ~/Library/Caches/com.microsoft.VSCode/*
    perform_deletion ~/Library/Caches/Google/Chrome/*
    perform_deletion ~/Library/Caches/com.apple.Safari/*
    perform_deletion ~/Library/Caches/com.apple.QuickLook.thumbnailcache/*
    perform_deletion /private/var/folders/*/*/C/com.apple.appstore/*
    perform_deletion /private/var/folders/*/*/C/com.apple.SoftwareUpdate/*
    
    # Font Caches (perintah khusus)
    if [[ "$DRY_RUN" -eq 0 ]]; then
        sudo atsutil databases -remove 2>/dev/null
        sudo rm -rf /Library/Caches/com.apple.ATS/* 2>/dev/null
        sudo rm -rf ~/Library/Caches/com.apple.ATS/* 2>/dev/null
        log_message "INFO" "Font caches dibersihkan."
    else
        log_message "INFO" "Dry Run: Font caches akan dibersihkan."
    fi
}

clean_development_tool_caches() {
    if command -v npm >/dev/null 2>&1; then
        if [[ "$DRY_RUN" -eq 0 ]]; then npm cache clean --force 2>/dev/null; log_message "INFO" "Cache npm dibersihkan."; fi
        perform_deletion ~/.npm/_npx/*
    fi

    if command -v yarn >/dev/null 2>&1; then
        if [[ "$DRY_RUN" -eq 0 ]]; then yarn cache clean --force 2>/dev/null; log_message "INFO" "Cache Yarn dibersihkan."; fi
    fi

    if command -v bun >/dev/null 2>&1; then
        if [[ "$DRY_RUN" -eq 0 ]]; then bun clean --force 2>/dev/null; log_message "INFO" "Cache Bun dibersihkan."; else log_message "INFO" "Dry Run: Cache Bun akan dibersihkan."; fi
        perform_deletion ~/.bun/install/cache/*
    fi

    if command -v brew >/dev/null 2>&1; then
        if [[ "$DRY_RUN" -eq 0 ]]; then brew cleanup --prune=all 2>/dev/null; log_message "INFO" "Cache Homebrew dibersihkan."; fi
        perform_deletion "$(brew --cache)"/*
    fi

    perform_deletion ~/.gradle/caches/*
    perform_deletion ~/.cache/puppeteer/*
}

clean_xcode_components() {
    perform_deletion "$HOME/Library/Developer/Xcode/DerivedData"/*
    perform_deletion "$HOME/Library/Developer/Xcode/Archives"/*
    perform_deletion "$HOME/Library/Developer/Xcode/iOS DeviceSupport"/* # Membersihkan semua versi
    perform_deletion "$HOME/Library/Developer/Xcode/UserData/Previews/Simulator Devices"/*
}

clean_nextjs_related() {
    # .next/cache dan .next/cache/webpack
    calc_pattern_size ".next" "-type d" # Mengisi LAST_FOUND_ITEMS
    for next_dir in "${LAST_FOUND_ITEMS[@]}"; do
        perform_deletion "$next_dir/cache"
        perform_deletion "$next_dir/cache/webpack"
    done
    # .bun-cache
    calc_pattern_size ".bun-cache" "-type d" # Mengisi LAST_FOUND_ITEMS
    for bun_cache_dir in "${LAST_FOUND_ITEMS[@]}"; do
        perform_deletion "$bun_cache_dir"
    done
}

clean_nextjs_swc_binaries() {
    calc_pattern_size "next-swc.darwin-arm64.node" "-type f" # Mengisi LAST_FOUND_ITEMS
    for swc_file in "${LAST_FOUND_ITEMS[@]}"; do
        perform_deletion "$swc_file"
    done
}

clean_vscode_extensions() {
    if [ -d ~/.vscode/extensions ]; then
        # Hanya menghapus jika ini bukan dry run
        if [[ "$DRY_RUN" -eq 0 ]]; then
            log_message "INFO" "Membersihkan semua ekstensi VS Code. Anda harus menginstal ulang yang Anda butuhkan."
            sudo rm -rf ~/.vscode/extensions/* 2>/dev/null
            if [[ $? -eq 0 ]]; then log_message "INFO" "Ekstensi VS Code dibersihkan."; else log_message "ERROR" "Gagal membersihkan ekstensi VS Code."; fi
        else
            log_message "INFO" "Dry Run: Ekstensi VS Code akan dibersihkan."
        fi
    fi
}

clean_build_and_temp_directories() {
    local patterns=("dist" "build" "tmp" "temp" "*.tmp" "*.temp" ".DS_Store" "._*" ".localized" "*.bak" "*.old" "*.swp" "*.swo" "*.log" "Thumbs.db" "node_modules/.cache")
    for pattern in "${patterns[@]}"; do
        # Menggunakan mdfind untuk beberapa pola yang umum dan cepat
        if [[ "$pattern" == "dist" || "$pattern" == "build" || "$pattern" == ".DS_Store" || "$pattern" == "*.tmp" ]]; then
            # Hati-hati dengan mdfind di root, batasi ke direktori yang diketahui aman
            local mdfind_cmd="mdfind -onlyin \"$HOME\" -name \"$pattern\""
            while IFS= read -r item_to_delete; do
                local skip=false
                for exclude_dir in "${EXCLUDE_DIRS[@]}"; do
                    local expanded_exclude_dir=$(eval echo "$exclude_dir")
                    if [[ "$item_to_delete" == "$expanded_exclude_dir"* ]]; then
                        skip=true
                        break
                    fi
                done
                if $skip; then continue; fi
                perform_deletion "$item_to_delete"
            done < <(eval "$mdfind_cmd" 2>/dev/null)
        else
            # Fallback ke find untuk pola yang lebih kompleks atau di luar jangkauan mdfind yang aman
            calc_pattern_size "$pattern" # Mengisi LAST_FOUND_ITEMS
            for item_to_delete in "${LAST_FOUND_ITEMS[@]}"; do
                perform_deletion "$item_to_delete"
            done
        fi
    done
}

clean_node_modules() {
    # Mengumpulkan semua jalur node_modules dan menghapusnya
    local node_modules_paths=()
    for search_dir in "${SEARCH_DIRS[@]}"; do
        if [ -d "$search_dir" ]; then
            while IFS= read -r -d '' node_dir; do
                node_modules_paths+=("$node_dir")
            done < <(sudo find "$search_dir" -type d -name "node_modules" -print0 2>/dev/null)
        fi
    done

    # Hapus secara berurutan
    for node_dir in "${node_modules_paths[@]}"; do
        perform_deletion "$node_dir"
    done
}

clean_docker_resources() {
    if command -v docker >/dev/null 2>&1; then
        if [[ "$DRY_RUN" -eq 0 ]]; then
            docker system prune -a --volumes -f 2>/dev/null
            if [[ $? -eq 0 ]]; then log_message "INFO" "Pembersihan Docker selesai."; else log_message "ERROR" "Pembersihan Docker gagal."; fi
        else
            log_message "INFO" "Dry Run: Docker containers, images, dan volumes akan dipangkas."
        fi
    else
        log_message "WARN" "Docker tidak terinstal. Melewati pembersihan Docker."
    fi
}

clean_system_and_user_logs() {
    # Log sistem
    if [[ "$DRY_RUN" -eq 0 ]]; then
        sudo find /private/var/log -type f -name "*.log" -mtime +30 -exec rm -f {} \; 2>/dev/null
    fi
    # Log aplikasi pengguna
    if [[ "$DRY_RUN" -eq 0 ]]; then
        find ~/Library/Logs -type f -name "*.log" -mtime +30 -exec rm -f {} \; 2>/dev/null
    fi
    # Laporan Crash
    if [[ "$DRY_RUN" -eq 0 ]]; then
        find ~/Library/Logs/DiagnosticReports -type f -mtime +90 -exec rm -f {} \; 2>/dev/null
        sudo find /Library/Logs/DiagnosticReports -type f -mtime +90 -exec rm -f {} \; 2>/dev/null
        log_message "INFO" "Log lama dan laporan crash dibersihkan."
    else
        log_message "INFO" "Dry Run: Log dan laporan crash lama akan dibersihkan."
    fi
}

empty_trash() {
    perform_deletion ~/.Trash/*
}

clean_downloads() {
    if [[ "$DRY_RUN" -eq 0 ]]; then
        sudo find ~/Downloads -type f -mtime +90 -exec rm -f {} \; 2>/dev/null
        sudo find ~/Downloads -type f \( -name "*.dmg" -o -name "*.pkg" \) -mtime +30 -exec rm -f {} \; 2>/dev/null
        log_message "INFO" "File Unduhan lama dan installer DMG/PKG dibersihkan."
    else
        log_message "INFO" "Dry Run: File Unduhan lama dan installer DMG/PKG akan dibersihkan."
    fi
}

clean_broken_symlinks() {
    local broken_symlinks=()
    for search_dir in "${SEARCH_DIRS[@]}"; do
        if [ -d "$search_dir" ]; then
            while IFS= read -r -d '' symlink; do
                broken_symlinks+=("$symlink")
            done < <(sudo find "$search_dir" -xtype l -print0 2>/dev/null)
        fi
    done
    for symlink in "${broken_symlinks[@]}"; do
        perform_deletion "$symlink"
    done
}

clean_user_library_junk() {
    perform_deletion "$HOME/Library/Saved Application State"/*
    perform_deletion "$HOME/Library/Application Support/CrashReporter"/*
    perform_deletion "$HOME/Library/Containers/com.apple.Safari/Data/Library/Safari/SafeBrowse.db"
    # Tambahan: Empty Caches for Mail.app attachments
    perform_deletion "$HOME/Library/Containers/com.apple.mail/Data/Library/Caches/Mail Downloads"/*
}

clean_time_machine_local_snapshots() {
    if sysctl -n sysctl.proc_info.procs_system | grep -q 'backupd'; then
        log_message "WARN" "Proses Time Machine sedang berjalan. Snapshot lokal mungkin tidak bisa dihapus sepenuhnya."
    fi
    if [[ "$DRY_RUN" -eq 0 ]]; then
        # tmutil bisa dihapus secara langsung tanpa perlu du -sm sebelumnya
        sudo tmutil deletelocalsnapshots / 2>/dev/null
        if [[ $? -eq 0 ]]; then log_message "INFO" "Snapshot lokal Time Machine dihapus."; else log_message "ERROR" "Gagal menghapus snapshot lokal Time Machine."; fi
    else
        log_message "INFO" "Dry Run: Snapshot lokal Time Machine akan dihapus."
    fi
}

# --- Struktur Pembersihan Bertahap (Simulasi Mode Pembersihan) ---

# Level 1: Pembersihan Aman - Cache & File Sementara yang Umum
clean_level_1_safe() {
    log_message "INFO" "Memulai pembersihan Level 1: Aman dan Umum."
    confirm_and_execute "🧹 Bersihkan semua cache standar dan aplikasi (termasuk unduhan & font)?" "clean_standard_caches" "Cache standar & aplikasi dibersihkan." "Gagal membersihkan cache standar & aplikasi."
    confirm_and_execute "🏗️ Bersihkan direktori build/dist/sementara umum (.tmp, .temp, .DS_Store, dll.)?" "clean_build_and_temp_directories" "Direktori build/dist/sementara dibersihkan." "Gagal membersihkan direktori build/dist/sementara."
    confirm_and_execute "📝 Hapus log sistem dan pengguna lama (lebih dari 30 hari) serta laporan crash?" "clean_system_and_user_logs" "Log dan laporan crash dibersihkan." "Gagal membersihkan log dan laporan crash."
    confirm_and_execute "🗑️ Kosongkan Sampah?" "empty_trash" "Sampah dikosongkan." "Gagal mengosongkan Sampah."
    confirm_and_execute "📥 Hapus file Unduhan lama (lebih dari 90 hari) dan installer DMG/PKG (lebih dari 30 hari)?" "clean_downloads" "File Unduhan lama dan installer dibersihkan." "Gagal membersihkan file Unduhan lama dan installer."
    confirm_and_execute "🔗 Bersihkan symbolic link yang rusak?" "clean_broken_symlinks" "Symbolic link yang rusak dibersihkan." "Gagal membersihkan symbolic link yang rusak."
    confirm_and_execute "📚 Bersihkan sampah umum di ~/Library (Saved Application State, Mail Downloads)?" "clean_user_library_junk" "Sampah Library pengguna dibersihkan." "Gagal membersihkan sampah Library pengguna."
    log_message "INFO" "Pembersihan Level 1 selesai."
}

# Level 2: Pembersihan Agresif - Cache Pengembangan & Sumber Daya Kontainer
clean_level_2_aggressive() {
    log_message "INFO" "Memulai pembersihan Level 2: Agresif (Pengembangan & Kontainer)."
    confirm_and_execute "🚀 Bersihkan cache alat pengembangan (npm, Yarn, Bun, Homebrew, Gradle, Puppeteer, Homebrew Cellar)?" "clean_development_tool_caches" "Cache alat pengembangan dibersihkan." "Gagal membersihkan cache alat pengembangan."
    confirm_and_execute "🛠️ Bersihkan komponen Xcode (DerivedData, Archives, iOS DeviceSupport, Simulator Previews)?" "clean_xcode_components" "Komponen Xcode dibersihkan." "Gagal membersihkan komponen Xcode."
    confirm_and_execute "⚛️ Bersihkan cache Next.js (.next/cache dan .bun-cache directories)?" "clean_nextjs_related" "Cache Next.js dibersihkan." "Gagal membersihkan cache Next.js."
    confirm_and_execute "🔧 Bersihkan file biner Next.js SWC (next-swc.darwin-arm64.node)?" "clean_nextjs_swc_binaries" "Biner SWC Next.js dibersihkan." "Gagal membersihkan biner SWC Next.js."
    if command -v docker >/dev/null 2>&1; then
        confirm_and_execute "🐳 Bersihkan kontainer, image, dan volume Docker yang tidak terpakai?" "clean_docker_resources" "Sumber daya Docker dibersihkan." "Gagal membersihkan sumber daya Docker."
    fi
    log_message "INFO" "Pembersihan Level 2 selesai."
}

# Level 3: Pembersihan Berisiko - Menghapus data yang dapat diregenerasi tetapi memakan waktu
clean_level_3_risky() {
    log_message "INFO" "Memulai pembersihan Level 3: Berisiko (Membutuhkan regenerasi)."
    confirm_and_execute "📦 Hapus direktori node_modules? (PERINGATAN: Hanya untuk proyek yang tidak aktif, perlu 'npm install' ulang!)" "clean_node_modules" "Direktori node_modules dihapus." "Gagal menghapus direktori node_modules."
    confirm_and_execute "📝 Bersihkan ekstensi VS Code (~/.vscode/extensions)? (PERINGATAN: Akan menghapus semua ekstensi, perlu instal ulang!)" "clean_vscode_extensions" "Ekstensi VS Code dibersihkan." "Gagal membersihkan ekstensi VS Code."
    confirm_and_execute "⏰ Hapus snapshot lokal Time Machine? (PERINGATAN: Ini bisa membebaskan banyak ruang, tetapi akan mempengaruhi kemampuan pemulihan Time Machine Anda!)" "clean_time_machine_local_snapshots" "Snapshot lokal Time Machine dihapus." "Gagal menghapus snapshot lokal Time Machine."
    log_message "INFO" "Pembersihan Level 3 selesai."
}


# --- Logika Utama Skrip ---

# Mengarahkan semua output ke file log jika FORCE_CLEAN diaktifkan untuk otomatisasi
if [[ "$FORCE_CLEAN" -eq 1 ]]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
    log_message "INFO" "--- Memulai skrip pembersihan otomatis (FORCE_CLEAN) ---"
fi

# Parsing argumen baris perintah
for arg in "$@"; do
    case "$arg" in
        --force)
            FORCE_CLEAN=1
            log_message "INFO" "Mode Pembersihan Paksa diaktifkan. Tidak ada prompt yang akan ditampilkan."
            ;;
        --dry-run)
            DRY_RUN=1
            log_message "INFO" "Mode Dry Run diaktifkan. Tidak ada file yang akan dihapus."
            ;;
        *)
            if [[ "$arg" =~ ^[0-9]+$ ]]; then
                SIZE="$arg"
                log_message "INFO" "Mengatur ambang batas ukuran file ke ${SIZE}MB."
            else
                log_message "WARN" "Argumen tidak dikenal: $arg. Mengabaikan."
            fi
            ;;
    esac
done

# Sesuaikan PROJECTS_DIR jika tidak ada
if [ ! -d "$PROJECTS_DIR" ]; then
    PROJECTS_DIR="$HOME"
    log_message "WARN" "Menggunakan $HOME sebagai direktori proyek karena $HOME/Documents/projects tidak ada."
fi

echo "--- Selamat datang di Asisten Pembersihan Disk Cerdas untuk macOS ---"
echo "Versi: 2.0 (AI-Enhanced)"
echo "Tanggal: $(date "+%Y-%m-%d %H:%M:%S")"
echo "Mode: $(if [[ "$FORCE_CLEAN" -eq 1 ]]; then echo "Otomatis"; elif [[ "$DRY_RUN" -eq 1 ]]; then echo "Dry Run"; else echo "Interaktif"; fi)"
echo "Log: $LOG_FILE"
echo ""

# --- FASE ANALISIS CERDAS ---
echo "=== FASE 1: ANALISIS SISTEM CERDAS ==="
echo "Menganalisis penggunaan disk dan mengidentifikasi kandidat pembersihan..."

analyze_projects_for_recommendations
detect_old_files

echo -e "\n--- Ikhtisar Sistem Saat Ini ---"
echo "--- Memindai file lebih besar dari ${SIZE}MB ---"
sudo find "${SEARCH_DIRS[@]}" -type f -size +${SIZE}M -exec ls -lh {} \; 2>/dev/null | head -20
echo -e "\n--- Menganalisis ukuran folder di /Users ---"
sudo du -sh /Users/* 2>/dev/null | sort -hr
echo -e "\n--- Ringkasan Penggunaan Disk ---"
df -h
echo -e "\n--- Ringkasan Penggunaan Memori (RAM) ---"
echo "Statistik Memori (via vm_stat):"
vm_stat | grep -E "Pages free|Pages active|Pages inactive|Pages wired down|Pageins|Pageouts"
echo -e "\n5 Proses Teratas berdasarkan penggunaan memori (via top):"
top -l 1 -o mem -n 5 | head -n 15 | tail -n 5

echo -e "\n=== Ringkasan Cache dan File Sementara (Sebelum Pembersihan) ==="
# Hitung ukuran cache
USER_CACHE_SIZE=$(calc_dir_size ~/Library/Caches)
SYSTEM_CACHE_SIZE=$(calc_dir_size /Library/Caches)
APP_DOWNLOAD_CACHE_SIZE=$(calc_dir_size /private/var/folders/*/*/C/com.apple.appstore) # Approximate
PUPPETEER_CACHE_SIZE=$(calc_dir_size ~/.cache/puppeteer)
NPM_CACHE_SIZE=$(calc_dir_size ~/.npm)
BUN_CACHE_SIZE=$(calc_dir_size ~/.bun/install/cache)
BREW_CACHE_SIZE=$(calc_dir_size ~/Library/Caches/Homebrew)
BREW_CELLAR_CACHE_SIZE=$(calc_dir_size "$(brew --cache)" 2>/dev/null)
GRADLE_CACHE_SIZE=$(calc_dir_size ~/.gradle/caches)
NPX_CACHE_SIZE=$(calc_dir_size ~/.npm/_npx)
VSCODE_CACHE_SIZE=$(calc_dir_size ~/Library/Caches/com.microsoft.VSCode)
VSCODE_EXT_SIZE=$(calc_dir_size ~/.vscode/extensions)
CHROME_CACHE_SIZE=$(calc_dir_size ~/Library/Caches/Google/Chrome)
SAFARI_CACHE_SIZE=$(calc_dir_size ~/Library/Caches/com.apple.Safari)
QUICKLOOK_CACHE_SIZE=$(calc_dir_size ~/Library/Caches/com.apple.QuickLook.thumbnailcache)
SPOTLIGHT_CACHE_SIZE=$(calc_dir_size /.Spotlight-V100)
XCODE_DERIVED_DATA_SIZE=$(calc_dir_size ~/Library/Developer/Xcode/DerivedData)
XCODE_ARCHIVES_SIZE=$(calc_dir_size ~/Library/Developer/Xcode/Archives)
XCODE_IOS_DEVICE_SUPPORT_SIZE=$(calc_dir_size ~/Library/Developer/Xcode/iOS\ DeviceSupport)
XCODE_SIMULATOR_SIZE=$(calc_dir_size ~/Library/Developer/Xcode/UserData/Previews/Simulator\ Devices)
YARN_CACHE_SIZE=$(calc_pattern_size "*yarn/cache" "-type d")
NEXT_CACHE_SIZE=$(calc_pattern_size ".next/cache" "-type d")
NEXT_WEBPACK_SIZE=$(calc_pattern_size ".next/cache/webpack" "-type d")
NODE_MODULES_SIZE=$(calc_pattern_size "node_modules" "-type d")
NEXT_SWC_SIZE=$(calc_pattern_size "next-swc.darwin-arm64.node" "-type f")
BUN_NEXT_CACHE_SIZE=$(calc_pattern_size ".bun-cache" "-type d")
TEMP_BUILD_SIZE=$(calc_pattern_size "*.tmp" "*.temp" "dist" "build")
DS_STORE_SIZE=$(calc_pattern_size ".DS_Store" "-type f")
if command -v docker >/dev/null 2>&1; then DOCKER_SIZE=$(docker system df --format '{{.Total}}' 2>/dev/null || echo "0B"); else DOCKER_SIZE="Docker not installed"; fi
SYSTEM_LOG_SIZE=$(calc_dir_size /private/var/log)
USER_LOG_SIZE=$(calc_dir_size ~/Library/Logs)
CRASH_REPORT_SIZE=$(calc_dir_size ~/Library/Logs/DiagnosticReports)
TRASH_SIZE=$(calc_dir_size ~/.Trash)
DOWNLOADS_SIZE=$(calc_dir_size ~/Downloads)
DMG_PKG_SIZE=$(calc_pattern_size "*.dmg" "*.pkg")
FONT_CACHE_SIZE=$(calc_dir_size /Library/Caches/com.apple.ATS)
SAVED_APP_STATE_SIZE=$(calc_dir_size ~/Library/Saved\ Application\ State)
APPLICATION_SUPPORT_CRASHREPORTER_SIZE=$(calc_dir_size ~/Library/Application\ Support/CrashReporter)

echo "📁 Cache Standar:"
echo "  Cache Pengguna (~/Library/Caches): ${USER_CACHE_SIZE:-0B}"
echo "  Cache Sistem (/Library/Caches): ${SYSTEM_CACHE_SIZE:-0B}"
echo "  Cache Unduhan Aplikasi/Sistem: ${APP_DOWNLOAD_CACHE_SIZE:-0B}"
echo "  Cache Chrome: ${CHROME_CACHE_SIZE:-0B}"
echo "  Cache Safari: ${SAFARI_CACHE_SIZE:-0B}"
echo "  Thumbnail QuickLook: ${QUICKLOOK_CACHE_SIZE:-0B}"
echo "  Cache Indeks Spotlight: ${SPOTLIGHT_CACHE_SIZE:-0B}"
echo "  Cache Font: ${FONT_CACHE_SIZE:-0B}"
echo ""
echo "🔧 Cache Pengembangan:"
echo "  Cache npm (~/.npm): ${NPM_CACHE_SIZE:-0B}"
echo "  Cache NPX (~/.npm/_npx): ${NPX_CACHE_SIZE:-0B}"
echo "  Cache Yarn: ${YARN_CACHE_SIZE:-0B}"
echo "  Cache instalasi Bun (~/.bun/install/cache): ${BUN_CACHE_SIZE:-0B}"
echo "  Cache Puppeteer: ${PUPPETEER_CACHE_SIZE:-0B}"
echo "  Cache Homebrew: ${BREW_CACHE_SIZE:-0B}"
echo "  Cache Cellar Homebrew (unduhan): ${BREW_CELLAR_CACHE_SIZE:-0B}"
echo "  Cache Gradle (~/.gradle/caches): ${GRADLE_CACHE_SIZE:-0B}"
echo "  Cache VS Code: ${VSCODE_CACHE_SIZE:-0B}"
echo "  Ekstensi VS Code: ${VSCODE_EXT_SIZE:-0B}"
echo "  Xcode DerivedData: ${XCODE_DERIVED_DATA_SIZE:-0B}"
echo "  Xcode Archives: ${XCODE_ARCHIVES_SIZE:-0B}"
echo "  Dukungan Perangkat iOS Xcode: ${XCODE_IOS_DEVICE_SUPPORT_SIZE:-0B}"
echo "  Simulator Xcode (Data Pratinjau): ${XCODE_SIMULATOR_SIZE:-0B}"
echo ""
echo "⚛️ Terkait Next.js:"
echo "  Cache Next.js (.next/cache): ${NEXT_CACHE_SIZE:-0B}"
echo "  Cache Webpack Next.js (.next/cache/webpack): ${NEXT_WEBPACK_SIZE:-0B}"
echo "  Biner SWC Next.js (next-swc.darwin-arm64.node): ${NEXT_SWC_SIZE:-0B}"
echo "  Cache Bun Next.js (.bun-cache): ${BUN_NEXT_CACHE_SIZE:-0B}"
echo ""
echo "📦 File Proyek & Sementara:"
echo "  Direktori node_modules: ${NODE_MODULES_SIZE:-0B}"
echo "  Direktori dist: ${DIST_SIZE:-0B}"
echo "  Direktori build: ${BUILD_SIZE:-0B}"
echo "  File sementara/lain-lain (*.tmp, .DS_Store, dll.): ${TEMP_BUILD_SIZE:-0B} + ${DS_STORE_SIZE:-0B}"
echo ""
echo "🐳 Kontainer & Sistem:"
echo "  Docker (kontainer, image, volume): ${DOCKER_SIZE:-0B}"
echo "  Log Sistem (/private/var/log): ${SYSTEM_LOG_SIZE:-0B}"
echo "  Log Pengguna (~/Library/Logs): ${USER_LOG_SIZE:-0B}"
echo "  Laporan Crash: ${CRASH_REPORT_SIZE:-0B}"
echo "  Sampah (~/.Trash): ${TRASH_SIZE:-0B}"
echo "  Unduhan (~/Downloads): ${DOWNLOADS_SIZE:-0B}"
echo "  File Installer DMG/PKG: ${DMG_PKG_SIZE:-0B}"
echo ""
echo "🗑️ Sampah Perpustakaan Pengguna:"
echo "  Saved Application State: ${SAVED_APP_STATE_SIZE:-0B}"
echo "  Application Support (CrashReporter): ${APPLICATION_SUPPORT_CRASHREPORTER_SIZE:-0B}"

# --- FASE PEMBERSIHAN ---
echo -e "\n=== FASE 2: PEMBERSIHAN BERTINGKAT ==="

if [[ "$FORCE_CLEAN" -eq 1 ]]; then
    log_message "INFO" "Mode Otomatis diaktifkan. Melakukan pembersihan Level 1, 2, dan 3 secara paksa."
    clean_level_1_safe
    clean_level_2_aggressive
    clean_level_3_risky # Tetap berhati-hati dengan Level 3, walaupun dipaksa.
elif [[ "$DRY_RUN" -eq 1 ]]; then
    log_message "INFO" "Mode Dry Run diaktifkan. Mensimulasikan pembersihan Level 1, 2, dan 3."
    clean_level_1_safe
    clean_level_2_aggressive
    clean_level_3_risky
else
    # Interaktif: Biarkan pengguna memilih level pembersihan
    echo -e "\nPilih Level Pembersihan Anda:"
    echo "1. Pembersihan Aman & Umum (Direkomendasikan, tidak mengganggu fungsionalitas)"
    echo "2. Pembersihan Agresif (Pengembangan & Kontainer, mungkin butuh regenerasi)"
    echo "3. Pembersihan Berisiko (Menghapus data yang memakan waktu regenerasi, perlu instal ulang!)"
    echo "4. Semua Level (1, 2, dan 3)"
    echo "0. Keluar"
    read -p "Masukkan pilihan Anda (1-4, default: 1): " clean_level

    case "$clean_level" in
        1|"") clean_level_1_safe ;;
        2) clean_level_2_aggressive ;;
        3) clean_level_3_risky ;;
        4)
            clean_level_1_safe
            clean_level_2_aggressive
            clean_level_3_risky
            ;;
        0) log_message "INFO" "Pembersihan dibatalkan oleh pengguna."; exit 0 ;;
        *) log_message "WARN" "Pilihan tidak valid. Melanjutkan dengan Pembersihan Aman (Level 1)."; clean_level_1_safe ;;
    esac
fi


# Analisis disk interaktif (hanya jika tidak dipaksa bersih dan bukan dry run)
echo -e "\n--- FASE 3: ANALISIS DISK INTERAKTIF (OPSIONAL) ---"
if [[ "$FORCE_CLEAN" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
    read -p "🔍 Jalankan ncdu untuk analisis penggunaan disk interaktif yang mendalam? (y/N): " ncdu_confirm
    if [[ "$ncdu_confirm" =~ ^[Yy]$ ]]; then
        if command -v ncdu >/dev/null 2>&1; then
            echo "Pilih direktori untuk dianalisis (tekan 'd' untuk menghapus, 'q' untuk keluar):"
            echo "1) Direktori Home ($HOME)"
            echo "2) Dokumen ($HOME/Documents)"
            echo "3) Proyek ($PROJECTS_DIR)"
            echo "4) Direktori Root (/)"
            read -p "Masukkan pilihan (1-4, default: 1): " ncdu_choice

            case $ncdu_choice in
                1|"") ncdu_dir="$HOME" ;;
                2) ncdu_dir="$HOME/Documents" ;;
                3) ncdu_dir="$PROJECTS_DIR" ;;
                4) ncdu_dir="/" ;;
            esac

            log_message "INFO" "Menjalankan ncdu di $ncdu_dir..."
            if [ "$ncdu_dir" = "/" ]; then
                sudo ncdu "$ncdu_dir"
            else
                ncdu "$ncdu_dir"
            fi
        else
            log_message "WARN" "❌ ncdu tidak terinstal. Instal dengan: brew install ncdu"
        fi
    else
        log_message "INFO" "❌ Analisis ncdu dilewati."
    fi
fi

# --- RINGKASAN AKHIR & PELAPORAN ---
echo -e "\n--- 🎉 RINGKASAN PEMBERSIHAN AKHIR 🎉 ---"
total_freed_mb=$(awk '{s+=$1} END {print s}' "$FREED_SPACE_REPORT" 2>/dev/null || echo 0)
echo "Total ruang disk yang berhasil dibebaskan: **${total_freed_mb}MB**"
echo ""

log_message "INFO" "✅ Skrip selesai dengan sukses!"

echo "💡 Apa yang telah dibersihkan:"
echo "    • Cache standar (browser, sistem, alat pengembangan, Xcode, unduhan aplikasi, font)"
echo "    • Cache build dan file webpack Next.js"
echo "    • File biner SWC Next.js"
echo "    • Cache Bun untuk proyek Next.js"
echo "    • Ekstensi VS Code (opsional, Level 3)"
echo "    • Direktori build, dist, dan sementara umum (.tmp, .temp, .DS_Store, dll.)"
echo "    • Opsional: node_modules, sumber daya Docker, log, sampah, unduhan lama, installer, symbolic link rusak, sampah Library pengguna, snapshot lokal Time Machine"
echo ""
echo "🔄 File yang dibuat ulang secara otomatis:"
echo "    • Semua cache akan dibangun kembali secara otomatis saat dibutuhkan"
echo "    • SWC binaries akan diunduh ulang pada build Next.js berikutnya"
echo "    • Direktori build akan dibuat ulang pada build berikutnya"
echo ""
echo "⚠️ Ingat:"
echo "    • Jalankan 'npm install' atau 'bun install' di proyek tempat node_modules dihapus (jika dihapus)"
echo "    • Build Next.js pertama setelah pembersihan mungkin memakan waktu lebih lama karena pembuatan ulang cache"
echo "    • Cadangkan proyek penting sebelum menjalankan skrip ini"
echo "    • Jika Anda menghapus ekstensi VS Code, Anda perlu menginstalnya kembali."
echo ""
echo "📁 Direktori pencarian yang digunakan:"
for dir in "${SEARCH_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "  ✅ $dir"
    else
        echo "  ❌ $dir (tidak ditemukan)"
    fi
done

if [[ "$FORCE_CLEAN" -eq 1 ]]; then
    log_message "INFO" "--- Skrip pembersihan otomatis selesai ---"
fi

rm -f "$FREED_SPACE_REPORT" # Hapus file laporan sementara
