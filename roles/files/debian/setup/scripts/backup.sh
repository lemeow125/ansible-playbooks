#!/bin/bash

current_date=$(date "+%B %-d %Y%l:%M %p")

# Export Borg environment variables
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

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

# Backup function
function backup() {
    [[ -z "$1" || -z "$2" ]] && { echo "Missing arguments!"; exit 1; }

    local backup_name="$1"
    local source_dir="$2"
    shift 2
    local extras=("$@")
    
    # Iterate through all mount points
    for local_mount in "${mount_points[@]}"; do
        local repo_path="${local_mount}/${backup_name}"
        
        echo "Starting backups for '$backup_name' at $local_mount"
        
        # Initialize repository if missing
        if [[ ! -d "$repo_path" ]]; then
            echo "Initializing new repository: $repo_path"
            borg init --encryption=none "$repo_path"
        fi

        # Perform backup
        echo "Backing up $source_dir to $repo_path"
        borg create --stats --progress --compression lz4 "$repo_path"::"$current_date" \
            "$source_dir" "${extras[@]}"
        
        # Cleanup old backups
        echo "Cleaning old backups at $repo_path"
        borg prune --stats "$repo_path" -d 6
        borg compact "$repo_path"
        
        echo "Backup for '$backup_name' completed at $local_mount"
    done
}


## Docker Projects

## Root Docker Projects Directory
docker_projects="/mnt/nvme/files/docker projects"

# Sample Entry
# backup "sample" "$docker_projects/sample_project" '--exclude "*.tmp"'

## Non-Docker Directories

# Bash Scripts
backup "bash-scripts" "/root/scripts"

# ACME
backup "acme" "/root/.acme.sh" '--exclude "*.tmp"'

# Crontab
backup "cron" "/var/spool/cron/crontabs"

# Nginx
backup "nginx" "/etc/nginx" '--exclude "*.tmp"'

# Syncthing
backup "syncthing" "/root/.config/syncthing" '--exclude "*.tmp"'

# Samba
backup "samba" "/etc/samba"

# Samba Credentials
backup "samba_credentials" "/root/.samba"