#!/bin/bash
#use HOST_IP as iScsi target server Ip

if [[ $TOP_DIR -eq "" ]]; then
    TOP_DIR="/home/xeven/devstack"
fi
source $TOP_DIR/localrc

for iqn in `sudo iscsiadm -m discovery -t sendtargets -p $HOST_IP|cut -d' ' -f2`
do
    printf "Logging $iqn ......\n"
    sudo iscsiadm -m node -T $iqn -p $HOST_IP --login
done

echo "done"
