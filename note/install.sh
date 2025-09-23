#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="note"
SCRIPT_URL="https://raw.githubusercontent.com/bipproduction/sh/refs/heads/main/note/note.sh"

echo "🚀 Installing $SCRIPT_NAME..."

# Buat folder jika belum ada
mkdir -p "$INSTALL_DIR"

# Download script
curl -fsSL "$SCRIPT_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

# Cek PATH
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
    SHELL_RC=""
    if [ -f "$HOME/.bashrc" ]; then
        SHELL_RC="$HOME/.bashrc"
    elif [ -f "$HOME/.zshrc" ]; then
        SHELL_RC="$HOME/.zshrc"
    fi

    if [ -n "$SHELL_RC" ]; then
        echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$SHELL_RC"
        echo "⚠️  Added $INSTALL_DIR to PATH in $SHELL_RC"
    else
        echo "⚠️  Please add $INSTALL_DIR to your PATH manually."
    fi
fi

echo "✅ Installed as $INSTALL_DIR/$SCRIPT_NAME"
echo "💡 Restart terminal or run 'source ~/.bashrc' / 'source ~/.zshrc' to use the command."
