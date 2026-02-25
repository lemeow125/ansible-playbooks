#!/bin/bash

current_date=$(date "+%B %-d %Y%l:%M %p")

# Export Borg environment variables
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes
export device_name="$(hostname 2>/dev/null || echo CHANGE-ME)" # Use hostname, otherwise fall back to "CHANGE-ME"
export ntfy_server="https://ntfy.06222001.xyz"
export ntfy_topic="CHANGE-ME"

echo "Timestamp: $current_date"

# Define required mount points as key-value pairs (remote:local)
declare -A mount_points=(
    ["//10.0.10.169/pc-2"]="/mnt/backups_a"
    ["//10.0.10.115/pc-2"]="/mnt/backups_b"
)

# Function to check if a mount point is mounted
is_mounted() {
    local remote="$1"
    local local_path="$2"
    if ! findmnt --target "$local_path" --source "$remote" &>/dev/null; then
        echo "Error: $remote not mounted at $local_path"
        curl -s -H "Title: [$device_name] Backup Error" -H "Priority: high" \
            -d "$remote not mounted at $local_path $(date)" \
            "$ntfy_server/$ntfy_topic" >/dev/null 2>&1
        return 1
    fi
    return 0
}

# Verify all required mount points
for remote in "${!mount_points[@]}"; do
    local_path="${mount_points[$remote]}"
    if ! is_mounted "$remote" "$local_path"; then
        exit 1
    fi
done

function backup() {
    # Validate arguments BEFORE shifting
    [[ -z "$1" || -z "$2" ]] && {
        echo "Missing arguments!" >&2
        curl -s -H "Title: [$device_name] Backup Error" -H "Priority: high" \
            -d "Missing arguments for backup function at $(date)" \
            "$ntfy_server/$ntfy_topic" >/dev/null 2>&1
        exit 1
    }

    local backup_name="$1"
    local source_dir="$2"
    shift 2
    local extras=("$@")

    # Iterate through all mount points
    for local_mount in "${mount_points[@]}"; do
        local repo_path="${local_mount}/${backup_name}"
        local stderr_file

        # Create a unique temp file for stderr capture
        stderr_file=$(mktemp)
        if [[ ! -f "$stderr_file" ]]; then
            echo "ERROR: Failed to create temp file for stderr capture" >&2
            continue
        fi

        echo "Starting backups for '$backup_name' at $local_mount"

        # Initialize repository if missing
        if [[ ! -d "$repo_path" ]]; then
            echo "Initializing new repository: $repo_path"
            borg init --encryption=none "$repo_path" 2> >(tee "$stderr_file" >&2)
            if [[ $? -ne 0 ]]; then
                echo "ERROR: borg init failed for $repo_path" >&2
                error_content=$(cat "$stderr_file")
                curl -s -H "Title: [$device_name] Init failed for $backup_name on $local_mount" -H "Priority: high" \
                    -d "$error_content" \
                    "$ntfy_server/$ntfy_topic" >/dev/null 2>&1
                rm -f "$stderr_file"
                continue
            fi
        fi

        # Perform backup
        echo "Backing up $source_dir to $repo_path"
        borg create --stats --progress --compression lz4 "$repo_path"::"$current_date" \
            "$source_dir" "${extras[@]}" 2> >(tee "$stderr_file" >&2)
        if [[ $? -ne 0 ]]; then
            echo "ERROR: borg create failed for $repo_path" >&2
            error_content=$(cat "$stderr_file")
            curl -s -H "Title: [$device_name] Create failed for $backup_name on $local_mount" -H "Priority: high" \
                -d "$error_content" \
                "$ntfy_server/$ntfy_topic" >/dev/null 2>&1
            rm -f "$stderr_file"
            continue
        fi

        # Cleanup old backups
        echo "Cleaning old backups at $repo_path"
        borg prune --stats "$repo_path" -d 6 2> >(tee "$stderr_file" >&2)
        if [[ $? -ne 0 ]]; then
            echo "ERROR: borg prune failed for $repo_path" >&2
            error_content=$(cat "$stderr_file")
            curl -s -H "Title: [$device_name] Prune failed for $backup_name on $local_mount" -H "Priority: high" \
                -d "$error_content" \
                "$ntfy_server/$ntfy_topic" >/dev/null 2>&1
            rm -f "$stderr_file"
            continue
        fi

        borg compact "$repo_path" 2> >(tee "$stderr_file" >&2)
        if [[ $? -ne 0 ]]; then
            echo "ERROR: borg compact failed for $repo_path" >&2
            error_content=$(cat "$stderr_file")
            curl -s -H "Title: [$device_name] Compact failed for $backup_name on $local_mount" -H "Priority: high" \
                -d "$error_content" \
                "$ntfy_server/$ntfy_topic" >/dev/null 2>&1
            rm -f "$stderr_file"
            continue
        fi

        # All commands succeeded – clean up temp file
        rm -f "$stderr_file"
        echo "Backup for '$backup_name' completed at $local_mount"
    done
}

## Docker Projects

## Root Docker Projects Directory
docker_projects="/mnt/nvme/files/docker projects"

# Sample Entry
# backup "sample" "$docker_projects/sample_project"

## Non-Docker Directories

# Bash Scripts
backup "bash-scripts" "/root/scripts"

# ACME
backup "acme" "/root/.acme.sh"

# Crontab
backup "cron" "/var/spool/cron/crontabs"

# Nginx
backup "nginx" "/etc/nginx"

# Syncthing
backup "syncthing" "/root/.config/syncthing"

# Samba
backup "samba" "/etc/samba"

# Samba Credentials
backup "samba_credentials" "/root/.samba"