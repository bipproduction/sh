#!/bin/bash

# 1. Cek apakah .env file ada
ENV_FILE=".env"
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ File .env tidak ditemukan di $(pwd)"
  exit 1
fi

# 2. Baca .env dan ambil key-nya
echo "🔄 Membaca .env..."
ENV_KEYS=$(grep -v '^#' "$ENV_FILE" | grep '=' | cut -d '=' -f 1)

# 3. Siapkan isi file TypeScript .d.ts
OUTPUT_DIR="types"
OUTPUT_FILE="$OUTPUT_DIR/env.d.ts"

# Mulai isi file
CONTENT="declare namespace NodeJS {\n  interface ProcessEnv {\n"

# Loop tiap key dan append
while read -r key; do
  CONTENT+="    $key?: string;\n"
done <<< "$ENV_KEYS"

CONTENT+="  }\n}\n"

# 4. Buat output dir kalau belum ada
mkdir -p "$OUTPUT_DIR"

# 5. Tulis file
echo -e "$CONTENT" > "$OUTPUT_FILE"

echo "✅ Env types generated at: $OUTPUT_FILE"
