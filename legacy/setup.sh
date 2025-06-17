#!/bin/bash

log_with_color() {
    local text="$1"
    local color="$2"
    local color_code=""

    case $color in
        red)
            color_code="0;31" # Red
            ;;
        green)
            color_code="0;32" # Green
            ;;
        blue)
            color_code="0;36" # Blue
            ;;
        yellow)
            color_code="0;33" # Yellow
            ;;
        light)
            color_code="1;37" # Light (White)
            ;;
        gray)
            color_code="2;37" # Gray (White)
            ;;
        *)
            color_code="0" # Default color
            ;;
    esac

    echo -e "\e[${color_code}m${text}\e[0m"
}


wget https://dist.ipfs.tech/kubo/v0.32.1/kubo_v0.32.1_linux-amd64.tar.gz && \
  tar -xvzf kubo_v0.32.1_linux-amd64.tar.gz && \
  cd kubo && \
  bash install.sh

log_with_color "Kubo installed successfully." "green"
log_with_color "Setting up IPFS Relay Node..." "blue"

ipfs init

ipfs config --json Swarm.EnableRelayHop true

ipfs bootstrap rm --all

log_with_color "Creating swarm key for private network enforcement..." "blue"

cd ..
./write_key.sh

log_with_color "Starting IPFS service..." "blue"

cp ipfs.service /etc/systemd/system/ipfs.service
sudo systemctl daemon-reload
sudo systemctl enable ipfs
sudo systemctl start ipfs

log_with_color "IPFS service started successfully." "green"

./show.sh
