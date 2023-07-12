#!/bin/bash

# Send an encrypted version of your NEMS Migrator backup file to the offsite backup service.
# This only happens if you enable it.
# Learn more about how to enable the offsite backup service at https://docs.nemslinux.com/en/latest/nems-cloud-services/nems-migrator.html

# Load Config
hwid=`/usr/local/bin/nems-info hwid`
osbpass=$(cat /usr/local/share/nems/nems.conf | grep osbpass | printf '%s' $(cut -n -d '=' -f 2))
osbkey=$(cat /usr/local/share/nems/nems.conf | grep osbkey | printf '%s' $(cut -n -d '=' -f 2))
timestamp=$(/bin/date +%s)

if [[ $osbpass == '' ]] || [[ $osbkey == '' ]]; then
  echo NEMS Migrator Offsite Backup is not currently enabled.
  exit
fi;

# Check account status
cloudauth=$(/usr/local/bin/nems-info cloudauth)
if [[ $cloudauth == '1' ]]; then # this account passes authentication

if pidof -o %PPID -x "backup.sh">/dev/null; then
    echo "Standby... backup is running."
    sleep 5
    v=0
    while pidof -o %PPID -x "backup.sh">/dev/null
    do
      v=$(($v+1))
      if [[ $v -ge 120 ]]; then
        echo "It has been 10 minutes and backup is still running. Aborted."
        exit 1
      fi
      sleep 5
    done
fi

  # Cron triggers this at midnight
  # Sleep for a random time up to 4 hours to stagger user backups to relieve stress on the API server
  if [[ $1 != 'now' ]]; then
    delay=$[ ( $RANDOM % 14400 ) ]
    echo "Waiting $delay seconds" >&2
    sleep ${delay}s
    echo "Running OSB" >&2
  else
    echo "Running OSB now" >&2
  fi

  # Encrypt the file
  # Combine the user's passphrase with the OSB Key to further strenghten the entropy of the passphrase
  gpg --yes --batch --passphrase="::$osbpass::$osbkey::" -c /var/www/html/backup/snapshot/backup.nems

  # Upload the file
  data=$(curl -s -F "hwid=$hwid" -F "osbkey=$osbkey" -F "timestamp=$timestamp" -F "backup=@/var/www/html/backup/snapshot/backup.nems.gpg" https://cloud.nemslinux.com/api/offsite-backup.php)

  # Delete the local file
  rm /var/www/html/backup/snapshot/backup.nems.gpg

  # Parse the response
  datarr=($data)
  response="${datarr[0]}"
  date="${datarr[1]}"
  size="${datarr[2]}"
  usage="${datarr[3]}"
  retained="${datarr[4]}"

  online=`/usr/local/bin/nems-info online`

  if [[ $response == 1 ]]; then
    echo "`date`::1::Success::File was accepted::$date::$size::$usage::$retained" >> /var/log/nems/nems-osb.log
    if [[ $1 != 'now' ]]; then
      /usr/local/share/nems/nems-scripts/osb-stats.sh now
    fi
  elif [[ $response == 0 ]]; then
    echo "`date`::2::Failed::Upload failed" >> /var/log/nems/nems-osb.log
  elif [[ $response == 2 ]]; then
    echo "`date`::2::Failed::File permissions issue on receiving server" >> /var/log/nems/nems-osb.log
  elif [[ $response == 3 ]]; then
    echo "`date`::2::Failed::Could not access authentication service" >> /var/log/nems/nems-osb.log
  elif [[ $response == 4 ]]; then
    echo "`date`::2::Failed::Invalid credentials" >> /var/log/nems/nems-osb.log
  elif [[ $response == 5 ]]; then
    echo "`date`::2::Failed::Bad query" >> /var/log/nems/nems-osb.log
  elif [[ $online == 0 ]]; then
    echo "`date`::2::Failed::No Internet Connection" >> /var/log/nems/nems-osb.log
  elif [[ $data == '' ]]; then
    echo "`date`::2::Failed::NEMS Cloud Services did not respond to query" >> /var/log/nems/nems-osb.log
  else
    echo "`date`::2::Failed::Unknown error" >> /var/log/nems/nems-osb.log # Replace code with unknown error (as it could be anything)
  fi;

elif [[ $cloudauth == '3' ]]; then # this account passes authentication
    echo "`date`::2::Failed::No Internet Connection" >> /var/log/nems/nems-osb.log
else
    echo "`date`::2::Failed::Authentication Failed" >> /var/log/nems/nems-osb.log
fi
