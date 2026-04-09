#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Load configuration ---
if [[ -f "$SCRIPT_DIR/config.env" ]]; then
    source "$SCRIPT_DIR/config.env"
else
    echo "ERROR: config.env not found in $SCRIPT_DIR" >&2
    exit 1
fi

# --- Notification helper (gracefully handles missing ntfy config) ---
notify_error() {
    local title="$1"
    local message="$2"
    if [[ -n "${ntfy_server:-}" && -n "${ntfy_topic:-}" ]]; then
        curl -s -H "Title: [$device_name] $title" -H "Priority: high" \
            -d "$message" "$ntfy_server/$ntfy_topic" >/dev/null 2>&1 || true
    fi
}

# --- Validate ntfy configuration (non-fatal warning) ---
if [[ -z "${ntfy_server:-}" || -z "${ntfy_topic:-}" ]]; then
    echo "WARNING: ntfy_server or ntfy_topic not set. Notifications disabled." >&2
fi

# --- Validate other essential variables ---
if [[ -z "${device_name:-}" ]]; then
    echo "ERROR: device_name not set" >&2
    notify_error "Config Error" "device_name not set in config.env"
    exit 1
fi

if [[ -z "${parallel_backups:-}" ]]; then
    echo "ERROR: parallel_backups not set (true/false)" >&2
    notify_error "Config Error" "parallel_backups not set in config.env"
    exit 1
fi

# Validate mount_points associative array
if ! declare -p mount_points &>/dev/null || [[ ${#mount_points[@]} -eq 0 ]]; then
    echo "ERROR: mount_points array is empty or not declared" >&2
    notify_error "Config Error" "mount_points missing or empty in config.env"
    exit 1
fi

# Borg environment
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

current_date=$(date "+%B %-d %Y %l:%M %p")
echo "Timestamp: $current_date"

# --- Mount verification (unchanged) ---
is_mounted() {
    local remote="$1"
    local local_path="$2"
    if ! findmnt --target "$local_path" --source "$remote" &>/dev/null; then
        echo "Error: $remote not mounted at $local_path"
        notify_error "Backup Error" "$remote not mounted at $local_path $(date)"
        return 1
    fi
    return 0
}

for remote in "${!mount_points[@]}"; do
    local_path="${mount_points[$remote]}"
    if ! is_mounted "$remote" "$local_path"; then
        exit 1
    fi
done

# --- Backup function (updated to use notify_error) ---
function backup() {
    [[ -z "$1" || -z "$2" ]] && {
        echo "Missing arguments!" >&2
        notify_error "Backup Error" "Missing arguments for backup function at $(date)"
        exit 1
    }

    local backup_name="$1"
    local source_dir="$2"
    shift 2
    local extras=("$@")

    for local_mount in "${mount_points[@]}"; do
        run_backup_job() {
            local repo_path="${local_mount}/${backup_name}"
            local stderr_file
            stderr_file=$(mktemp)
            if [[ ! -f "$stderr_file" ]]; then
                echo "ERROR: Failed to create temp file for stderr capture" >&2
                exit 1
            fi

            echo "Starting backups for '$backup_name' at $local_mount"

            if [[ ! -d "$repo_path" ]]; then
                echo "Initializing new repository: $repo_path"
                borg init --encryption=none "$repo_path" 2> >(tee "$stderr_file" >&2)
                if [[ $? -ne 0 ]]; then
                    echo "ERROR: borg init failed for $repo_path" >&2
                    error_content=$(cat "$stderr_file")
                    notify_error "Init failed for $backup_name on $local_mount" "$error_content"
                    rm -f "$stderr_file"
                    exit 1
                fi
            fi

            echo "Backing up $source_dir to $repo_path"
            borg create --stats --progress --compression lz4 "$repo_path"::"$current_date" \
                "$source_dir" "${extras[@]}" 2> >(tee "$stderr_file" >&2)
            if [[ $? -ne 0 ]]; then
                echo "ERROR: borg create failed for $repo_path" >&2
                error_content=$(cat "$stderr_file")
                notify_error "Create failed for $backup_name on $local_mount" "$error_content"
                rm -f "$stderr_file"
                exit 1
            fi

            echo "Cleaning old backups at $repo_path"
            borg prune --stats "$repo_path" -d 6 2> >(tee "$stderr_file" >&2)
            if [[ $? -ne 0 ]]; then
                echo "ERROR: borg prune failed for $repo_path" >&2
                error_content=$(cat "$stderr_file")
                notify_error "Prune failed for $backup_name on $local_mount" "$error_content"
                rm -f "$stderr_file"
                exit 1
            fi

            borg compact "$repo_path" 2> >(tee "$stderr_file" >&2)
            if [[ $? -ne 0 ]]; then
                echo "ERROR: borg compact failed for $repo_path" >&2
                error_content=$(cat "$stderr_file")
                notify_error "Compact failed for $backup_name on $local_mount" "$error_content"
                rm -f "$stderr_file"
                exit 1
            fi

            rm -f "$stderr_file"
            echo "Backup for '$backup_name' completed at $local_mount"
        }

        if [[ "$parallel_backups" == "true" ]]; then
            run_backup_job &
        else
            run_backup_job
        fi
    done

    if [[ "$parallel_backups" == "true" ]]; then
        wait
    fi
}

# --- Load job definitions ---
if [[ -f "$SCRIPT_DIR/jobs.conf" ]]; then
    source "$SCRIPT_DIR/jobs.conf"
else
    echo "WARNING: jobs.conf not found – no backups will run." >&2
    notify_error "Config Warning" "jobs.conf missing – no backups executed"
fi