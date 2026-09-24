#!/bin/bash
# Restore the latest archive from each repo in /mnt/external/backups_b
# to the root directory (/).

set -euo pipefail

export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

REPO_BASE="/mnt/external/backups_b"

echo "Scanning repositories in $REPO_BASE ..."
repos=$(find "$REPO_BASE" -maxdepth 1 -type d -exec test -f {}/config \; -print)
[[ -z "$repos" ]] && { echo "No repos found."; exit 1; }

for repo in $repos; do
    echo "--------------------------------------------------"
    echo "Repository: $repo"

    # Check readability
    if ! borg list "$repo" &>/dev/null; then
        echo "  ❌ Cannot read repo – skipping"
        continue
    fi

    # Get latest archive
    latest=$(borg list --short --last 1 "$repo" 2>&1)
    if [[ -z "$latest" ]]; then
        echo "  No archives – skipping"
        continue
    fi
    echo "  Latest archive: $latest"

    # Show top-level directories
    echo "  Top-level paths (first component):"
    borg list --format '{path}{NL}' "$repo::$latest" 2>/dev/null | \
        awk -F/ '{if (NF) print $1}' | sort -u | head -10

    echo "  Sample files (first 10):"
    borg list "$repo::$latest" 2>/dev/null | head -10

    read -p "  Restore $latest to / ? (y/N) " -n 1 -r; echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && continue

    # Perform extraction – cd to / so files go to the right place
    echo "  Extracting ... (this may overwrite existing files)"
    if (cd / && borg extract --strip-components=0 "$repo::$latest"); then
        echo "  ✅ Extraction completed."
    else
        echo "  ❌ Extraction failed – check logs above."
    fi
done

echo "All done."