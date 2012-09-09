#!/bin/bash

ADMINUSERNAME=`getent passwd | awk -F: '$3 == 1000 { print $1 }'`
grep "^$ADMINUSERNAME ALL=(ALL) NOPASSWD: ALL$" /etc/sudoers > /dev/null

if [ "$?" -ne "0" ];
  then
    chmod +w /etc/sudoers
    echo "$ADMINUSERNAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    chmod -w /etc/sudoers
  else
    echo "already in sudoer"
fi
source /home/xeven/x7env
(cd /home/xeven && sudo -u $ADMINUSERNAME ./startup all)
