#!/bin/bash
# Install IPFS
wget https://dist.ipfs.io/go-ipfs/v0.32.1/go-ipfs_v0.32.1_linux-amd64.tar.gz
tar xvf go-ipfs_v0.32.1_linux-amd64.tar.gz
cd go-ipfs
sudo ./install.sh

# Initialize IPFS
ipfs init --profile server

# Configure as relay
ipfs config --json Swarm.EnableRelayHop true
ipfs config --json Swarm.EnableAutoRelay true
ipfs config --json Swarm.Transports.Network.Relay true
ipfs config --json Experimental.Libp2pStreamMounting true
ipfs config --json Addresses.Swarm '["/ip4/0.0.0.0/tcp/4001", "/ip4/0.0.0.0/tcp/4001/ws", "/ip4/0.0.0.0/udp/4001/quic"]'
ipfs config Addresses.API /ip4/0.0.0.0/tcp/5001
ipfs config Addresses.Gateway /ip4/0.0.0.0/tcp/8080

# Install swarm key
mkdir -p ~/.ipfs
cp swarm.key ~/.ipfs/

# Create systemd service
cat <<EOF | sudo tee /lib/systemd/system/ipfs.service
[Unit]
Description=IPFS Relay Node
After=network.target

[Service]
User=$USER
ExecStart=/usr/local/bin/ipfs daemon
Restart=always
RestartSec=30
Environment="IPFS_PATH=/home/$USER/.ipfs"

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable ipfs
sudo systemctl start ipfs

# Get relay ID
echo "Relay ID: $(ipfs id -f="<id>")"
