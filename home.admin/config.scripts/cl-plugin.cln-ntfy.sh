#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install the cln-ntfy plugin for Core Lightning"
  echo "Usage:"
  echo "cl-plugin.cln-ntfy.sh [on|off] <testnet|mainnet|signet> <ntfy_url> <ntfy_username:"ntfy_password"  ('!' must be quoted with a backslash) >"
  echo
  exit 1
fi

if [ -n "$3" ]; then
  NTFY_URL="$3"
else
  NTFY_URL="https://ntfy.sh/"
fi

NTFY_TOPIC="$(hostname)-cln-alerts"

if [ -n "$4" ]; then
  IFS=: read -r NTFY_USERNAME NTFY_PASSWORD <<< "$4"
  if [ -n "$NTFY_USERNAME" ] && [ -n "$NTFY_PASSWORD" ]; then
    echo "Setting ntfy username and password to $NTFY_USERNAME and $(printf '%0.s*' ${#NTFY_PASSWORD})"
  else
    echo "ERROR: Optional fourth argument must be in the format of username:password" 1>&2
    exit 1
  fi
else
  echo "No ntfy username and password provided, using default values (None)"
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)
plugin="cln-ntfy"


function buildFromSource() {

  # dependencies
  echo "# rust for ${plugin}, includes rustfmt"
  sudo -u bitcoin curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sudo -u bitcoin sh -s -- -y


  # download
  cd /home/bitcoin/cl-plugins-available/ || exit 1
  sudo -u bitcoin git clone https://github.com/yukibtc/cln-ntfy
  cd cln-ntfy || exit 1

  # build
  sudo -u bitcoin /home/bitcoin/.cargo/bin/cargo build --locked --release || exit 1
}


if [ "$1" = "on" ];then

  if [ ! -f "/home/bitcoin/cl-plugins-available/${plugin}" ]; then
    buildFromSource
  fi

  if [ ! -L /home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}/ ];then
    sudo ln -s /home/bitcoin/cl-plugins-available/${plugin}/target/release/${plugin} \
               /home/bitcoin/${netprefix}cl-plugins-enabled
  fi

  # setting values in cln config  
  echo "ntfy-url=${NTFY_URL}" | sudo tee -a "${CLCONF}" >/dev/null
  echo "ntfy-topic=${NTFY_TOPIC}" | sudo tee -a "${CLCONF}" >/dev/null
  echo "ntfy-username=${NTFY_USERNAME}" | sudo tee -a "${CLCONF}" >/dev/null
  echo "ntfy-password=${NTFY_PASSWORD}" | sudo tee -a "${CLCONF}" >/dev/null


  # setting value in raspiblitz config
  #/home/admin/config.scripts/blitz.conf.sh set "ntfy-url" "${NTFY_URL}" "noquotes"
  #/home/admin/config.scripts/blitz.conf.sh set "ntfy-topic" "${NTFY_TOPIC}" "noquotes"  

  #if [ -n "$NTFY_USERNAME" ] && [ -n "$NTFY_PASSWORD" ] ; then
  #  /home/admin/config.scripts/blitz.conf.sh set "ntfy-username" "${NTFY_USERNAME}" "noquotes"
  #  /home/admin/config.scripts/blitz.conf.sh set "ntfy-password" "${NTFY_PASSWORD}"
  #fi


  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}${plugin} "on"

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    echo "# Restarting ${netprefix}lightningd to activate"
    sudo systemctl restart ${netprefix}lightningd

    #echo "# Start ${netprefix}${plugin}"
    #$lightningcli_alias plugin start /home/bitcoin/cl-plugins-enabled/${plugin}
  fi

fi

if [ "$1" = "off" ];then

  echo "Stop the ${plugin}"
  $lightningcli_alias plugin stop home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}

  echo "# delete symlink"
  sudo rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}
  
  echo "# Edit ${CLCONF}"
  sudo sed -i "/^ntfy/d" ${CLCONF}

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}${plugin} "off"

  echo "# Restarting ${netprefix}lightningd to deactivate"
  sudo systemctl restart ${netprefix}lightningd


  # purge
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ]; then
    echo "# Delete plugin"
    sudo rm -rf /home/bitcoin/cl-plugins-available/${plugin}
  fi


  echo "# The ${plugin} was uninstalled"
fi