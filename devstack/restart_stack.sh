#!/usr/bin/env bash

# ``stack.sh`` is an opinionated OpenStack developer installation.  It
# installs and configures various combinations of **Glance**, **Horizon**,
# **Keystone**, **Melange**, **Nova**, **Quantum** and **Swift**

# This script allows you to specify configuration options of what git
# repositories to use, enabled services, network configuration and various
# passwords.  If you are crafty you can run the script on multiple nodes using
# shared settings for common resources (mysql, rabbitmq) and build a multi-node
# developer install.

# To keep this script simple we assume you are running on an **Ubuntu 11.10
# Oneiric** or **Ubuntu 12.04 Precise** machine.  It should work in a VM or
# physical server.  Additionally we put the list of ``apt`` and ``pip``
# dependencies and other configuration files in this repo.  So start by
# grabbing this script and the dependencies.

# Learn more and get the most recent version at http://devstack.org

# Keep track of the devstack directory
TOP_DIR=$(cd $(dirname "$0") && pwd)

# Import common functions
source $TOP_DIR/functions


# Settings
# ========

# ``stack.sh`` is customizable through setting environment variables.  If you
# want to override a setting you can set and export it::
#
#     export MYSQL_PASSWORD=anothersecret
#     ./stack.sh
#
# You can also pass options on a single line ``MYSQL_PASSWORD=simple ./stack.sh``
#
# Additionally, you can put any local variables into a ``localrc`` file::
#
#     MYSQL_PASSWORD=anothersecret
#     MYSQL_USER=hellaroot
#
# We try to have sensible defaults, so you should be able to run ``./stack.sh``
# in most cases.
#
# DevStack distributes ``stackrc`` which contains locations for the OpenStack
# repositories and branches to configure.  ``stackrc`` sources ``localrc`` to
# allow you to safely override those settings without being overwritten
# when updating DevStack.

# HTTP and HTTPS proxy servers are supported via the usual environment variables
# ``http_proxy`` and ``https_proxy``.  They can be set in ``localrc`` if necessary
# or on the command line::
#
#     http_proxy=http://proxy.example.com:3128/ ./stack.sh

if [[ ! -r $TOP_DIR/stackrc ]]; then
    echo "ERROR: missing $TOP_DIR/stackrc - did you grab more than just stack.sh?"
    exit 1
fi
source ./stackrc

# Destination path for installation ``DEST``
DEST=${DEST:-/opt/stack}

# stack.sh keeps the list of ``apt`` and ``pip`` dependencies in external
# files, along with config templates and other useful files.  You can find these
# in the ``files`` directory (next to this script).  We will reference this
# directory using the ``FILES`` variable in this script.
FILES=$TOP_DIR/files
if [ ! -d $FILES ]; then
    echo "ERROR: missing devstack/files - did you grab more than just stack.sh?"
    exit 1
fi

# Check to see if we are already running DevStack
if type -p screen >/dev/null && screen -ls | egrep -q "[0-9].stack"; then
    echo "You are already running a stack.sh session."
    echo "To rejoin this session type 'screen -x stack'."
    echo "To destroy this session, kill the running screen."
    exit 1
fi

# OpenStack is designed to be run as a regular user (Horizon will fail to run
# as root, since apache refused to startup serve content from root user).  If
# ``stack.sh`` is run as **root**, it automatically creates a **stack** user with
# sudo privileges and runs as that user.

if [[ $EUID -eq 0 ]]; then
    ROOTSLEEP=${ROOTSLEEP:-10}
    echo "You are running this script as root."
    echo "In $ROOTSLEEP seconds, we will create a user 'stack' and run as that user"
    sleep $ROOTSLEEP

    # since this script runs as a normal user, we need to give that user
    # ability to run sudo
    dpkg -l sudo || apt_get update && install_package sudo

    if ! getent passwd stack >/dev/null; then
        echo "Creating a user called stack"
        useradd -U -G sudo -s /bin/bash -d $DEST -m stack
    fi

    echo "Giving stack user passwordless sudo priviledges"
    # some uec images sudoers does not have a '#includedir'. add one.
    grep -q "^#includedir.*/etc/sudoers.d" /etc/sudoers ||
        echo "#includedir /etc/sudoers.d" >> /etc/sudoers
    ( umask 226 && echo "stack ALL=(ALL) NOPASSWD:ALL" \
        > /etc/sudoers.d/50_stack_sh )

    echo "Copying files to stack user"
    STACK_DIR="$DEST/${PWD##*/}"
    cp -r -f -T "$PWD" "$STACK_DIR"
    chown -R stack "$STACK_DIR"
    if [[ "$SHELL_AFTER_RUN" != "no" ]]; then
        exec su -c "set -e; cd $STACK_DIR; bash stack.sh; bash" stack
    else
        exec su -c "set -e; cd $STACK_DIR; bash stack.sh" stack
    fi
    exit 1
else
    # We're not root, make sure sudo is available
    dpkg -l sudo || die "Sudo is required.  Re-run stack.sh as root ONE TIME ONLY to set up sudo."

    # UEC images /etc/sudoers does not have a '#includedir'. add one.
    sudo grep -q "^#includedir.*/etc/sudoers.d" /etc/sudoers ||
        echo "#includedir /etc/sudoers.d" | sudo tee -a /etc/sudoers

    # Set up devstack sudoers
    TEMPFILE=`mktemp`
    echo "`whoami` ALL=(root) NOPASSWD:ALL" >$TEMPFILE
    chmod 0440 $TEMPFILE
    sudo chown root:root $TEMPFILE
    sudo mv $TEMPFILE /etc/sudoers.d/50_stack_sh

    # Set up the rootwrap sudoers
    TEMPFILE=`mktemp`
    echo "$USER ALL=(root) NOPASSWD: /usr/local/bin/nova-rootwrap" >$TEMPFILE
    chmod 0440 $TEMPFILE
    sudo chown root:root $TEMPFILE
    sudo mv $TEMPFILE /etc/sudoers.d/nova-rootwrap

    # Remove old file
    sudo rm -f /etc/sudoers.d/stack_sh_nova
fi

# Set True to configure ``stack.sh`` to run cleanly without Internet access.
# ``stack.sh`` must have been previously run with Internet access to install
# prerequisites and initialize ``$DEST``.
OFFLINE=`trueorfalse False $OFFLINE`

# Set the destination directories for openstack projects
NOVA_DIR=$DEST/nova
HORIZON_DIR=$DEST/horizon
GLANCE_DIR=$DEST/glance
KEYSTONE_DIR=$DEST/keystone
NOVACLIENT_DIR=$DEST/python-novaclient
KEYSTONECLIENT_DIR=$DEST/python-keystoneclient
NOVNC_DIR=$DEST/noVNC
SWIFT_DIR=$DEST/swift
QUANTUM_DIR=$DEST/quantum
QUANTUM_CLIENT_DIR=$DEST/python-quantumclient
MELANGE_DIR=$DEST/melange
MELANGECLIENT_DIR=$DEST/python-melangeclient

# Default Quantum Plugin
Q_PLUGIN=${Q_PLUGIN:-openvswitch}
# Default Quantum Port
Q_PORT=${Q_PORT:-9696}
# Default Quantum Host
Q_HOST=${Q_HOST:-localhost}

# Default Melange Port
M_PORT=${M_PORT:-9898}
# Default Melange Host
M_HOST=${M_HOST:-localhost}
# Melange MAC Address Range
M_MAC_RANGE=${M_MAC_RANGE:-FE-EE-DD-00-00-00/24}

# Name of the lvm volume group to use/create for iscsi volumes
VOLUME_GROUP=${VOLUME_GROUP:-nova-volumes}
VOLUME_NAME_PREFIX=${VOLUME_NAME_PREFIX:-volume-}
INSTANCE_NAME_PREFIX=${INSTANCE_NAME_PREFIX:-instance-}

# Nova hypervisor configuration.  We default to libvirt with **kvm** but will
# drop back to **qemu** if we are unable to load the kvm module.  ``stack.sh`` can
# also install an **LXC** based system.
VIRT_DRIVER=${VIRT_DRIVER:-libvirt}
LIBVIRT_TYPE=${LIBVIRT_TYPE:-kvm}

# Nova supports pluggable schedulers.  ``FilterScheduler`` should work in most
# cases.
SCHEDULER=${SCHEDULER:-nova.scheduler.filter_scheduler.FilterScheduler}

HOST_IP_IFACE=${HOST_IP_IFACE:-eth0}
# Use the eth0 IP unless an explicit is set by ``HOST_IP`` environment variable
if [ -z "$HOST_IP" -o "$HOST_IP" == "dhcp" ]; then
    HOST_IP=`LC_ALL=C /sbin/ifconfig ${HOST_IP_IFACE} | grep -m 1 'inet addr:'| cut -d: -f2 | awk '{print $1}'`
    if [ "$HOST_IP" = "" ]; then
        echo "Could not determine host ip address."
        echo "Either localrc specified dhcp on ${HOST_IP_IFACE} or defaulted to eth0"
        exit 1
    fi
fi

# Allow the use of an alternate hostname (such as localhost/127.0.0.1) for service endpoints.
SERVICE_HOST=${SERVICE_HOST:-$HOST_IP}

# Configure services to use syslog instead of writing to individual log files
SYSLOG=`trueorfalse False $SYSLOG`
SYSLOG_HOST=${SYSLOG_HOST:-$HOST_IP}
SYSLOG_PORT=${SYSLOG_PORT:-516}

# Service startup timeout
SERVICE_TIMEOUT=${SERVICE_TIMEOUT:-60}

# Generic helper to configure passwords
function read_password {
    set +o xtrace
    var=$1; msg=$2
    pw=${!var}

    localrc=$TOP_DIR/localrc

    # If the password is not defined yet, proceed to prompt user for a password.
    if [ ! $pw ]; then
        # If there is no localrc file, create one
        if [ ! -e $localrc ]; then
            touch $localrc
        fi

        # Presumably if we got this far it can only be that our localrc is missing
        # the required password.  Prompt user for a password and write to localrc.
        echo ''
        echo '################################################################################'
        echo $msg
        echo '################################################################################'
        echo "This value will be written to your localrc file so you don't have to enter it "
        echo "again.  Use only alphanumeric characters."
        echo "If you leave this blank, a random default value will be used."
        pw=" "
        while true; do
            echo "Enter a password now:"
            read -e $var
            pw=${!var}
            [[ "$pw" = "`echo $pw | tr -cd [:alnum:]`" ]] && break
            echo "Invalid chars in password.  Try again:"
        done
        if [ ! $pw ]; then
            pw=`openssl rand -hex 10`
        fi
        eval "$var=$pw"
        echo "$var=$pw" >> $localrc
    fi
    set -o xtrace
}


# Nova Network Configuration
# --------------------------

# FIXME: more documentation about why these are important options.  Also
# we should make sure we use the same variable names as the option names.

if [ "$VIRT_DRIVER" = 'xenserver' ]; then
    PUBLIC_INTERFACE_DEFAULT=eth3
    # allow build_domU.sh to specify the flat network bridge via kernel args
    FLAT_NETWORK_BRIDGE_DEFAULT=$(grep -o 'flat_network_bridge=[^.]*' /proc/cmdline | cut -d= -f 2)
    GUEST_INTERFACE_DEFAULT=eth1
else
    PUBLIC_INTERFACE_DEFAULT=br100
    FLAT_NETWORK_BRIDGE_DEFAULT=br100
    GUEST_INTERFACE_DEFAULT=eth0
fi

PUBLIC_INTERFACE=${PUBLIC_INTERFACE:-$PUBLIC_INTERFACE_DEFAULT}
PUBLIC_INTERFACE=${PUBLIC_INTERFACE:-br100}
FIXED_RANGE=${FIXED_RANGE:-10.0.0.0/24}
FIXED_NETWORK_SIZE=${FIXED_NETWORK_SIZE:-256}
FLOATING_RANGE=${FLOATING_RANGE:-172.24.4.224/28}
NET_MAN=${NET_MAN:-FlatDHCPManager}
EC2_DMZ_HOST=${EC2_DMZ_HOST:-$SERVICE_HOST}
FLAT_NETWORK_BRIDGE=${FLAT_NETWORK_BRIDGE:-$FLAT_NETWORK_BRIDGE_DEFAULT}
VLAN_INTERFACE=${VLAN_INTERFACE:-$GUEST_INTERFACE_DEFAULT}

# Test floating pool and range are used for testing.  They are defined
# here until the admin APIs can replace nova-manage
TEST_FLOATING_POOL=${TEST_FLOATING_POOL:-test}
TEST_FLOATING_RANGE=${TEST_FLOATING_RANGE:-192.168.253.0/29}

# **MULTI_HOST** is a mode where each compute node runs its own network node.  This
# allows network operations and routing for a VM to occur on the server that is
# running the VM - removing a SPOF and bandwidth bottleneck.
MULTI_HOST=${MULTI_HOST:-False}

# If you are using FlatDHCP on multiple hosts, set the ``FLAT_INTERFACE``
# variable but make sure that the interface doesn't already have an
# ip or you risk breaking things.
#
# **DHCP Warning**:  If your flat interface device uses DHCP, there will be a
# hiccup while the network is moved from the flat interface to the flat network
# bridge.  This will happen when you launch your first instance.  Upon launch
# you will lose all connectivity to the node, and the vm launch will probably
# fail.
#
# If you are running on a single node and don't need to access the VMs from
# devices other than that node, you can set the flat interface to the same
# value as ``FLAT_NETWORK_BRIDGE``.  This will stop the network hiccup from
# occurring.
FLAT_INTERFACE=${FLAT_INTERFACE:-$GUEST_INTERFACE_DEFAULT}

## FIXME(ja): should/can we check that FLAT_INTERFACE is sane?

# Using Quantum networking:
#
# Make sure that quantum is enabled in ENABLED_SERVICES.  If it is the network
# manager will be set to the QuantumManager.  If you want to run Quantum on
# this host, make sure that q-svc is also in ENABLED_SERVICES.
#
# If you're planning to use the Quantum openvswitch plugin, set Q_PLUGIN to
# "openvswitch" and make sure the q-agt service is enabled in
# ENABLED_SERVICES.
#
# With Quantum networking the NET_MAN variable is ignored.

# Using Melange IPAM:
#
# Make sure that quantum and melange are enabled in ENABLED_SERVICES.
# If they are then the melange IPAM lib will be set in the QuantumManager.
# Adding m-svc to ENABLED_SERVICES will start the melange service on this
# host.


# MySQL & RabbitMQ
# ----------------

# We configure Nova, Horizon, Glance and Keystone to use MySQL as their
# database server.  While they share a single server, each has their own
# database and tables.

# By default this script will install and configure MySQL.  If you want to
# use an existing server, you can pass in the user/password/host parameters.
# You will need to send the same ``MYSQL_PASSWORD`` to every host if you are doing
# a multi-node DevStack installation.
MYSQL_HOST=${MYSQL_HOST:-localhost}
MYSQL_USER=${MYSQL_USER:-root}
read_password MYSQL_PASSWORD "ENTER A PASSWORD TO USE FOR MYSQL."

# NOTE: Don't specify /db in this string so we can use it for multiple services
BASE_SQL_CONN=${BASE_SQL_CONN:-mysql://$MYSQL_USER:$MYSQL_PASSWORD@$MYSQL_HOST}

# Rabbit connection info
RABBIT_HOST=${RABBIT_HOST:-localhost}
read_password RABBIT_PASSWORD "ENTER A PASSWORD TO USE FOR RABBIT."

# Glance connection info.  Note the port must be specified.
GLANCE_HOSTPORT=${GLANCE_HOSTPORT:-$SERVICE_HOST:9292}


# SWIFT
# -----
# TODO: implement glance support
# TODO: add logging to different location.

# By default the location of swift drives and objects is located inside
# the swift source directory. SWIFT_DATA_DIR variable allow you to redefine
# this.
SWIFT_DATA_DIR=${SWIFT_DATA_DIR:-${DEST}/data/swift}

# We are going to have the configuration files inside the source
# directory, change SWIFT_CONFIG_DIR if you want to adjust that.
SWIFT_CONFIG_DIR=${SWIFT_CONFIG_DIR:-/etc/swift}

# devstack will create a loop-back disk formatted as XFS to store the
# swift data. By default the disk size is 1 gigabyte. The variable
# SWIFT_LOOPBACK_DISK_SIZE specified in bytes allow you to change
# that.
SWIFT_LOOPBACK_DISK_SIZE=${SWIFT_LOOPBACK_DISK_SIZE:-1000000}

# The ring uses a configurable number of bits from a path’s MD5 hash as
# a partition index that designates a device. The number of bits kept
# from the hash is known as the partition power, and 2 to the partition
# power indicates the partition count. Partitioning the full MD5 hash
# ring allows other parts of the cluster to work in batches of items at
# once which ends up either more efficient or at least less complex than
# working with each item separately or the entire cluster all at once.
# By default we define 9 for the partition count (which mean 512).
SWIFT_PARTITION_POWER_SIZE=${SWIFT_PARTITION_POWER_SIZE:-9}

# This variable allows you to configure how many replicas you want to be
# configured for your Swift cluster.  By default the three replicas would need a
# bit of IO and Memory on a VM you may want to lower that to 1 if you want to do
# only some quick testing.
SWIFT_REPLICAS=${SWIFT_REPLICAS:-3}

if is_service_enabled swift; then
    # If we are using swift, we can default the s3 port to swift instead
    # of nova-objectstore
    S3_SERVICE_PORT=${S3_SERVICE_PORT:-8080}
    # We only ask for Swift Hash if we have enabled swift service.
    # SWIFT_HASH is a random unique string for a swift cluster that
    # can never change.
    read_password SWIFT_HASH "ENTER A RANDOM SWIFT HASH."
fi

# Set default port for nova-objectstore
S3_SERVICE_PORT=${S3_SERVICE_PORT:-3333}

# Keystone
# --------

# Service Token - Openstack components need to have an admin token
# to validate user tokens.
read_password SERVICE_TOKEN "ENTER A SERVICE_TOKEN TO USE FOR THE SERVICE ADMIN TOKEN."
# Services authenticate to Identity with servicename/SERVICE_PASSWORD
read_password SERVICE_PASSWORD "ENTER A SERVICE_PASSWORD TO USE FOR THE SERVICE AUTHENTICATION."
# Horizon currently truncates usernames and passwords at 20 characters
read_password ADMIN_PASSWORD "ENTER A PASSWORD TO USE FOR HORIZON AND KEYSTONE (20 CHARS OR LESS)."

# Set the tenant for service accounts in Keystone
SERVICE_TENANT_NAME=${SERVICE_TENANT_NAME:-service}

# Set Keystone interface configuration
KEYSTONE_API_PORT=${KEYSTONE_API_PORT:-5000}
KEYSTONE_AUTH_HOST=${KEYSTONE_AUTH_HOST:-$SERVICE_HOST}
KEYSTONE_AUTH_PORT=${KEYSTONE_AUTH_PORT:-35357}
KEYSTONE_AUTH_PROTOCOL=${KEYSTONE_AUTH_PROTOCOL:-http}
KEYSTONE_SERVICE_HOST=${KEYSTONE_SERVICE_HOST:-$SERVICE_HOST}
KEYSTONE_SERVICE_PORT=${KEYSTONE_SERVICE_PORT:-5000}
KEYSTONE_SERVICE_PROTOCOL=${KEYSTONE_SERVICE_PROTOCOL:-http}


# Horizon
# -------

# Allow overriding the default Apache user and group, default both to
# current user.
APACHE_USER=${APACHE_USER:-$USER}
APACHE_GROUP=${APACHE_GROUP:-$APACHE_USER}


# Log files
# ---------

# Set up logging for stack.sh
# Set LOGFILE to turn on logging
# We append '.xxxxxxxx' to the given name to maintain history
# where xxxxxxxx is a representation of the date the file was created
if [[ -n "$LOGFILE" || -n "$SCREEN_LOGDIR" ]]; then
    LOGDAYS=${LOGDAYS:-7}
    TIMESTAMP_FORMAT=${TIMESTAMP_FORMAT:-"%F-%H%M%S"}
    CURRENT_LOG_TIME=$(date "+$TIMESTAMP_FORMAT")
fi

if [[ -n "$LOGFILE" ]]; then
    # First clean up old log files.  Use the user-specified LOGFILE
    # as the template to search for, appending '.*' to match the date
    # we added on earlier runs.
    LOGDIR=$(dirname "$LOGFILE")
    LOGNAME=$(basename "$LOGFILE")
    mkdir -p $LOGDIR
    find $LOGDIR -maxdepth 1 -name $LOGNAME.\* -mtime +$LOGDAYS -exec rm {} \;

    LOGFILE=$LOGFILE.${CURRENT_LOG_TIME}
    # Redirect stdout/stderr to tee to write the log file
    exec 1> >( tee "${LOGFILE}" ) 2>&1
    echo "stack.sh log $LOGFILE"
    # Specified logfile name always links to the most recent log
    ln -sf $LOGFILE $LOGDIR/$LOGNAME
fi

# Set up logging of screen windows
# Set SCREEN_LOGDIR to turn on logging of screen windows to the
# directory specified in SCREEN_LOGDIR, we will log to the the file
# screen-$SERVICE_NAME-$TIMESTAMP.log in that dir and have a link
# screen-$SERVICE_NAME.log to the latest log file.
# Logs are kept for as long specified in LOGDAYS.
if [[ -n "$SCREEN_LOGDIR" ]]; then

    # We make sure the directory is created.
    if [[ -d "$SCREEN_LOGDIR" ]]; then
        # We cleanup the old logs
        find $SCREEN_LOGDIR -maxdepth 1 -name screen-\*.log -mtime +$LOGDAYS -exec rm {} \;
    else
        mkdir -p $SCREEN_LOGDIR
    fi
fi

# So that errors don't compound we exit on any errors so you see only the
# first error that occurred.
trap failed ERR
failed() {
    local r=$?
    set +o xtrace
    [ -n "$LOGFILE" ] && echo "${0##*/} failed: full log in $LOGFILE"
    exit $r
}

# Print the commands being run so that we can see the command that triggers
# an error.  It is also useful for following along as the install occurs.
set -o xtrace


# Syslog
# ------

if [[ $SYSLOG != "False" ]]; then
    install_package rsyslog-relp
    if [[ "$SYSLOG_HOST" = "$HOST_IP" ]]; then
        # Configure the master host to receive
        cat <<EOF >/tmp/90-stack-m.conf
\$ModLoad imrelp
\$InputRELPServerRun $SYSLOG_PORT
EOF
        sudo mv /tmp/90-stack-m.conf /etc/rsyslog.d
    else
        # Set rsyslog to send to remote host
        cat <<EOF >/tmp/90-stack-s.conf
*.*		:omrelp:$SYSLOG_HOST:$SYSLOG_PORT
EOF
        sudo mv /tmp/90-stack-s.conf /etc/rsyslog.d
    fi
    restart_service rsyslog
fi


# Rabbit
# ------

if is_service_enabled rabbit; then
    sudo /etc/init.d/rabbitmq-server restart
fi


# Mysql
# -----

if is_service_enabled mysql; then

    restart_service mysql
fi

if [ -z "$SCREEN_HARDSTATUS" ]; then
    SCREEN_HARDSTATUS='%{= .} %-Lw%{= .}%> %n%f %t*%{= .}%+Lw%< %-=%{g}(%{d}%H/%l%{g})'
fi

# Our screenrc file builder
function screen_rc {
    SCREENRC=$TOP_DIR/stack-screenrc
    if [[ ! -e $SCREENRC ]]; then
        # Name the screen session
        echo "sessionname stack" > $SCREENRC
        # Set a reasonable statusbar
        echo "hardstatus alwayslastline '$SCREEN_HARDSTATUS'" >> $SCREENRC
        echo "screen -t stack bash" >> $SCREENRC
    fi
    # If this service doesn't already exist in the screenrc file
    if ! grep $1 $SCREENRC 2>&1 > /dev/null; then
        NL=`echo -ne '\015'`
        echo "screen -t $1 bash" >> $SCREENRC
        echo "stuff \"$2$NL\"" >> $SCREENRC
    fi
}

# Our screen helper to launch a service in a hidden named screen
function screen_it {
    NL=`echo -ne '\015'`
    if is_service_enabled $1; then
        # Append the service to the screen rc file
        screen_rc "$1" "$2"

        screen -S stack -X screen -t $1
        # sleep to allow bash to be ready to be send the command - we are
        # creating a new window in screen and then sends characters, so if
        # bash isn't running by the time we send the command, nothing happens
        sleep 3

        if [[ -n ${SCREEN_LOGDIR} ]]; then
            screen -S stack -p $1 -X logfile ${SCREEN_LOGDIR}/screen-${1}.${CURRENT_LOG_TIME}.log
            screen -S stack -p $1 -X log on
            ln -sf ${SCREEN_LOGDIR}/screen-${1}.${CURRENT_LOG_TIME}.log ${SCREEN_LOGDIR}/screen-${1}.log
        fi
        screen -S stack -p $1 -X stuff "$2$NL"
    fi
}

# create a new named screen to run processes in
screen -d -m -S stack -t stack -s /bin/bash
sleep 1
# set a reasonable statusbar
screen -r stack -X hardstatus alwayslastline "$SCREEN_HARDSTATUS"

# Horizon
# -------

# Setup the django horizon application to serve via apache/wsgi

if is_service_enabled horizon; then
    restart_service apache2
fi


# Glance
# ------

if is_service_enabled g-reg; then
    GLANCE_CONF_DIR=/etc/glance

    GLANCE_IMAGE_DIR=$DEST/glance/images

    GLANCE_REGISTRY_CONF=$GLANCE_CONF_DIR/glance-registry.conf

    GLANCE_REGISTRY_PASTE_INI=$GLANCE_CONF_DIR/glance-registry-paste.ini

    GLANCE_API_CONF=$GLANCE_CONF_DIR/glance-api.conf

    GLANCE_API_PASTE_INI=$GLANCE_CONF_DIR/glance-api-paste.ini

fi


# Nova
# ----

# Put config files in /etc/nova for everyone to find
NOVA_CONF_DIR=/etc/nova
NOVA_CONF=nova.conf

if is_service_enabled n-cpu; then

    restart_service libvirt-bin

fi

# Volume Service
# --------------

if is_service_enabled n-vol; then
    if ! sudo vgs $VOLUME_GROUP; then
        VOLUME_BACKING_FILE=${VOLUME_BACKING_FILE:-$DEST/nova-volumes-backing-file}
        if [ -f $VOLUME_BACKING_FILE ]; then 
            sudo losetup -f --show $VOLUME_BACKING_FILE 
        fi
    fi


    sudo stop tgt || true
    sudo start tgt
fi

# Provide some transition from EXTRA_FLAGS to EXTRA_OPTS
if [[ -z "$EXTRA_OPTS" && -n "$EXTRA_FLAGS" ]]; then
    EXTRA_OPTS=$EXTRA_FLAGS
fi


# Launch Services
# ===============

# nova api crashes if we start it with a regular screen command,
# so send the start command by forcing text into the window.
# Only run the services specified in ``ENABLED_SERVICES``

# launch the glance registry service
if is_service_enabled g-reg; then
    screen_it g-reg "cd $GLANCE_DIR; bin/glance-registry --config-file=$GLANCE_CONF_DIR/glance-registry.conf"
fi

# launch the glance api and wait for it to answer before continuing
if is_service_enabled g-api; then
    screen_it g-api "cd $GLANCE_DIR; bin/glance-api --config-file=$GLANCE_CONF_DIR/glance-api.conf"
    echo "Waiting for g-api ($GLANCE_HOSTPORT) to start..."
    if ! timeout $SERVICE_TIMEOUT sh -c "while ! http_proxy= wget -q -O- http://$GLANCE_HOSTPORT; do sleep 1; done"; then
      echo "g-api did not start"
      exit 1
    fi
fi

if is_service_enabled key; then

    KEYSTONE_CONF_DIR=${KEYSTONE_CONF_DIR:-/etc/keystone}
    KEYSTONE_CONF=$KEYSTONE_CONF_DIR/keystone.conf
    KEYSTONE_CATALOG=$KEYSTONE_CONF_DIR/default_catalog.templates


    # launch keystone and wait for it to answer before continuing
    screen_it key "cd $KEYSTONE_DIR && $KEYSTONE_DIR/bin/keystone-all --config-file $KEYSTONE_CONF $KEYSTONE_LOG_CONFIG -d --debug"
    echo "Waiting for keystone to start..."
    if ! timeout $SERVICE_TIMEOUT sh -c "while http_proxy= wget -O- $KEYSTONE_AUTH_PROTOCOL://$SERVICE_HOST:$KEYSTONE_API_PORT/v2.0/ 2>&1 | grep -q 'refused'; do sleep 1; done"; then
      echo "keystone did not start"
      exit 1
    fi
fi

# launch the nova-api and wait for it to answer before continuing
if is_service_enabled n-api; then
    screen_it n-api "cd $NOVA_DIR && $NOVA_DIR/bin/nova-api"
    echo "Waiting for nova-api to start..."
    if ! timeout $SERVICE_TIMEOUT sh -c "while ! http_proxy= wget -q -O- http://127.0.0.1:8774; do sleep 1; done"; then
      echo "nova-api did not start"
      exit 1
    fi
fi


# Launching nova-compute should be as simple as running ``nova-compute`` but
# have to do a little more than that in our script.  Since we add the group
# ``libvirtd`` to our user in this script, when nova-compute is run it is
# within the context of our original shell (so our groups won't be updated).
# Use 'sg' to execute nova-compute as a member of the libvirtd group.
# We don't check for is_service_enable as screen_it does it for us

screen_it n-crt "cd $NOVA_DIR && $NOVA_DIR/bin/nova-cert"
screen_it n-vol "cd $NOVA_DIR && $NOVA_DIR/bin/nova-volume"
screen_it n-net "cd $NOVA_DIR && $NOVA_DIR/bin/nova-network"
screen_it n-sch "cd $NOVA_DIR && $NOVA_DIR/bin/nova-scheduler"
screen_it n-novnc "cd $NOVNC_DIR && ./utils/nova-novncproxy --config-file $NOVA_CONF_DIR/$NOVA_CONF --web ."
screen_it n-xvnc "cd $NOVA_DIR && ./bin/nova-xvpvncproxy --config-file $NOVA_CONF_DIR/$NOVA_CONF"
screen_it n-cauth "cd $NOVA_DIR && ./bin/nova-consoleauth"
screen_it horizon "cd $HORIZON_DIR && sudo tail -f /var/log/apache2/error.log"
screen_it swift "cd $SWIFT_DIR && $SWIFT_DIR/bin/swift-proxy-server ${SWIFT_CONFIG_DIR}/proxy-server.conf -v"
screen_it n-cpu "cd $NOVA_DIR && sg libvirtd $NOVA_DIR/bin/nova-compute"
#Login iscsi

if [[ -x $TOP_DIR/iscsi_login.sh ]]; then

    $TOP_DIR/iscsi_login.sh

fi

# Run local script
# ================

# Run ``local.sh`` if it exists to perform user-managed tasks
if [[ -x $TOP_DIR/local.sh ]]; then
    echo "Running user script $TOP_DIR/local.sh"
    $TOP_DIR/local.sh
fi


# Fin
# ===

set +o xtrace


# Using the cloud
# ===============

echo ""
echo ""
echo ""

# If you installed Horizon on this server you should be able
# to access the site using your browser.
if is_service_enabled horizon; then
    echo "Horizon is now available at http://$SERVICE_HOST/"
fi

# If Keystone is present you can point ``nova`` cli to this server
if is_service_enabled key; then
    echo "Keystone is serving at $KEYSTONE_AUTH_PROTOCOL://$SERVICE_HOST:$KEYSTONE_API_PORT/v2.0/"
    echo "Examples on using novaclient command line is in exercise.sh"
    echo "The default users are: admin and demo"
    echo "The password: $ADMIN_PASSWORD"
fi

# Echo HOST_IP - useful for build_uec.sh, which uses dhcp to give the instance an address
echo "This is your host ip: $HOST_IP"

# Warn that ``EXTRA_FLAGS`` needs to be converted to ``EXTRA_OPTS``
if [[ -n "$EXTRA_FLAGS" ]]; then
    echo "WARNING: EXTRA_FLAGS is defined and may need to be converted to EXTRA_OPTS"
fi

sudo mount -t nfs4 -o noatime $SERVICE_HOST:/ /opt/stack/nova/instances

# Indicate how long this took to run (bash maintained variable 'SECONDS')
echo "stack.sh completed in $SECONDS seconds."
(cd /home/xeven && ./libvirt_restart.py)
