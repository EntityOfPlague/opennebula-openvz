#!/bin/bash

ONE_LOCATION=$1

function usage {
    echo "usage: $0 if OpenNebula is installed system-wide"
    echo "usage: $0 ONE_LOCATION if OpenNebula is installed in a directory"
}

if [ -z "$ONE_LOCATION" ]; then
  if [ ! -e "/usr/bin/oned" ]; then
    echo "Could not find OpenNebula executables installed system wide"
    usage
    exit 1
  fi
  VAR_LOCATION="/var/lib/one"
  ETC_LOCATION="/etc/one"
elif [ ! -e "$ONE_LOCATION/bin/oned" ]; then
  echo "Could not find OpenNebula in specified directory $ONE_LOCATION"
  echo "Check whether main program $ONE_LOCATION/bin/oned really exists"
  usage
  exit 2
else
  VAR_LOCATION="$ONE_LOCATION/var"
  ETC_LOCATION="$ONE_LOCATION/etc"
fi

patch $VAR_LOCATION/remotes/tm/shared/clone ./var/remotes/tm/shared/clone.patch
patch $VAR_LOCATION/remotes/tm/shared/mkimage ./var/remotes/tm/shared/mkimage.patch
patch $VAR_LOCATION/remotes/tm/shared/delete ./var/remotes/tm/shared/delete.patch

patch $VAR_LOCATION/remotes/tm/ssh/delete ./var/remotes/tm/ssh/delete.patch

cp ./etc/vmm_exec/vmm_exec_ovz.conf $ETC_LOCATION/vmm_exec/vmm_exec_ovz.conf

mkdir -p $VAR_LOCATION/remotes/im/ovz.d
cp ./var/remotes/im/ovz.d/* $VAR_LOCATION/remotes/im/ovz.d

mkdir -p $VAR_LOCATION/remotes/vmm/ovz
cp ./var/remotes/vmm/ovz/* $VAR_LOCATION/remotes/vmm/ovz

rm -rf /var/tmp/one

