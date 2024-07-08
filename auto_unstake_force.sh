#!/bin/bash

ctrl_c() {
    echo "Interrupted by user."
    exit 1
}

trap ctrl_c INT

if [ -z "$1" ]; then
    echo "Error. Specify the container from which to start auto unstake."
    exit 1
fi

starter=$1

containers=$(docker ps --format "{{.Names}}")
private_keys_file="private_keys.txt"

if [ ! -f "$private_keys_file" ]; then
    echo "No private key file: $private_keys_file"
    exit 1
fi

start_container="dashboard_$starter"
start_index=$(echo "$containers" | grep -n "$start_container" | cut -d: -f1)

start_processing=false

max_attempts=30

while IFS=$'\t' read -r container private_key; do
    if [ -z "$container" ] || [ -z "$private_key" ]; then
        echo "Error in private_keys.txt file: line contains invalid data."
        exit 1
    fi

    if [ "$container" == "$start_container" ]; then
        start_processing=true
    fi

    if [ "$start_processing" == true ]; then
        echo "Unstake force on $container..."
        attempts=0

        while [ $attempts -lt $max_attempts ]; do
            echo "Attempt $attempts..."
            expect << EOF
                spawn docker exec -i $container /bin/bash -c "docker exec -i shardeum-dashboard operator-cli unstake -f"
                expect "Node is currently participating in the network, unstaking could result in a penalty. Confirm if you would like to force unstake (y/N): "
                send "y\n"
                expect "Please enter your private key: "
                send "$private_key\n"
                expect {
                    "No stake found" { exit 0 }
                    timeout { exit 1 }
                }
EOF
            sleep 10
            if [ $? -eq 0 ]; then
                echo "Succes"
                break
            fi
            ((attempts++))
        done
    fi
    
done < "$private_keys_file"
