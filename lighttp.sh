#!/bin/bash

X7WORKDIR=`pwd`
CONFDIR=$X7WORKDIR/conf
CURWD=$X7WORKDIR

# download dependency for git, rabbitmq, etc
#sudo apt-get update
#sudo apt-get install -y --assume-yes approx

# setup sources.list and use local deb only
if [ -d $CURWD/ubuntu_repo ]; then
  cp -f $CONFDIR/etc/apt/sources.list.template $CONFDIR/etc/apt/sources.list
  sed -i "s|%HOSTADDR%|127.0.0.1|g" $CONFDIR/etc/apt/sources.list
  if [ ! -f /etc/apt/sources.list.backup ]; then
    sudo mv -f /etc/apt/sources.list /etc/apt/sources.list.backup
  fi
  sudo cp -f $CONFDIR/etc/apt/sources.list /etc/apt/sources.list 
  cd $CURWD/x7http
  cp x7srv.conf.template lighttpd.conf
  sed -i "s|%SRVDOCROOT%|$CURWD/ubuntu_repo|g" $CURWD/x7http/lighttpd.conf
  killall lighttpd || true
  ./lighttpd -f lighttpd.conf -m lib
  cd $CURWD
else
  echo "no ubuntu_repo folder found"
fi

