#!/bin/bash

# ===== Configuration =====
# List of top-level directories that contain Borg repositories (may be nested)
BACKUP_ROOTS=(
    # REPLACE-ME
)

DEVICE_NAME="REPLACE-ME"                         # identifier for this host
NTFY_SERVER="https://ntfy.06222001.xyz"
NTFY_TOPIC="REPLACE-ME"

# Suppress Borg warnings about unencrypted / relocated repos
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

# ===== Functions =====
# Send a notification via ntfy
# Usage: send_ntfy "Title" "Message body"
send_ntfy() {
    local title="$1"
    local message="$2"

    # Truncate message if too long (ntfy has ~4k character limit)
    if [ ${#message} -gt 4000 ]; then
        message="${message:0:4000}\n… (truncated)"
    fi

    # Add device name to message for context
    message="Device: $DEVICE_NAME\n\n$message"

    curl -s -H "Title: $title" \
         -H "Priority: high" \
         -d "$message" \
         "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null
}

# ===== Main script =====
for root in "${BACKUP_ROOTS[@]}"; do
    # Check if root exists
    if [ ! -d "$root" ]; then
        echo "WARNING: Backup root '$root' does not exist – skipping." >&2
        send_ntfy "🚨 Backup Root Missing" "The configured backup root directory does not exist:\n$root"
        continue
    fi

    echo "--- Searching for Borg repositories under $root ---"

    # Find all directories that contain a 'config' file (Borg repo marker)
    # Use -printf "%h\0" to output the parent directory with null separator
    found_repos=()
    while IFS= read -r -d '' repo; do
        found_repos+=("$repo")
    done < <(find "$root" -type f -name config -printf "%h\0" 2>/dev/null | sort -uz)

    if [ ${#found_repos[@]} -eq 0 ]; then
        echo "No Borg repositories found under $root – skipping."
        continue
    fi

    echo "Found ${#found_repos[@]} repository(ies)."
    for repo in "${found_repos[@]}"; do
        # Get the relative path for display (relative to root)
        rel_path="${repo#$root/}"
        echo "=== Checking $rel_path (full: $repo) ==="

        # Run borg check, capture all output
        output=$(borg check "$repo" 2>&1)
        exit_code=$?

        if [ $exit_code -ne 0 ]; then
            echo "❌ borg check FAILED for $rel_path (exit code $exit_code)"
            send_ntfy "🚨 Borg Check Failure" \
                "Repository: $rel_path\nPath: $repo\n\nError details:\n$output"
        else
            echo "✅ borg check succeeded for $rel_path"
        fi
    done
done