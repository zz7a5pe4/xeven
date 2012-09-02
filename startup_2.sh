#!/bin/bash -x

#set -e
function trackme 
{
    #$CURWD/notify_status.py "log" "$@"
    $@
    local EXIT_CODE=$?
    return $EXIT_CODE
}

if [ $# == 0 ]; then
  echo "you must tell me which nic you use: $0 eth0 or $0 wlan0"
  exit -1
fi

export INTERFACE=$1
source ./addrc

echo ${HOSTADDR:?"empty host addr"}
echo ${MASKADDR:?"empty mask addr"}
echo ${GATEWAY:?"empty gateway"}
echo ${NETWORK:?"empty network"}
echo ${BRDADDR:?"empty broad addr"}

export X7WORKDIR=`pwd`
CONFDIR=$X7WORKDIR/conf
CURWD=$X7WORKDIR
MYID=`whoami`

# ssh id/user setup
if [ ! -f /home/$MYID/.ssh/id_rsa ]; then
  ssh-keygen -b 1024 -t rsa -P "" -f /home/$MYID/.ssh/id_rsa
fi
cat /home/$MYID/.ssh/id_rsa.pub  >> /home/$MYID/.ssh/authorized_keys
cd /home/$MYID 
tar czf $CURWD/ssh.tar.gz .ssh/

# ntp server
#trackme sudo apt-get install -y --force-yes ntp
grep "server 127.127.1.0" /etc/ntp.conf > /dev/null && true
if [ "$?" -ne "0" ]; then
  #trackme echo "configure ntp"
  sudo sed -i 's/server ntp.ubuntu.com/serverntp.ubuntu.com\nserver 127.127.1.0\nfudge 127.127.1.0 stratum 10/g' /etc/ntp.conf
  sudo service ntp restart
fi


# prepare for pxe installation
#trackme sudo apt-get install -y --force-yes fai-quickstart

# dhcp config
cp -f $CONFDIR/etc/dhcp/dhcpd.conf.template $CONFDIR/etc/dhcp/dhcpd.conf
sed -i "s|%NETADDR%|$NETWORK|g" $CONFDIR/etc/dhcp/dhcpd.conf
sed -i "s|%MASKADDR%|$MASKADDR|g" $CONFDIR/etc/dhcp/dhcpd.conf
sed -i "s|%GATEWAY%|$GATEWAY|g" $CONFDIR/etc/dhcp/dhcpd.conf
sed -i "s|%HOSTADDR%|$HOSTADDR|g" $CONFDIR/etc/dhcp/dhcpd.conf
sudo cp -f $CONFDIR/etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf
trackme sudo /etc/init.d/isc-dhcp-server restart




# tftp config
cp -f $CONFDIR/etc/default/tftpd-hpa.template  $CONFDIR/etc/default/tftpd-hpa
trackme sudo cp -f $CONFDIR/etc/default/tftpd-hpa /etc/default/tftpd-hpa
trackme sudo /etc/init.d/tftpd-hpa restart

# vai ubuntu auto-installation setup
cp -f $CONFDIR/srv/tftp/vai/ubuntu-installer/amd64/boot-screens/txt.cfg.template $CONFDIR/srv/tftp/vai/ubuntu-installer/amd64/boot-screens/txt.cfg
sed -i "s|%HOSTADDR%|$HOSTADDR|g" $CONFDIR/srv/tftp/vai/ubuntu-installer/amd64/boot-screens/txt.cfg
sudo mkdir -p /srv/tftp
sudo rm -rf /srv/tftp/*
sudo cp -rf $CONFDIR/srv/tftp/vai /srv/tftp/

# preseed
cp -f $CURWD/www/preseed.cfg.template $CURWD/www/preseed.cfg
sed -i "s|%HOSTADDR%|$HOSTADDR|g" $CURWD/www/preseed.cfg
cp -f $CURWD/www/preseed.cfg $CURWD/ubuntu_repo

# dns setup/config
##TODO##
# hosts config
cp $CONFDIR/etc/hosts.template $CONFDIR/etc/hosts
sed -i "s|%HOSTADDR%|$HOSTADDR|g" $CONFDIR/etc/hosts
sed -i "s|%HOSTNAME%|$HOSTNAME|g" $CONFDIR/etc/hosts
sudo cp -rf $CONFDIR/etc/hosts /etc/hosts

# nfs path prepare
sudo mkdir -p /srv/instances
sudo chmod 777 /srv/instances
grep "/srv/instances $HOSTADDR/24" /etc/exports > /dev/null  && true
if [ "$?" -ne "0" ]; then
    echo "/srv/instances $HOSTADDR/24(sync,rw,fsid=0,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports > /dev/null
    echo "/srv/instances 127.0.0.1(sync,rw,fsid=0,no_subtree_check,no_root_squash)" | sudo tee -a  /etc/exports > /dev/null
    sudo /etc/init.d/nfs-kernel-server restart
    sudo /etc/init.d/idmapd restart
fi



cp -f $CONFDIR/etc/apt/sources.list.template $CONFDIR/sources.list.client
sed -i "s|%HOSTADDR%|$HOSTADDR|g" $CONFDIR/sources.list.client

#devstack & openstack packages
#mkdir -p $CURWD/cache
#if [ ! -f $CURWD/cache/devstack.tar.gz ]; then
#  trackme wget https://github.com/downloads/zz7a5pe4/x7_start/devstack.tar.gz -O $CURWD/cache/devstack.tar.gz
#fi

#rm -rf $CURWD/devstack
#tar xzf $CURWD/cache/devstack.tar.gz -C $CURWD/ 
( cd $CURWD/ && tar czf $CURWD/cache/devstack.tar.gz $CURWD/devstack )

if [ ! -f $CURWD/cache/cirros-0.3.0-x86_64-uec.tar.gz ]; then
  wget https://github.com/downloads/zz7a5pe4/x7_start/cirros-0.3.0-x86_64-uec.tar.gz -O $CURWD/cache/cirros-0.3.0-x86_64-uec.tar.gz
fi
cp -f $CURWD/cache/cirros-0.3.0-x86_64-uec.tar.gz $CURWD/devstack/files/cirros-0.3.0-x86_64-uec.tar.gz


if [ ! -f $CURWD/cache/stack.zip ]; then
  trackme wget https://nodeload.github.com/zz7a5pe4/x7_dep/zipball/master -O $CURWD/cache/stack.zip
fi
rm -rf $CURWD/stack $CURWD/zz7a5pe4-x7_dep*
unzip $CURWD/cache/stack.zip -d $CURWD/ 
mv $CURWD/zz7a5pe4-x7_dep*  $CURWD/stack

sudo rm -rf /opt/stack
sudo mv -f $CURWD/stack /opt
sudo chown -R $MYID:$MYID /opt/stack

mkdir -p $CURWD/cache/apt
mkdir -p $CURWD/cache/img
mkdir -p $CURWD/cache/pip
mkdir -p $CURWD/cache/piptmp
sudo rm -rf $CURWD/cache/piptmp/* 

#trackme sudo apt-get install --force-yes -y $PYDEP

# image and pip
if [ -d /media/x7_usb/ ]; then
  cp /media/x7_usb/x7_cache/cirros-0.3.0-x86_64-uec.tar.gz $CURWD/cache/img/cirros-0.3.0-x86_64-uec.tar.gz
  tar xzf /media/x7_usb/x7_cache/pika-0.9.5.tar.gz -C $CURWD/cache/pip/
  tar xzf /media/x7_usb/x7_cache/passlib-1.5.3.tar.gz -C $CURWD/cache/pip/
  tar xzf /media/x7_usb/x7_cache/django-nose-selenium-0.7.3.tar.gz -C $CURWD/cache/pip/
else
  #[ -f $CURWD/cache/img/cirros-0.3.0-x86_64-uec.tar.gz ] || wget http://launchpad.net/cirros/trunk/0.3.0/+download/cirros-0.3.0-x86_64-uec.tar.gz -O $CURWD/cache/img/cirros-0.3.0-x86_64-uec.tar.gz
  [ -f $CURWD/cache/pip/pika-0.9.5.tar.gz ] || wget https://github.com/downloads/jkerng/x7/pika-0.9.5.tar.gz -O $CURWD/cache/pip/pika-0.9.5.tar.gz
  [ -f $CURWD/cache/pip/passlib-1.5.3.tar.gz ] || wget https://github.com/downloads/jkerng/x7/passlib-1.5.3.tar.gz -O $CURWD/cache/pip/passlib-1.5.3.tar.gz
  [ -f $CURWD/cache/pip/django-nose-selenium-0.7.3.tar.gz ] || wget https://github.com/downloads/jkerng/x7/django-nose-selenium-0.7.3.tar.gz -O $CURWD/cache/pip/django-nose-selenium-0.7.3.tar.gz
  [ -f $CURWD/cache/pip/pam-0.1.4.tar.gz ] || wget https://github.com/downloads/jkerng/x7/pam-0.1.4.tar.gz -O $CURWD/cache/pip/pam-0.1.4.tar.gz
  [ -f $CURWD/cache/pip/pycrypto-2.3.tar.gz ] || wget https://github.com/downloads/jkerng/x7/pycrypto-2.3.tar.gz -O $CURWD/cache/pip/pycrypto-2.3.tar.gz
fi

tar xzf $CURWD/cache/pip/pika-0.9.5.tar.gz -C $CURWD/cache/piptmp/
tar xzf $CURWD/cache/pip/passlib-1.5.3.tar.gz -C $CURWD/cache/piptmp/
tar xzf $CURWD/cache/pip/django-nose-selenium-0.7.3.tar.gz -C $CURWD/cache/piptmp/
tar xzf $CURWD/cache/pip/pam-0.1.4.tar.gz -C $CURWD/cache/piptmp/
tar xzf $CURWD/cache/pip/pycrypto-2.3.tar.gz -C $CURWD/cache/piptmp/
[ -f $CURWD/cache/pip/WebOb-1.0.8.tar.gz ] && tar xzf $CURWD/cache/pip/WebOb-1.0.8.tar.gz -C $CURWD/cache/piptmp/
chmod -R +r $CURWD/cache/piptmp || true


if [ -d $CURWD/cache/piptmp ];then
  pippackages=`ls $CURWD/cache/piptmp`
  for package in ${pippackages}; do
    cd $CURWD/cache/piptmp/$package && sudo python setup.py install
    echo "$CURWD/cache/piptmp/$package"
  done
fi

cd $CURWD/cache 
tar czf $CURWD/cache/pip.tar.gz --exclude "*.tar.gz" piptmp


mkdir -p $CURWD/log/
rm -rf $CURWD/log/*
cp -f $CURWD/localrc_server_template $CURWD/devstack/localrc

cd $CURWD/devstack
sed -i "s|%HOSTADDR%|$HOSTADDR|g" localrc
sed -i "s|%INTERFACE%|$INTERFACE|g" localrc
sed -i "s|%BRDADDR%|$BRDADDR|g" localrc

grep "add_nova_opt \"logdir=" stack.sh > /dev/null && true
# "0" => found
if [ "$?" -ne "0" ]; then
  sed -i "s,add_nova_opt \"verbose=True\",add_nova_opt \"verbose=True\"\nadd_nova_opt \"logdir=$CURWD/log\",g" stack.sh
fi
trackme ./stack.sh
sudo mkdir -p /opt/stack/nova/instances

cp -f $CURWD/localrc_compute_template $CURWD/localrc_compute
sed -i "s|%SERVERADDR%|$HOSTADDR|g" $CURWD/localrc_compute
sed -i "s|%BRDADDR%|$BRDADDR|g" $CURWD/localrc_compute

#echo "change libvirt config for migrate"
#sudo sed -i  /etc/libvirt/libvirtd.conf -e "
#        s,#listen_tls = 0,listen_tls = 0,g;
#        s,#listen_tcp = 1,listen_tcp = 1,g;
#        s,#auth_tcp = \"sasl\",auth_tcp = \"none\",g;
#"

#sudo sed -i /etc/default/libvirt-bin -e "s,libvirtd_opts=\"-d\",libvirtd_opts=\" -d -l\",g"
#sudo /etc/init.d/libvirt-bin restart

cd $CURWD/devstack
source ./openrc admin admin
#python $CURWD/migrate_monitor.py &

#$CURWD/notify_status.py cmd complete

exit 0
