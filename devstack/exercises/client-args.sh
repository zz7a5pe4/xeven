#!/usr/bin/env bash

# Test OpenStack client authentication aguemnts handling

echo "*********************************************************************"
echo "Begin DevStack Exercise: $0"
echo "*********************************************************************"

# Settings
# ========

# Keep track of the current directory
EXERCISE_DIR=$(cd $(dirname "$0") && pwd)
TOP_DIR=$(cd $EXERCISE_DIR/..; pwd)

# Import common functions
source $TOP_DIR/functions

# Import configuration
source $TOP_DIR/openrc

# Import exercise configuration
source $TOP_DIR/exerciserc

# Unset all of the known NOVA_ vars
unset NOVA_API_KEY
unset NOVA_ENDPOINT_NAME
unset NOVA_PASSWORD
unset NOVA_PROJECT_ID
unset NOVA_REGION_NAME
unset NOVA_URL
unset NOVA_USERNAME
unset NOVA_VERSION

# Save the known variables for later
export x_TENANT_NAME=$OS_TENANT_NAME
export x_USERNAME=$OS_USERNAME
export x_PASSWORD=$OS_PASSWORD
export x_AUTH_URL=$OS_AUTH_URL

#Unset the usual variables to force argument processing
unset OS_TENANT_NAME
unset OS_USERNAME
unset OS_PASSWORD
unset OS_AUTH_URL

# Common authentication args
TENANT_ARG="--os_tenant_name=$x_TENANT_NAME"
ARGS="--os_username=$x_USERNAME --os_password=$x_PASSWORD --os_auth_url=$x_AUTH_URL"

# Set global return
RETURN=0

# Keystone client
# ---------------
if [[ "$ENABLED_SERVICES" =~ "key" ]]; then
    if [[ "$SKIP_EXERCISES" =~ "key" ]] ; then
        STATUS_KEYSTONE="Skipped"
    else
        echo -e "\nTest Keystone"
        if keystone $TENANT_ARG $ARGS catalog --service identity; then
            STATUS_KEYSTONE="Succeeded"
        else
            STATUS_KEYSTONE="Failed"
            RETURN=1
        fi
    fi
fi

# Nova client
# -----------

if [[ "$ENABLED_SERVICES" =~ "n-api" ]]; then
    if [[ "$SKIP_EXERCISES" =~ "n-api" ]] ; then
        STATUS_NOVA="Skipped"
        STATUS_EC2="Skipped"
    else
        # Test OSAPI
        echo -e "\nTest Nova"
        if nova $TENANT_ARG $ARGS flavor-list; then
            STATUS_NOVA="Succeeded"
        else
            STATUS_NOVA="Failed"
            RETURN=1
        fi
    fi
fi

# Glance client
# -------------

if [[ "$ENABLED_SERVICES" =~ "g-api" ]]; then
    if [[ "$SKIP_EXERCISES" =~ "g-api" ]] ; then
        STATUS_GLANCE="Skipped"
    else
        echo -e "\nTest Glance"
        if glance $TENANT_ARG $ARGS index; then
            STATUS_GLANCE="Succeeded"
        else
            STATUS_GLANCE="Failed"
            RETURN=1
        fi
    fi
fi

# Swift client
# ------------

if [[ "$ENABLED_SERVICES" =~ "swift" ]]; then
    if [[ "$SKIP_EXERCISES" =~ "swift" ]] ; then
        STATUS_SWIFT="Skipped"
    else
        echo -e "\nTest Swift"
        if swift $ARGS stat; then
            STATUS_SWIFT="Succeeded"
        else
            STATUS_SWIFT="Failed"
            RETURN=1
        fi
    fi
fi

# Results
# -------

function report() {
    if [[ -n "$2" ]]; then
        echo "$1: $2"
    fi
}

echo -e "\n"
report "Keystone" $STATUS_KEYSTONE
report "Nova" $STATUS_NOVA
report "Glance" $STATUS_GLANCE
report "Swift" $STATUS_SWIFT

echo "*********************************************************************"
echo "SUCCESS: End DevStack Exercise: $0"
echo "*********************************************************************"

exit $RETURN
