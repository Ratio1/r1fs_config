#!/bin/bash

# Check if exactly two parameters are given
if [ "$#" -eq 2 ]; then
  # Run journalctl with -S and -U options using the provided parameters
  journalctl -a -n 1000 -u edge_node_service -S "$1" -U "$2"
else
  # Run the normal journalctl command
  journalctl -a -n 2000 -f -u edge_node_service
fi