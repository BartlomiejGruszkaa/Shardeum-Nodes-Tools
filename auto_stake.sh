#!/bin/bash

if [ -z "$1" ]; then
    echo "Error! Specify the container from which to start the auto stake."
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

while IFS=$'\t' read -r container private_key; do
    if [ -z "$container" ] || [ -z "$private_key" ]; then
        echo "Error in private_keys.txt file: line contains invalid data."
        exit 1
    fi

    if [ "$container" == "$start_container" ]; then
        start_processing=true
    fi

    if [ "$start_processing" == true ]; then
        echo "$container"
        info=$(sudo docker exec "$container" /bin/sh -c 'docker exec shardeum-dashboard operator-cli status 2>/dev/null')
        staked_raw=$(echo "$info" | awk "/lockedStake/ {gsub(/lockedStake: /, \"\"); gsub(/\x27\$/, \"\"); print}" 2>/dev/null)
        staked=$(echo "$staked_raw" | sed "s/'//g; s/ //g")
        if [ "$(echo "$staked > 10" | bc)" -eq 1 ]; then
            echo "**********************************************************************************************************************"
            echo "          The number of tokens in the $container is more than 10 ($staked), so staking will be skipped."
            echo "**********************************************************************************************************************"
            continue
        fi
        echo "****************************************************************"
        echo "              	 Staking in $container starts!"
        echo "****************************************************************"
        attempt=1
        while [ $attempt -le 25 ]; do
            echo "****************************************************************"
            echo "                          Attempt $attempt..."
            echo "                  Running stake on $container"
            echo "****************************************************************"
            ( docker exec -i "$container" bin/sh -c 'docker exec -i shardeum-dashboard operator-cli stake 10.01' <<< "$private_key" ) &  # Uruchom w tle
            stake_pid=$! 

            start_time=$(date +%s)

            while kill -0 $stake_pid 2>/dev/null; do
                current_time=$(date +%s)
                elapsed_time=$((current_time - start_time))
                if [ $elapsed_time -gt 25 ]; then
                    echo "******************************************************************************"
                    echo "  Staking in $container took too long, killing the process and retrying..."
                    echo "******************************************************************************"
                
                    kill -9 $stake_pid  
                    wait $stake_pid 2>/dev/null  
                    break
                fi
                sleep 1
            done

            if [ -z "$(docker ps -q --no-trunc | grep $stake_pid)" ]; then
                info=$(sudo docker exec "$container" /bin/sh -c 'docker exec shardeum-dashboard operator-cli status 2>/dev/null')
                staked_raw=$(echo "$info" | awk "/lockedStake/ {gsub(/lockedStake: /, \"\"); gsub(/\x27\$/, \"\"); print}" 2>/dev/null)
                staked=$(echo "$staked_raw" | sed "s/'//g; s/ //g")
                if [ "$staked" = "0" ]; then
                    echo "*************************************************************"
                    echo "              Staking in $container succeeded!"
                    echo "*************************************************************"
                    break
                elif [ "$(echo "$staked > 10" | bc)" -eq 1 ]; then
                    echo "***************************************************************************************************************************"
                    echo "          The number of tokens in the $container is now more than 10 ($staked), so staking will be aborted."
                    echo "***************************************************************************************************************************"
                    break
                else
                    echo "*********************************************************************"
                    echo "     Staking in $container failed or took too long, retrying..."
                    echo "*********************************************************************"
                    ((attempt++))
                fi
            else
                echo "***********************************************************************"
                echo "      Staking in $container was forcefully terminated, retrying..."
                echo "***********************************************************************"
                ((attempt++))
            fi
        done
        if [ $attempt -gt 20 ]; then
            echo "***************************************************************************"
            echo "  Staking in $container failed after 20 attempts. Please check manually."
            echo "***************************************************************************"
        fi
        echo "***********************************************************"
        echo "              Staking in $container ends! <3"
        echo "***********************************************************"
    fi
    
done < "$private_keys_file"
