#!/bin/bash

containers=$(sudo docker ps --format '{{.Names}}' | tac)

get_container_info() {
  container=$1

  info=$(sudo docker exec $container /bin/sh -c 'docker exec shardeum-dashboard operator-cli status 2>/dev/null')
  state=$(echo "$info" | awk "/state/ {gsub(/state: /, \"\"); print}")
  staked_raw=$(echo "$info" | awk "/lockedStake/ {gsub(/lockedStake: /, \"\"); gsub(/\x27\$/, \"\"); print}" 2>/dev/null)
  version=$(echo "$info" | grep 'shardeumVersion' | awk -F 'shardeumVersion: ' '{print $2}')
  active=$(echo "$info" | awk -F 'lastActive: ' '/lastActive/ {print $2}' | awk -F ' GMT' '{print $1, $2}' | awk '{print $1, $2, $3, $4, $5}')
  rewards=$(echo "$info" | awk -F 'currentRewards: ' '{print $2}' | tr -d '\n' | sed 's/ *$//' | cut -c 1-6 | sed "s/^'//" | sed "s/'$//")
  staked=$(echo "$staked_raw" | sed "s/'//g; s/ //g")
  c=""
  rc="\e[0m"

  if [ "$state" = "waiting-for-network" ]; then
    c="\e[32m"  # Green
  elif [ "$state" = "stopped" ]; then
    c="\e[31m"  # Red
  elif [ "$state" = "standby" ]; then
    c="\e[32m"  # Red
  elif [ "$state" = "active" ]; then
    c="\e[34m"  # Blue
    state="$state "
  fi

  if (( $(echo "$staked < 10" | bc -l) )); then
    c="\e[31m"  # Red
  fi

  container_padded=$(printf "%-20s" "$container")
  staked_padded=$(printf "%-8s" "$staked")
  version_padded=$(printf "%-9s" "$version")
  rewards_padded=$(printf "%-9s" "$rewards")
  active_padded=$(printf "%-25s" "$active")
  state_padded=$(printf "%-20s" "$state")

  echo -e "$container_padded||  ${staked_padded}||  ${version_padded}||  ${rewards_padded}|| ${c}${state_padded}${rc} || ${active_padded}"
}

export -f get_container_info

top_padding+="                    "  
top_padding+="||  "  
top_padding+="||   "  
top_padding+="||     "  
top_padding+="||  "  
top_padding+="|| "  

echo "================================================================================================================"
echo "Container Name      ||  Staked  ||  Version  ||  Rewards  ||        State         ||        Last Active        "
echo "================================================================================================================"
echo "$containers" | parallel -k -j+0 get_container_info 2>/dev/null
echo "================================================================================================================"
