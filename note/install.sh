#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="note"
SCRIPT_URL="https://raw.githubusercontent.com/bipproduction/sh/refs/heads/main/note/note.sh"

mkdir -p "$INSTALL_DIR"
curl -fsSL "$SCRIPT_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo '⚠️  Tambahkan baris berikut ke ~/.bashrc atau ~/.zshrc:'
    echo 'export PATH="$HOME/.local/bin:$PATH"'
fi

echo "✅ Installed as $INSTALL_DIR/$SCRIPT_NAME"
