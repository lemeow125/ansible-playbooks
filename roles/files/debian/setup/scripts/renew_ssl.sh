#!/bin/bash

directory="/root/scripts/acme_scripts"

# Execute all .sh files in the directory
for script in "$directory"/*.sh; do
   echo "--Executing $script--"
   bash "$script"
done