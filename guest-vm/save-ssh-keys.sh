#!/bin/bash
set -e

NAME=
IP=

usage() {
  echo "$0 [options]"
  echo " -name          ssh key name to store in ~/.ssh"
  echo " -ip            IP host to connect with the provided ssh key"

  exit
}

while [ -n "$1" ]; do
	case "$1" in
		-name) NAME="$2"
			shift
			;;
        -ip) IP="$2"
			shift
			;;
		*)  usage
			;;
	esac

	shift
done

if [[ -z "$NAME" || -z "$IP" ]]; then
  echo "Error: Both -name and -ip must be provided."
  usage
fi

mv $GUEST_DIR/keys/ssh-key-vm-owner ~/.ssh/$NAME
mv $GUEST_DIR/keys/ssh-key-vm-owner.pub ~/.ssh/$NAME.pub
echo "Host $NAME
    HostName $IP
    User ubuntu
    IdentityFile ~/.ssh/$NAME
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null" | tee -a ~/.ssh/config > /dev/null

echo "Now you will access the machine with: ssh $NAME"