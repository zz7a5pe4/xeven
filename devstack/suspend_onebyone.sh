#!/bin/bash

cd /home/xeven/devstack
source openrc admin admin
for i in `nova list | grep "ACTIVE"|cut -d'|' -f2`
do
    printf "suspending $i"
    nova suspend $i
    while true;do
        le=`nova list | grep "ACTIVE"|cut -d'|' -f2 | tr "\n" " "`
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
