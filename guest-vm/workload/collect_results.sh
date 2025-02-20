#!/bin/bash

set -e

HOST=localhost
PORT=22
USER=ubuntu

SCRIPT_DIR=$(dirname $0)
SSH_HOSTS_FILE=$(realpath $SCRIPT_DIR/../../build/known_hosts)
CONFIG_FILE=$(realpath $SCRIPT_DIR/conf.json)


contains_colon() {
  local str="$1"
  [[ "$str" == *:* ]]
}

extract_dir() {
  before_colon=$(echo "$str" | awk -F':' '{print $1}') # Get directory path before ':'
  echo "$(basename "$before_colon")"  # Extract last directory name
}

usage() {
  echo "$0 [options]"
  echo " -host <string>          hostname or IP address of the VM (default: $HOST)"
  echo " -port <int>             SSH port of the VM (default: $PORT)"
  echo " -user <string>          VM user to login to (default: $USER)"
  echo " -config <string>        Configuration file to collect results (default: $CONFIG_FILE)"
  exit
}

while [ -n "$1" ]; do
	case "$1" in
		-host) HOST="$2"
			shift
			;;
		-port) PORT="$2"
			shift
			;;
		-user) USER="$2"
			shift
			;;
        -config) CONFIG_FILE="$2"
			shift
			;;
		*) 		usage
				;;
	esac

	shift
done

# Parsing configuration file to get local directory to store results
echo "Parsing $CONFIG_FILE to get local directory to store results.."
local_result_folder=$(jq -r '.local_result_folder' "$CONFIG_FILE")

# Copying back results
echo "Copying docker results into $local_result_folder.."
# Check if the directory exists
if [ -d "$local_result_folder" ]; then
    read -p "Directory $local_result_folder already exists. Do you want to overwrite? (y/n): " choice
    if [[ "$choice" != "y" ]]; then
        echo "Copy operation aborted."
        exit 1
    else
        rm -r "$local_result_folder"
    fi
fi

# Perform the copy
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile="$SSH_HOSTS_FILE" -P "$PORT" -r "$USER@$HOST:/home/$USER/workload_results/*" "$local_result_folder"

# Copy also all the user outputs that were inputs
mapfile -t outputs  < <(jq -r '.outputs[]' "$CONFIG_FILE")
for output in ${outputs[@]}; do
    if contains_colon "$output"; then
      dir=$(extract_dir "$output")
      scp -o StrictHostKeyChecking=no -o UserKnownHostsFile="$SSH_HOSTS_FILE" -P "$PORT" -r "$USER@$HOST:/home/$USER/workload_data/$dir" "$local_result_folder"
    fi
done

echo "Copy operation completed."
