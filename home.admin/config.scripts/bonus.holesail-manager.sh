#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "Config script to manage Holesail port forwarding. See: https://docs.holesail.io/"
  echo "bonus.holesail-manager.sh [on|off]"
  echo "bonus.holesail-manager.sh menu"
  echo "bonus.holesail-manager.sh list"
  echo "bonus.holesail-manager.sh add [clrest|lndrest|electrs|fulcrum]"
  echo "bonus.holesail-manager.sh remove [clrest|lndrest|electrs|fulcrum]"
  exit 1
fi

# check and load raspiblitz config

RASPIBLITZ_CONF=/mnt/hdd/raspiblitz.conf
HOLESAIL_MIN_NODE_VERSION="20"

source $RASPIBLITZ_CONF



# Installation function
function install() {
  echo "# Installing Holesail..."

  # Check if Node.js and npm are installed
  if ! command -v node > /dev/null || ! command -v npm > /dev/null; then
    echo "# Error: Node.js and npm are required but not installed"
    return 1
  fi

  # Check Node.js version
  NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
  if [ "${NODE_VERSION}" -lt "${HOLESAIL_MIN_NODE_VERSION}" ]; then
    echo "# Error: Node.js version ${HOLESAIL_MIN_NODE_VERSION} or higher is required"
    echo "# Current version: $(node -v)"
    return 1
  fi

  # Install Holesail globally
  echo "# Installing Holesail via npm..."
  sudo npm install -g holesail
  if [ $? -ne 0 ]; then
    echo "# Error: Failed to install Holesail"
    return 1
  fi

  # Verify installation
  _version=$(holesail --version | grep -E '^[0-9]+(\.[0-9]+)*$')
  if [ -z "${_version}" ]; then
    echo "# Error: Holesail installation verification failed"
    return 1
  fi

  # setting value in raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh set holesail on
  # TODO: do we also need to set _cache.sh here???


  echo "# Holesail installation successful"
  return 0
}

# Uninstallation function
function uninstall() {
  echo "# Uninstalling Holesail..."

  # Check if Holesail is installed
  if ! command -v holesail > /dev/null; then
    echo "# Holesail is not installed"
    return 0
  fi

  # Uninstall Holesail globally
  echo "# Removing Holesail via npm..."
  sudo npm uninstall -g holesail
  if [ $? -ne 0 ]; then
    echo "# Error: Failed to uninstall Holesail"
    return 1
  fi

  # setting value in raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh delete holesail

  # Verify uninstallation
  if command -v holesail > /dev/null; then
    echo "# Error: Holesail is still installed"
    return 1
  fi

  echo "# Holesail uninstallation successful"
  return 0
}

function createSystemdService() {
  local SERVICE=$1
  case $SERVICE in
    holesail-clrest)
      source <(/home/admin/config.scripts/network.aliases.sh getvars cl mainnet)

      # Set variables for CLnrest mainnet
      PORT=$(grep -oP '^clnrest-port=\K[0-9]+' "${CLCONF}")
      if [ -z "${PORT}" ]; then
        echo "# Error: Could not find clnrest-port in ${CLCONF}"
        exit 1
      fi

      CONNECTOR="clnrest@$(hostname)-$(uuidgen)"
      DEPENDS_ON="lightningd.service"
      ;;

    holesail-lndrest)
      PORT=8080 #TODO: look this up, instead of hardcoding
      CONNECTOR="lndrest@$(hostname)-$(uuidgen)"
      DEPENDS_ON="lnd.service"
      ;;

    holesail-electrs)
      PORT=50002 #TODO: look this up, instead of hardcoding
      CONNECTOR="electrs@$(hostname)-$(uuidgen)"
      DEPENDS_ON="bitcoind.service"
      ;;

    holesail-fulcrum)
      PORT=50022 #TODO: look this up, instead of hardcoding
      CONNECTOR="fulcrum@$(hostname)-$(uuidgen)"
      DEPENDS_ON="bitcoind.service"
      ;;

    *)
      echo "# Error: Unknown service: $SERVICE"
      return 1
      ;;
  esac

  
  echo "# Create a systemd service for $SERVICE on port $PORT"
  echo "\
[Unit]
Description=Holesail
After=network.target $DEPENDS_ON
StartLimitBurst=2
StartLimitIntervalSec=20

[Service]
ExecStart=holesail --live $PORT --connector=$CONNECTOR
KillSignal=SIGINT
User=admin
RestartSec=5
Restart=on-failure

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/$SERVICE.service

  sudo systemctl enable $SERVICE
  sudo systemctl start $SERVICE

}


function removeSystemdService() {
  local SERVICE=$1
  echo "# Removing systemd service for $SERVICE..."
  sudo systemctl disable $SERVICE
  sudo rm /etc/systemd/system/$SERVICE.service
  sudo systemctl daemon-reload
  echo "# OK - systemd service removed"
}


###############################################
# ON (installs Holesail)
###############################################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# Activating Holesail..."
  
  # Run installation
  if ! install; then
    echo "# FAIL - Holesail installation failed"
    exit 1
  fi
  
  echo "# OK - Holesail is now installed and ready"
  exit 0
fi

###############################################
# OFF (uninstalls Holesail)
###############################################
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# Deactivating Holesail..."
  
  # Run uninstallation
  if ! uninstall; then
    echo "# FAIL - Holesail uninstallation failed"
    exit 1
  fi
  
  echo "# OK - Holesail is now uninstalled"
  exit 0
fi

###############################################
# LIST (listing holesail sessions)
###############################################
if [ "$1" = "list" ]; then
  echo "Running 'sudo systemctl status holesail-*' to list all Holesail sessions:"
  sudo systemctl status holesail-*
  exit 0
fi

###############################################
# ADD (adds a new holesail session)
###############################################
if [ "$1" = "add" ]; then
  if [ -z "$2" ]; then
    echo "# Error: Service parameter is required"
    exit 1
  fi
  
  if [[ "$2" != holesail-* ]]; then
    SERVICE="holesail-$2"
  else
    SERVICE="$2"
  fi

  if [ -f "/etc/systemd/system/${SERVICE}.service" ]; then
    echo "# Error: Service ${SERVICE} already exists"
    exit 1
  fi

  echo "# Adding new Holesail port forwarding for ${SERVICE}..."
  createSystemdService "$SERVICE"
  echo "Success. Run 'sudo journalctl -u ${SERVICE}' to see connect string and QR code"
  exit 0
fi

###############################################
# REMOVE (removes a holesail session)
###############################################
if [ "$1" = "remove" ]; then
  if [ -z "$2" ]; then
    echo "# Error: Service parameter is required"
    exit 1
  fi

  if [[ "$2" != holesail-* ]]; then
    SERVICE="holesail-$2"
  else
    SERVICE="$2"
  fi

  if [ ! -f "/etc/systemd/system/${SERVICE}.service" ]; then
    echo "# Error: Service ${SERVICE} does not exist"
    exit 1
  fi

  echo "# Removing Holesail port forwarding for ${SERVICE}..."
  removeSystemdService "${SERVICE}"
  exit 0
fi



###############################################
# MENU (shows menu)  ---NOT working yet!!!
###############################################
if [ "$1" = "menu" ]; then

  echo "services default values"
  if [ ${#holesail-clrest} -eq 0 ]; then holesail-clrest="off"; fi
  if [ ${#holesail-lndrest} -eq 0 ]; then holesail-lndrest="off"; fi
  if [ ${#holesail-electrs} -eq 0 ]; then holesail-electrs="off"; fi
  if [ ${#holesail-fulcrum} -eq 0 ]; then holesail-fulcrum="off"; fi


  OPTIONS=()
  # Check if any supported services are enabled
  if [ "${holesail-electrs}" == "on" ]; then
    OPTIONS+=(rs 'BTC Electrum Rust Server' ${holesail-electrs})
  fi
  if [ "${holesail-fulcrum}" == "on" ]; then
    OPTIONS+=(fu 'Fulcrum Server' ${holesail-fulcrum})
  fi

  if [ "${holesail-elements}" == "on" ]; then
    OPTIONS+=(lq 'Elements/Liquid' ${holesail-elements})
  fi

  if [ "${holesail-lndrest}" == "on" ]; then
    OPTIONS+=(ln "LND REST API" ${holesail-lndrest})
  fi

  if [ "${holesail-clrest}" == "on" ]; then
    OPTIONS+=(cl "CLN REST API" ${holesail-clrest})
  fi

  if [ ${#OPTIONS[@]} -eq 0 ]; then
    echo "# Error: No supported services are enabled"
    exit 1
  fi


  # Menu options using whiptail
  HEIGHT=15
  WIDTH=60
  CHOICE=$(whiptail --title "Holesail Manager" --menu "Choose an option:" $HEIGHT $WIDTH 4 \
      "LIST" "List all running holsail services" \
      "ADD/REMOVE" "Add or remove a holesail service" 3>&1 1>&2 2>&3)

      case $CHOICE in
          "LIST")
              /home/admin/config.scripts/bonus.holesail-manager.sh list
              ;;
          "ADD/REMOVE")
              # Menu options using whiptail
              CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
              HEIGHT=$((CHOICE_HEIGHT+7))
              CHOICE=$(dialog --clear \
                              --title "Holesail Manager" \
                              --checklist "Use spacebar to activate/de-activate" \
                              $HEIGHT 55 20  \
                              "${OPTIONS[@]}" \
                              2>&1 >/dev/tty)
              dialogcancel=$?
              echo "done dialog"
              clear

              # check if user canceled dialog
              if [ ${dialogcancel} -eq 1 ]; then
                echo "user canceled"
                exit 0
              fi

              # loop through all options
              for i in $(seq 0 $((${#OPTIONS[@]}/2-1))); do
                option=${OPTIONS[$i*2]}
                value=${OPTIONS[$i*2+1]}
                if [[ $CHOICE =~ $option ]]; then
                  # enable
                  echo "Enabling $option"
                  /home/admin/config.scripts/bonus.holesail-manager.sh add $option
                else
                  # disable
                  echo "Disabling $option"
                  /home/admin/config.scripts/bonus.holesail-manager.sh remove $option
                fi
              done
              ;;
      esac
      ;;
  exit 0
fi