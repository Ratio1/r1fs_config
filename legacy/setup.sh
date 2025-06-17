#!/bin/bash
wget https://dist.ipfs.tech/kubo/v0.32.1/kubo_v0.32.1_linux-amd64.tar.gz && \
  tar -xvzf kubo_v0.32.1_linux-amd64.tar.gz && \
  cd kubo && \
  bash install.sh

ipfs init

ipfs config --json Swarm.EnableRelayHop true

ipfs bootstrap rm --all

cd ..
./write_key.sh


cp ipfs.service /etc/systemd/system/ipfs.service
sudo systemctl daemon-reload
sudo systemctl enable ipfs
sudo systemctl start ipfs
./show.sh
