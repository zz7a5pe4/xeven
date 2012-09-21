#!/bin/bash

cd /home/xeven/devstack
source openrc admin admin
for i in `nova list | grep "SUSPENDED"|cut -d'|' -f2`
do
    printf "resuming $i"
    nova resume $i
    while true;do
        le=`nova list | grep "SUSPENDED"|cut -d'|' -f2 | tr "\n" " "`
        if [[ "$le" =~ $i ]];then
            printf "."
            sleep 1
        else
            break
        fi
    done
    echo "complete"
done


echo "done"
