#!/bin/bash

if [[ $TOP_DIR -eq "" ]]; then
    TOP_DIR="/home/xeven/devstack"
fi

source $TOP_DIR/localrc
source $TOP_DIR/openrc admin admin

#use HOST_IP as iScsi target server Ip
function login_inuse_volume {
    for volID in `nova volume-list |grep in-use|cut -d' ' -f2`
    do
        if [ "$volID" = "$1" ]; then
            printf "Logging $2 ......\n"
            sudo iscsiadm -m node -T $2 -p $HOST_IP --login
        fi
    done
}



for iqn in `sudo iscsiadm -m discovery -t sendtargets -p $HOST_IP|cut -d' ' -f2`
do
#   get id and transfer from hex id to dec id 
    id_hex=0x${iqn:0-8}
    volumeid=$((id_hex))
    login_inuse_volume $volumeid $iqn
done

echo "done"

