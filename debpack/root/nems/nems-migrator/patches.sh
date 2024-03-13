#!/bin/bash
# This file is a failsafe patch to supplement fixes.sh
# If something happens to break nems-scripts, I can use this file to patch it
# since it gets called from a different git repository

# Because this script gets called by backup.sh, it will run every 5 minutes.

# Don't allow the script to run if it's already running. May occur if your logs or config tak$
if pidof -o %PPID -x "`basename "$0"`">/dev/null; then
    echo "Process already running"
    exit
fi


if [[ $EUID -ne 0 ]]; then
  echo "ERROR: You must be a root" 2>&1
  exit 1
else

  ver=$(/usr/local/bin/nems-info nemsver)

  if (( $(awk 'BEGIN {print ("'$ver'" >= "'1.6'")}') )); then

    # Update nems-scripts if nems-update lacks the ability to override config files programmatically
    # In the first release of NEMS Linux 1.6, some config files had to be modified, such as monit's config.
    # Because of this, if a user wasn't actively interacting with nems-update, it would prompt to replace the
    # file and never finish (resulting in an out-of-date NEMS system).
    if ! grep -q noninteractive /usr/local/bin/nems-update; then
      export DEBIAN_FRONTEND=noninteractive
      apt update
      apt-get install -y nems-scripts
    fi

  fi

fi;


# This is ONLY a failsafe: If quickfix has been running > 120 minutes, it's pretty apparent something is wrong, so do a git pull in case a patch has been issued
quickfix=`/usr/local/bin/nems-info quickfix`
if [[ $quickfix == 1 ]]; then
  if [[ $(find "/var/run/nems-quickfix.pid" -mmin +120 -print) ]]; then
    kill `cat /var/run/nems-quickfix.pid` && rm /var/run/nems-quickfix.pid
    cd /usr/local/share/nems/nems-scripts && git pull
  fi
fi
# Do the same for fixes
fixes=`/usr/local/bin/nems-info fixes`
if [[ $fixes == 1 ]]; then
  if [[ $(find "/var/run/nems-fixes.pid" -mmin +120 -print) ]]; then
    kill `cat /var/run/nems-fixes.pid` && rm /var/run/nems-fixes.pid
    cd /usr/local/share/nems/nems-scripts && git pull
  fi
fi
