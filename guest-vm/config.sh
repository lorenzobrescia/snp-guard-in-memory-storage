#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

DOCKER="1"

# Imposing timeout to systemd-networkd-wait-online service
echo "Imposing timeout to network startup service..."
SYSTEMD_SERVICE="/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
if [[ -f "$SYSTEMD_SERVICE" ]]; then
    sed -i 's|^ExecStart=.*|ExecStart=/lib/systemd/systemd-networkd-wait-online --timeout=5|' "$SYSTEMD_SERVICE"
    echo "Done. updated ExecStart in $SYSTEMD_SERVICE"
else
    echo "Warning: $SYSTEMD_SERVICE not found. Skipping modification."
fi

# Configuration to be sure dhclient start at every boot
echo "Configuration auto dhclient. Creating /etc/rc.local..."
cat <<EOF > /etc/rc.local
#!/bin/bash
dhclient
exit 0
EOF
chmod +x /etc/rc.local

# Install Docker if required
if [[ "$DOCKER" == "1" ]]; then
    echo "Installing Docker..."
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
    # Add Docker's official GPG key:
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo groupadd docker
    sudo usermod -aG docker $USER
    echo "Docker installed."
fi

# Install kernel and headers (copied before) this is needed even when running direct boot, as we still need access to the kernel module files
echo "Installing kernel and headers..."
sudo dpkg -i linux-*.deb
rm -rf linux-*.deb 
sudo systemctl disable multipathd.service

rm config.sh
echo "Setup complete. Reboot for changes to take effect."