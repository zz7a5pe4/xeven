#!/bin/bash

cd /home/xeven/devstack
source openrc admin admin
for i in `nova list | grep "SUSPENDED"|cut -d'|' -f2`
do
    echo "send resume to $i"
    nova resume $i
done
echo "waiting for complete"
while true;do
    le=`nova list | grep "SUSPENDED"|cut -d'|' -f2 | head -1`
    if [ -n "$le" ];then
        printf "."
        sleep 1
    else
        printf "\n"
        break
    fi
done
echo "done"
