#!/bin/bash

sudo apt update && sudo apt install -y expect nano apt-transport-https ca-certificates curl software-properties-common parallel bc && \
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - && \
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" && \
sudo apt update && sudo apt install -y docker-ce

liczba_kontenerow=127
portt1=8080
portt2=9001
portt3=10001

for ((i=0; i<=$liczba_kontenerow; i++)); do
    docker run --privileged -d \
    --name dashboard_$i \
    -p $portt1:$portt1 \
    -p $portt2:$portt2 \
    -p $portt3:$portt3 \
    docker:dind

    echo "Uruchomiono kontener dashboard_$i na portach $portt1, $portt2, $portt3."
    
    portt1=$((portt1+1))
    portt2=$((portt2+1))
    portt3=$((portt3+1))
done

containers=$(docker ps -q)
plik_do_skopiowania="/root/.setup.sh"

for container in $containers
do
    echo "$container"
    docker cp $plik_do_skopiowania $container:/
    docker exec $container chmod +x /.setup.sh
done

install_dependencies() {
    container_id=$1
    docker exec -i $container_id sh -c 'apk add curl && apk add git && apk add --no-cache bash && apk update && apk add expect'
    echo $container_id
}

export -f install_dependencies

parallel -k -j 4 install_dependencies ::: $containers



container_ids=$(docker ps -q)
container_ids_reversed=$(echo "$container_ids" | tac)



install_in_container() {
    local container_id=$1
    local p1=$2
    local p2=$3
    local p3=$4


    container_name=$(docker inspect --format '{{.Name}}' $container_id)
    container_name=${container_name:1}

    port_info=$(docker port $container_id)

    local port1=""
    local port2=""
    local port3=""

    while read -r line; do
        port=$(echo "$line" | cut -d ':' -f 2 | cut -d '/' -f 1)
        if [ -n "$port" ]; then
            if [ -z "$port1" ]; then
                port1="$port"
            elif [ -z "$port2" ]; then
                port2="$port"
            elif [ -z "$port3" ]; then
                port3="$port"
            fi
        fi
    done <<< "$port_info"

    echo "Porty w kontenerze $container_name: Port1=$port1, Port2=$port2, Port3=$port3"
    
    echo "**************************************************************"
    echo "Installation in $container_name starts!"
    echo "**************************************************************"
    docker exec -i $container_id /.setup.sh $port1 $port2 $port3
    echo "**************************************************************"
    echo "Installation in $container_name ends! <3"
    # docker exec $container_id rm .setup.sh
    echo "**************************************************************"
}

export -f install_in_container

containers=$(docker ps -q | tac)
parallel -k -j 4 install_in_container ::: "$containers" $port1 $port2 $port3


start_operator_cli() {
    container_id=$1
    docker exec $container_id bin/sh -c 'docker exec -i shardeum-dashboard operator-cli start'
    echo "$container_id"
}

export -f start_operator_cli


parallel -k -j 4 start_operator_cli ::: $container_ids_reversed

