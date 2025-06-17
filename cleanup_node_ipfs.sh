#!/bin/bash

# Warning prompt for destructive operation
while true; do
    read -p "WARNING: this is a destructive operation. Do you want to proceed? (y/N): " yn
    case $yn in
        [Yy]* )
            echo "Proceeding with operation..."
            break
            ;;
        [Nn]* | "" )
            echo "Operation cancelled."
            exit 0
            ;;
        * )
            echo "Please answer y (yes) or N (no)."
            ;;
    esac
done

# Execute the destructive operations after confirmation
rm -rf /var/cache/edge_node/_local_cache/.ipfs
./restart.sh
