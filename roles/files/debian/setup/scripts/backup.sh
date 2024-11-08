#!/bin/bash

current_date=$(date "+%B %-d %Y%l:%M %p")

env BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
env BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

echo "Timestamp: $current_date"

# Check if the required mount point exists
if ! df -h | grep -q "^//255\.255\.255\.255/SAMBA-MOUNT.*\/mnt/backups$"; then
    echo "Error: Required mount point //255.255.255.255/SAMBA-MOUNT not found or not mounted at /mnt/backups."
    exit 1
fi

function backup() {
	# $1 - Backup Name
	# $2 - Directory
	# $3 - Extras
	
	if [ "$1" == "" ] || [ "$2" == "" ]; then
		echo "Missing arguments!"
		exit
	fi
	
	# Root backup directory
	root_directory="/mnt/backups/"

	echo "Starting backups for: $1"
	
	# Check if the backup directory exists
	if [ ! -d "$root_directory/$1" ]; then
		echo "Backup directory does not exist for $1. Initializing one"
		borg init --encryption=none "$root_directory/$1"
	else
		echo "Backup directory already exists for $1"
	fi
	
	borg create --stats --progress --compression lz4 "$root_directory/$1"::"$current_date" "$2" $3
	echo "Cleaning old backups"
	borg prune --stats "$root_directory/$1" -d 6
	borg compact "$root_directory/$1"
	echo "Backup for $1 finished"
}

## Docker Projects

## Root Docker Projects Directory
docker_projects="/mnt/nvme/files/docker projects/"

# Sample Entry
# backup "sample" "$docker_projects/sample_project" '--exclude "*.tmp" 

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