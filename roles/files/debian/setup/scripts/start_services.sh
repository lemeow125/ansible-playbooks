#!/bin/bash

## Docker Projects

# Root Docker Projects Directory
docker_projects="/mnt/nvme/files/docker projects"

# Sample Entry
# cd "$docker_projects/sample_project" && docker-compose down && docker-compose up -d

## Non-Docker Projects

# Syncthing
systemctl start syncthing@root.service


