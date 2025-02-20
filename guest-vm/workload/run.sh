#!/bin/bash

set -e

HOST=localhost
PORT=22
USER=ubuntu

SCRIPT_DIR=$(dirname $0)
SSH_HOSTS_FILE=$(realpath $SCRIPT_DIR/../../build/known_hosts)
DOCKER_FILE=$(realpath $SCRIPT_DIR/Dockerfile)
CONFIG_FILE=$(realpath $SCRIPT_DIR/conf.json)

starts_with_atat() {
  local str="$1"
  [[ "$str" == @@* ]]
}

contains_colon() {
  local str="$1"
  [[ "$str" == *:* ]]
}

ends_with_slash() {
  local str="$1"
  [[ "$str" == */ ]]
}

usage() {
  echo "$0 [options]"
  echo " -host <string>          hostname or IP address of the VM (default: $HOST)"
  echo " -port <int>             SSH port of the VM (default: $PORT)"
  echo " -user <string>          VM user to login to (default: $USER)"
  echo " -docker <string>        Dockerfile to build inside the VM (default: $DOCKER_FILE)"
  echo " -config <string>        Configuration file to run the docker container (default: $CONFIG_FILE)"
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
    -docker) DOCKER_FILE="$2"
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

# PARSING CONFIGURATION VALUES
echo "Parsing $CONFIG_FILE.."

# Read container name
container_name=$(jq -r '.container_name' "$CONFIG_FILE")

# Read inputs and outputs
declare -A inputs_map
while IFS=":" read -r key value; do
  inputs_map["$key"]="$value"
done < <(jq -r '.inputs[]' "$CONFIG_FILE")
mapfile -t outputs  < <(jq -r '.outputs[]' "$CONFIG_FILE")

# Setup VM
echo "Creating workload_data folder inside VM ~ directory.."
ssh $USER@$HOST "mkdir -p /home/$USER/workload_data && mkdir -p /home/$USER/workload_results"

# Copy Dockerfile to the VM home directory
echo "Copying Dockerfile inside VM ~ directory.."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=$SSH_HOSTS_FILE -P $PORT $DOCKER_FILE $USER@$HOST:~

# Copying inputs
docker_volumes=""
for key in "${!inputs_map[@]}"; do
  basename=$(basename "$key")
  if [ -d "$key" ]; then
    echo "Copying directory $key in the VM.."
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=$SSH_HOSTS_FILE -P $PORT -r "$key" "$USER@$HOST:/home/$USER/workload_data/$basename"
    docker_volumes+="-v /home/$USER/workload_data/$basename:${inputs_map[$key]} "
  elif [ -f "$key" ]; then
    echo "Copying file $key in the VM.."
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=$SSH_HOSTS_FILE -P $PORT "$key" "$USER@$HOST:/home/$USER/workload_data/"
    docker_volumes+="-v /home/$USER/workload_data/$basename:${inputs_map[$key]} "
  else
    echo "Skipping invalid path: $key"
  fi
done

# Preparing output files to be mounted right in Docker
for output in ${outputs[@]}; do
    dirname=$(dirname "$output")
    if ! contains_colon "$output"; then
      if ends_with_slash "$output"; then
        echo "Creating folder $output in the VM.."
        ssh $USER@$HOST "mkdir -p /home/$USER/workload_results$output"
        docker_volumes+="-v /home/$USER/workload_results$output:$output "
      else
        echo "Creating file $output in the VM.."
        ssh $USER@$HOST "mkdir -p /home/$USER/workload_results$dirname && touch /home/$USER/workload_results/$output"
        docker_volumes+="-v /home/$USER/workload_results$output:$output "
      fi
    fi
done

# Build docker
echo "Building docker image in the VM.."
ssh $USER@$HOST "docker build -t $container_name ."

# Running docker image
echo "Executing docker container ($container_name) in the VM.."
echo "Command: docker run -itd $docker_volumes --name workload $container_name"
ssh $USER@$HOST "docker run -itd $docker_volumes --name workload $container_name"