#!/bin/bash

current_date=$(date "+%B %-d %Y%l:%M %p")

# Export Borg environment variables
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes
export device_name="CHANGE-ME"
export ntfy_server="https://ntfy.06222001.xyz"
export ntfy_topic="CHANGE-ME"

echo "Timestamp: $current_date"

# ----------------------------------------------------------------------
# Destination registry – friendly name → local_path|remote_source
# ----------------------------------------------------------------------
declare -A DESTINATIONS=(
    [backups_a]="/mnt/backups_a|//10.0.10.169/pc-2"
    [backups_b]="/mnt/backups_b|//10.0.10.115/pc-2"
)

# ----------------------------------------------------------------------
# Verify all defined destinations are mounted
# ----------------------------------------------------------------------
check_mounts() {
    local name local_path remote
    for name in "${!DESTINATIONS[@]}"; do
        IFS='|' read -r local_path remote <<< "${DESTINATIONS[$name]}"
        if ! findmnt --target "$local_path" --source "$remote" &>/dev/null; then
            echo "Error: $name ($remote) not mounted at $local_path"
            curl -s -H "Title: [$device_name] Backup Error" -H "Priority: high" \
                -d "$name ($remote) not mounted at $local_path $(date)" \
                "$ntfy_server/$ntfy_topic" >/dev/null 2>&1
            exit 1
        fi
    done
    echo "All destinations verified."
}
check_mounts

# ----------------------------------------------------------------------
# Backup function – now expects --targets list
# ----------------------------------------------------------------------
backup() {
    # Validate minimum arguments
    [[ $# -lt 2 ]] && {
        echo "ERROR: backup requires at least <name> <source> [--targets t1 t2 ...] [-- extras...]" >&2
        exit 1
    }

    local backup_name="$1"
    local source_dir="$2"
    shift 2

    local targets=()
    local extras=()

    # Parse remaining arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --targets)
                shift
                # Collect targets until next option or end
                while [[ $# -gt 0 && "$1" != "--" ]]; do
                    targets+=("$1")
                    shift
                done
                ;;
            --)
                shift
                extras=("$@")
                break
                ;;
            *)
                # If we hit something unexpected before --, it's an error
                echo "ERROR: Unexpected argument '$1' in backup call" >&2
                exit 1
                ;;
        esac
    done

    # Targets are now mandatory – no implicit “all destinations”
    if [[ ${#targets[@]} -eq 0 ]]; then
        echo "ERROR: backup '$backup_name' has no --targets specified" >&2
        exit 1
    fi

    # --- Run backup for each target in parallel ---
    for target in "${targets[@]}"; do
        # Validate target exists in DESTINATIONS
        if [[ -z "${DESTINATIONS[$target]}" ]]; then
            echo "ERROR: Unknown destination '$target' for backup '$backup_name'" >&2
            exit 1
        fi

        IFS='|' read -r local_mount _ <<< "${DESTINATIONS[$target]}"
        local repo_path="${local_mount}/${backup_name}"

        (
            local stderr_file
            stderr_file=$(mktemp)
            [[ ! -f "$stderr_file" ]] && {
                echo "ERROR: Failed to create temp file" >&2
                exit 1
            }

            echo "Starting backup '$backup_name' → $target ($local_mount)"

            # Initialize repository if missing
            if [[ ! -d "$repo_path" ]]; then
                echo "Initializing repository: $repo_path"
                borg init --encryption=none "$repo_path" 2> >(tee "$stderr_file" >&2)
                if [[ $? -ne 0 ]]; then
                    echo "ERROR: borg init failed for $repo_path" >&2
                    error_content=$(cat "$stderr_file")
                    curl -s -H "Title: [$device_name] Init failed for $backup_name on $target" \
                         -H "Priority: high" -d "$error_content" \
                         "$ntfy_server/$ntfy_topic" >/dev/null 2>&1
                    rm -f "$stderr_file"
                    exit 1
                fi
            fi

            # Perform backup
            echo "Backing up $source_dir to $repo_path"
            borg create --stats --progress --compression lz4 \
                "$repo_path"::"$current_date" \
                "$source_dir" "${extras[@]}" 2> >(tee "$stderr_file" >&2)
            if [[ $? -ne 0 ]]; then
                echo "ERROR: borg create failed for $repo_path" >&2
                error_content=$(cat "$stderr_file")
                curl -s -H "Title: [$device_name] Create failed for $backup_name on $target" \
                     -H "Priority: high" -d "$error_content" \
                     "$ntfy_server/$ntfy_topic" >/dev/null 2>&1
                rm -f "$stderr_file"
                exit 1
            fi

            # Prune old backups
            echo "Cleaning old backups at $repo_path"
            borg prune --stats "$repo_path" -d 3 2> >(tee "$stderr_file" >&2)
            if [[ $? -ne 0 ]]; then
                echo "ERROR: borg prune failed for $repo_path" >&2
                error_content=$(cat "$stderr_file")
                curl -s -H "Title: [$device_name] Prune failed for $backup_name on $target" \
                     -H "Priority: high" -d "$error_content" \
                     "$ntfy_server/$ntfy_topic" >/dev/null 2>&1
                rm -f "$stderr_file"
                exit 1
            fi

            # Compact repository
            borg compact "$repo_path" 2> >(tee "$stderr_file" >&2)
            if [[ $? -ne 0 ]]; then
                echo "ERROR: borg compact failed for $repo_path" >&2
                error_content=$(cat "$stderr_file")
                curl -s -H "Title: [$device_name] Compact failed for $backup_name on $target" \
                     -H "Priority: high" -d "$error_content" \
                     "$ntfy_server/$ntfy_topic" >/dev/null 2>&1
                rm -f "$stderr_file"
                exit 1
            fi

            rm -f "$stderr_file"
            echo "Backup '$backup_name' to $target completed."
        ) &
    done

    wait
}

# ----------------------------------------------------------------------
# Backup job definitions
# ----------------------------------------------------------------------

docker_projects="/mnt/nvme/files/docker projects"

# --- Docker projects ---
# backup "sample" "$docker_projects/sample" --targets backups_a backups_b

# --- Non-docker directories ---
backup "bash-scripts" "/root/scripts" --targets backups_a backups_b
backup "acme" "/root/.acme.sh" --targets backups_a backups_b
backup "cron" "/var/spool/cron/crontabs" --targets backups_a backups_b
backup "nginx" "/etc/nginx" --targets backups_a backups_b
backup "syncthing" "/root/.config/syncthing" --targets backups_a backups_b
backup "samba" "/etc/samba" --targets backups_a backups_b
backup "samba_credentials" "/root/.samba" --targets backups_a backups_b