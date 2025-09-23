#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="$HOME/.note.conf"
URL="https://cld-dkr-makuro-seafile.wibudev.com/api2"

# --- Check dependencies ---
for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Missing dependency: $cmd (please install it)"
        exit 1
    fi
done

# --- Parse command ---
cmd="${1:-help}"

# --- Handle config tanpa load token/repo ---
if [ "$cmd" == "config" ]; then
    if [ ! -f "$CONFIG_FILE" ]; then
        {
            echo "TOKEN="
            echo "REPO="
        } > "$CONFIG_FILE"
    fi
    ${EDITOR:-vim} "$CONFIG_FILE"
    exit 0
fi

# --- Load config untuk command lain ---
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
else
    echo "⚠️  Config file not found at $CONFIG_FILE"
    echo "Run: note config   to create/edit it."
    exit 1
fi

if [ -z "${TOKEN:-}" ] || [ -z "${REPO:-}" ]; then
    echo "❌ Config invalid. Please set TOKEN=... and REPO=... inside $CONFIG_FILE"
    exit 1
fi

# --- Commands ---
case "$cmd" in
    ls)
        curl -s -H "Authorization: Token $TOKEN" \
          "$URL/$REPO/dir/?p=/" \
        | jq -r '.[].name'
        ;;
    cat)
        FILE_NAME=${2:?Usage: note cat <file>}
        DOWNLOAD_URL=$(curl -s -H "Authorization: Token $TOKEN" \
          "$URL/$REPO/file/?p=/$FILE_NAME" | jq -r '.')
        curl -s -H "Authorization: Token $TOKEN" "$DOWNLOAD_URL"
        ;;
    cp)
        LOCAL_FILE=${2:?Usage: note cp <local_file> [remote_file]}
        if [ ! -f "$LOCAL_FILE" ]; then
            echo "❌ File not found: $LOCAL_FILE"
            exit 1
        fi
        REMOTE_FILE=${3:-$(basename "$LOCAL_FILE")}
        UPLOAD_URL=$(curl -s -H "Authorization: Token $TOKEN" \
          "$URL/$REPO/upload-link/?p=/" | jq -r '.')
        curl -s -H "Authorization: Token $TOKEN" \
          -F "file=@$LOCAL_FILE" \
          -F "filename=$REMOTE_FILE" \
          -F "parent_dir=/" \
          "$UPLOAD_URL" >/dev/null
        echo "✅ Uploaded $LOCAL_FILE → $REMOTE_FILE"
        ;;
    rm)
        FILE_NAME=${2:?Usage: note rm <remote_file>}
        curl -s -X DELETE -H "Authorization: Token $TOKEN" \
          "$URL/$REPO/file/?p=/$FILE_NAME" >/dev/null
        echo "🗑️  Removed $FILE_NAME"
        ;;
    mv)
        OLD_NAME=${2:?Usage: note mv <old_name> <new_name>}
        NEW_NAME=${3:?Usage: note mv <old_name> <new_name>}
        curl -s -X POST -H "Authorization: Token $TOKEN" \
          -d "operation=rename" \
          -d "newname=$NEW_NAME" \
          "$URL/$REPO/file/?p=/$OLD_NAME" >/dev/null
        echo "✏️  Renamed $OLD_NAME → $NEW_NAME"
        ;;
    get)
        REMOTE_FILE=${2:?Usage: note get <remote_file> [local_file]}
        LOCAL_FILE=${3:-$REMOTE_FILE}
        DOWNLOAD_URL=$(curl -s -H "Authorization: Token $TOKEN" \
          "$URL/$REPO/file/?p=/$REMOTE_FILE" | jq -r '.')
        curl -s -H "Authorization: Token $TOKEN" "$DOWNLOAD_URL" -o "$LOCAL_FILE"
        echo "⬇️  Downloaded $REMOTE_FILE → $LOCAL_FILE"
        ;;
    help|*)
        cat <<EOF
note - simple CLI for Seafile notes

Usage:
  note ls                      List files
  note cat <file>              Show file content
  note cp <local> [remote]     Upload file
  note rm <remote>             Remove file
  note mv <old> <new>          Rename/move file
  note get <remote> [local]    Download file
  note config                  Edit config (~/.note.conf)

Config (~/.note.conf):
  TOKEN=your_seafile_token
  REPO=repos/<repo-id>
EOF
        ;;
esac
