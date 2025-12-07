#!/bin/bash

# Holesail Manager for RaspiBlitz
# Holesail is a peer-to-peer tunneling solution that allows you to expose local services
# to the internet without port forwarding, static IPs, or complex configurations.
# See: https://docs.holesail.io/

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "Config script to manage Holesail port forwarding. See: https://docs.holesail.io/"
  echo "bonus.holesail-manager.sh [on|off]              # Install/uninstall holesail"
  echo "bonus.holesail-manager.sh menu                  # Interactive menu"
  echo "bonus.holesail-manager.sh status                # Show status of all holesail services"
  echo "bonus.holesail-manager.sh add <service>         # Enable holesail for service"
  echo "bonus.holesail-manager.sh remove <service>      # Disable holesail for service"
  echo "bonus.holesail-manager.sh connect <service>     # Show connection info for service"
  echo ""
  echo "Supported services: clnrest, lndrest, electrs, fulcrum"
  exit 1
fi

# check and load raspiblitz config
RASPIBLITZ_CONF=/mnt/hdd/app-data/raspiblitz.conf
HOLESAIL_MIN_NODE_VERSION="20"
HOLESAIL_DATA_DIR="/mnt/hdd/app-data/holesail"

if [ -f "${RASPIBLITZ_CONF}" ]; then
  source "${RASPIBLITZ_CONF}"
fi

# also source raspiblitz.info for state info
if [ -f /home/admin/raspiblitz.info ]; then
  source /home/admin/raspiblitz.info
fi

###############################################
# HELPER FUNCTIONS
###############################################

# Get the port for a given service
function getServicePort() {
  local SERVICE=$1
  local PORT=""
  
  case $SERVICE in
    clnrest)
      # Get CLNrest port from config (default 7378 for mainnet)
      source <(/home/admin/config.scripts/network.aliases.sh getvars cl mainnet 2>/dev/null)
      if [ -n "${CLCONF}" ] && [ -f "${CLCONF}" ]; then
        PORT=$(grep -oP '^clnrest-port=\K[0-9]+' "${CLCONF}" 2>/dev/null)
      fi
      # Default port if not found
      [ -z "${PORT}" ] && PORT="7378"
      ;;
    lndrest)
      # LND REST port (default 8080 for mainnet)
      PORT="8080"
      ;;
    electrs)
      # Electrs SSL port
      PORT="50002"
      ;;
    fulcrum)
      # Fulcrum SSL port
      PORT="50022"
      ;;
    *)
      echo ""
      return 1
      ;;
  esac
  
  echo "${PORT}"
}

# Get the systemd dependency for a service
function getServiceDependency() {
  local SERVICE=$1
  
  case $SERVICE in
    clnrest)
      echo "lightningd.service"
      ;;
    lndrest)
      echo "lnd.service"
      ;;
    electrs)
      echo "electrs.service"
      ;;
    fulcrum)
      echo "fulcrum.service"
      ;;
    *)
      echo "bitcoind.service"
      ;;
  esac
}

# Check if a service is available on the system
function isServiceAvailable() {
  local SERVICE=$1
  
  case $SERVICE in
    clnrest)
      [ "${cl}" == "on" ] && return 0
      ;;
    lndrest)
      [ "${lnd}" == "on" ] && return 0
      ;;
    electrs)
      [ "${ElectRS}" == "on" ] && return 0
      ;;
    fulcrum)
      [ "${fulcrum}" == "on" ] && return 0
      ;;
  esac
  return 1
}

# Check if holesail is enabled for a service
function isHolesailEnabled() {
  local SERVICE=$1
  [ -f "/etc/systemd/system/holesail-${SERVICE}.service" ] && return 0
  return 1
}

# Get the connector string for a service
function getConnector() {
  local SERVICE=$1
  local CONNECTOR_FILE="${HOLESAIL_DATA_DIR}/${SERVICE}.connector"
  
  if [ -f "${CONNECTOR_FILE}" ]; then
    cat "${CONNECTOR_FILE}"
  else
    echo ""
  fi
}

# Installation function
function install() {
  echo "# Installing Holesail..."

  # Check if Node.js and npm are installed, install if needed
  if ! command -v node > /dev/null || ! command -v npm > /dev/null; then
    echo "# Node.js and npm are required but not installed"
    echo "# Installing Node.js..."
    /home/admin/config.scripts/bonus.nodejs.sh on
    if [ $? -ne 0 ]; then
      echo "# Error: Failed to install Node.js"
      return 1
    fi
    # Verify installation
    if ! command -v node > /dev/null || ! command -v npm > /dev/null; then
      echo "# Error: Node.js installation verification failed"
      return 1
    fi
  fi

  # Install uuidgen if not available
  if ! command -v uuidgen > /dev/null; then
    echo "# Installing uuidgen..."
    sudo apt-get update
    sudo apt-get install -y uuid-runtime
    if [ $? -ne 0 ]; then
      echo "# Error: Failed to install uuidgen"
      return 1
    fi
    # Verify installation
    if ! command -v uuidgen > /dev/null; then
      echo "# Error: uuidgen installation verification failed"
      return 1
    fi
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
  _version=$(holesail --version 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+)*$')
  if [ -z "${_version}" ]; then
    echo "# Error: Holesail installation verification failed"
    return 1
  fi

  # Create data directory
  sudo mkdir -p "${HOLESAIL_DATA_DIR}"
  sudo chown admin:admin "${HOLESAIL_DATA_DIR}"

  # setting value in raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh set holesail on

  echo "# Holesail v${_version} installation successful"
  return 0
}

# Uninstallation function
function uninstall() {
  echo "# Uninstalling Holesail..."

  # Stop and remove all holesail services first
  for SERVICE in clnrest lndrest electrs fulcrum; do
    if isHolesailEnabled "${SERVICE}"; then
      echo "# Removing holesail-${SERVICE}..."
      removeSystemdService "${SERVICE}"
    fi
  done

  # Check if Holesail is installed
  if ! command -v holesail > /dev/null; then
    echo "# Holesail is not installed"
  else
    # Uninstall Holesail globally
    echo "# Removing Holesail via npm..."
    sudo npm uninstall -g holesail
  fi

  # Remove data directory
  sudo rm -rf "${HOLESAIL_DATA_DIR}"

  # setting value in raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh delete holesail

  echo "# Holesail uninstallation successful"
  return 0
}

# Create systemd service for a holesail tunnel
function createSystemdService() {
  local SERVICE=$1
  local PORT=$(getServicePort "${SERVICE}")
  local DEPENDS_ON=$(getServiceDependency "${SERVICE}")
  
  if [ -z "${PORT}" ]; then
    echo "# Error: Could not determine port for service: ${SERVICE}"
    return 1
  fi

  # Generate unique connector string: service@hostname-uuid
  local CONNECTOR="${SERVICE}@$(hostname)-$(uuidgen)"
  local SERVICE_NAME="holesail-${SERVICE}"
  local CONNECTOR_FILE="${HOLESAIL_DATA_DIR}/${SERVICE}.connector"
  
  echo "# Creating systemd service for ${SERVICE_NAME} on port ${PORT}"
  echo "# Connector: ${CONNECTOR}"
  
  # Store connector string
  sudo mkdir -p "${HOLESAIL_DATA_DIR}"
  echo "${CONNECTOR}" | sudo tee "${CONNECTOR_FILE}" > /dev/null
  sudo chown admin:admin "${CONNECTOR_FILE}"
  
  # Create systemd service file
  echo "[Unit]
Description=Holesail tunnel for ${SERVICE}
After=network.target ${DEPENDS_ON}
Wants=${DEPENDS_ON}
StartLimitBurst=5
StartLimitIntervalSec=60

[Service]
ExecStart=/usr/bin/holesail --live ${PORT} --connector=${CONNECTOR}
KillSignal=SIGINT
User=admin
RestartSec=10
Restart=on-failure

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null

  sudo systemctl daemon-reload
  sudo systemctl enable ${SERVICE_NAME}
  sudo systemctl start ${SERVICE_NAME}
  
  # Wait a moment for service to start
  sleep 2
  
  if sudo systemctl is-active --quiet ${SERVICE_NAME}; then
    echo "# OK - ${SERVICE_NAME} is running"
    echo "# Connector string: ${CONNECTOR}"
    return 0
  else
    echo "# Warning: ${SERVICE_NAME} may not have started correctly"
    echo "# Check with: sudo journalctl -u ${SERVICE_NAME}"
    return 1
  fi
}

# Remove systemd service
function removeSystemdService() {
  local SERVICE=$1
  local SERVICE_NAME="holesail-${SERVICE}"
  local CONNECTOR_FILE="${HOLESAIL_DATA_DIR}/${SERVICE}.connector"
  
  echo "# Removing systemd service for ${SERVICE_NAME}..."
  
  if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    sudo systemctl stop ${SERVICE_NAME} 2>/dev/null
    sudo systemctl disable ${SERVICE_NAME} 2>/dev/null
    sudo rm /etc/systemd/system/${SERVICE_NAME}.service
    sudo systemctl daemon-reload
  fi
  
  # Remove connector file
  sudo rm -f "${CONNECTOR_FILE}"
  
  echo "# OK - ${SERVICE_NAME} removed"
}

# Show connection info for a service
function showConnectionInfo() {
  local SERVICE=$1
  local CONNECTOR=$(getConnector "${SERVICE}")
  local PORT=$(getServicePort "${SERVICE}")
  
  if [ -z "${CONNECTOR}" ]; then
    echo "# Error: Holesail is not enabled for ${SERVICE}"
    return 1
  fi
  
  clear
  echo "=============================================="
  echo "  HOLESAIL CONNECTION INFO: ${SERVICE}"
  echo "=============================================="
  echo ""
  echo "Service: ${SERVICE}"
  echo "Local Port: ${PORT}"
  echo ""
  echo "CONNECTOR STRING (share this to connect):"
  echo "----------------------------------------------"
  echo "${CONNECTOR}"
  echo "----------------------------------------------"
  echo ""
  echo "To connect from another device, run:"
  echo "  holesail ${CONNECTOR}"
  echo ""
  echo "This will create a local proxy on the connecting device."
  echo ""
  
  # Show QR code if qrencode is available
  if command -v qrencode > /dev/null; then
    echo "QR Code:"
    qrencode -t ANSIUTF8 "${CONNECTOR}"
    echo ""
    # Also show on LCD if available
    sudo /home/admin/config.scripts/blitz.display.sh qr "${CONNECTOR}" 2>/dev/null
  fi
  
  return 0
}

###############################################
# STATUS
###############################################
if [ "$1" = "status" ]; then
  echo "# Holesail Status"
  echo ""
  
  # Check if holesail is installed
  if command -v holesail > /dev/null; then
    VERSION=$(holesail --version 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+)*$')
    echo "holesailInstalled=1"
    echo "holesailVersion='${VERSION}'"
  else
    echo "holesailInstalled=0"
  fi
  
  # Check each service
  for SERVICE in clnrest lndrest electrs fulcrum; do
    if isHolesailEnabled "${SERVICE}"; then
      CONNECTOR=$(getConnector "${SERVICE}")
      ACTIVE=$(sudo systemctl is-active holesail-${SERVICE} 2>/dev/null)
      echo "holesail_${SERVICE}='on'"
      echo "holesail_${SERVICE}_connector='${CONNECTOR}'"
      echo "holesail_${SERVICE}_active='${ACTIVE}'"
    else
      echo "holesail_${SERVICE}='off'"
    fi
  done
  
  exit 0
fi

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
  echo "# Use 'bonus.holesail-manager.sh menu' to enable tunnels for services"
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
# ADD (enables holesail for a service)
###############################################
if [ "$1" = "add" ]; then
  if [ -z "$2" ]; then
    echo "# Error: Service parameter is required"
    echo "# Usage: bonus.holesail-manager.sh add <clnrest|lndrest|electrs|fulcrum>"
    exit 1
  fi
  
  SERVICE="$2"
  # Remove holesail- prefix if present
  SERVICE="${SERVICE#holesail-}"
  
  # Check if service is valid
  if ! getServicePort "${SERVICE}" > /dev/null; then
    echo "# Error: Unknown service: ${SERVICE}"
    echo "# Supported services: clnrest, lndrest, electrs, fulcrum"
    exit 1
  fi
  
  # Check if service is available
  if ! isServiceAvailable "${SERVICE}"; then
    echo "# Error: Service ${SERVICE} is not enabled on this system"
    exit 1
  fi
  
  # Check if already enabled
  if isHolesailEnabled "${SERVICE}"; then
    echo "# Holesail is already enabled for ${SERVICE}"
    CONNECTOR=$(getConnector "${SERVICE}")
    echo "# Connector: ${CONNECTOR}"
    exit 0
  fi
  
  echo "# Adding Holesail tunnel for ${SERVICE}..."
  if createSystemdService "${SERVICE}"; then
    echo ""
    echo "# SUCCESS - Holesail tunnel created for ${SERVICE}"
    showConnectionInfo "${SERVICE}"
  else
    echo "# FAIL - Could not create Holesail tunnel for ${SERVICE}"
    exit 1
  fi
  exit 0
fi

###############################################
# REMOVE (disables holesail for a service)
###############################################
if [ "$1" = "remove" ]; then
  if [ -z "$2" ]; then
    echo "# Error: Service parameter is required"
    echo "# Usage: bonus.holesail-manager.sh remove <clnrest|lndrest|electrs|fulcrum>"
    exit 1
  fi
  
  SERVICE="$2"
  # Remove holesail- prefix if present
  SERVICE="${SERVICE#holesail-}"
  
  if ! isHolesailEnabled "${SERVICE}"; then
    echo "# Holesail is not enabled for ${SERVICE}"
    exit 0
  fi
  
  echo "# Removing Holesail tunnel for ${SERVICE}..."
  removeSystemdService "${SERVICE}"
  echo "# OK - Holesail tunnel removed for ${SERVICE}"
  exit 0
fi

###############################################
# CONNECT (shows connection info)
###############################################
if [ "$1" = "connect" ]; then
  if [ -z "$2" ]; then
    echo "# Error: Service parameter is required"
    echo "# Usage: bonus.holesail-manager.sh connect <clnrest|lndrest|electrs|fulcrum>"
    exit 1
  fi
  
  SERVICE="$2"
  # Remove holesail- prefix if present
  SERVICE="${SERVICE#holesail-}"
  
  if ! isHolesailEnabled "${SERVICE}"; then
    echo "# Error: Holesail is not enabled for ${SERVICE}"
    echo "# Enable it first with: bonus.holesail-manager.sh add ${SERVICE}"
    exit 1
  fi
  
  showConnectionInfo "${SERVICE}"
  echo ""
  echo "Press ENTER to continue..."
  read -r
  sudo /home/admin/config.scripts/blitz.display.sh hide 2>/dev/null
  exit 0
fi

###############################################
# MENU (interactive menu)
###############################################
if [ "$1" = "menu" ]; then

  # Check if holesail is installed
  if ! command -v holesail > /dev/null; then
    whiptail --title " Holesail Not Installed " --yesno "
Holesail is not installed on this system.

Holesail is a peer-to-peer tunneling solution that allows 
you to expose local services to the internet without:
- Port forwarding
- Static IP addresses
- Complex configurations

Would you like to install Holesail now?
" 15 60
    if [ $? -eq 0 ]; then
      clear
      /home/admin/config.scripts/bonus.holesail-manager.sh on
      echo ""
      echo "Press ENTER to continue..."
      read -r
    fi
    exit 0
  fi

  # Build menu options based on available services
  OPTIONS=()
  
  # CLNrest option
  if [ "${cl}" == "on" ]; then
    if isHolesailEnabled "clnrest"; then
      OPTIONS+=(CLNREST "Core Lightning REST [ENABLED]")
    else
      OPTIONS+=(CLNREST "Core Lightning REST [disabled]")
    fi
  fi
  
  # LND REST option
  if [ "${lnd}" == "on" ]; then
    if isHolesailEnabled "lndrest"; then
      OPTIONS+=(LNDREST "LND REST API [ENABLED]")
    else
      OPTIONS+=(LNDREST "LND REST API [disabled]")
    fi
  fi
  
  # Electrs option
  if [ "${ElectRS}" == "on" ]; then
    if isHolesailEnabled "electrs"; then
      OPTIONS+=(ELECTRS "Electrum Rust Server [ENABLED]")
    else
      OPTIONS+=(ELECTRS "Electrum Rust Server [disabled]")
    fi
  fi
  
  # Fulcrum option
  if [ "${fulcrum}" == "on" ]; then
    if isHolesailEnabled "fulcrum"; then
      OPTIONS+=(FULCRUM "Fulcrum Electrum Server [ENABLED]")
    else
      OPTIONS+=(FULCRUM "Fulcrum Electrum Server [disabled]")
    fi
  fi
  
  # Add status and uninstall options
  OPTIONS+=(STATUS "Show status of all tunnels")
  OPTIONS+=(UNINSTALL "Uninstall Holesail")
  
  if [ ${#OPTIONS[@]} -eq 4 ]; then
    # Only STATUS and UNINSTALL options (no services available)
    whiptail --title " No Services Available " --msgbox "
No compatible services are currently enabled on this system.

Holesail can create tunnels for:
- Core Lightning REST (CLNrest)
- LND REST API
- Electrum Rust Server (Electrs)
- Fulcrum Electrum Server

Please enable one of these services first.
" 14 55
    exit 0
  fi

  CHOICE=$(whiptail --title " Holesail Manager " --menu "
Holesail creates peer-to-peer tunnels to expose your 
services without port forwarding or static IPs.

Toggle services on/off or view connection info:
" 18 60 8 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)
  
  case $CHOICE in
    CLNREST)
      if isHolesailEnabled "clnrest"; then
        # Show submenu for enabled service
        SUBCHOICE=$(whiptail --title " CLNrest Holesail " --menu "" 12 50 4 \
          "CONNECT" "Show connection info & QR code" \
          "DISABLE" "Disable Holesail tunnel" \
          3>&1 1>&2 2>&3)
        case $SUBCHOICE in
          CONNECT)
            clear
            /home/admin/config.scripts/bonus.holesail-manager.sh connect clnrest
            ;;
          DISABLE)
            clear
            /home/admin/config.scripts/bonus.holesail-manager.sh remove clnrest
            echo ""
            echo "Press ENTER to continue..."
            read -r
            ;;
        esac
      else
        # Enable the service
        whiptail --title " Enable CLNrest Holesail " --yesno "
This will create a Holesail tunnel for CLNrest.

You will receive a unique connector string that can be 
used to connect to your CLNrest API from anywhere.

Enable Holesail tunnel for CLNrest?
" 12 55
        if [ $? -eq 0 ]; then
          clear
          /home/admin/config.scripts/bonus.holesail-manager.sh add clnrest
          echo ""
          echo "Press ENTER to continue..."
          read -r
        fi
      fi
      ;;
      
    LNDREST)
      if isHolesailEnabled "lndrest"; then
        SUBCHOICE=$(whiptail --title " LND REST Holesail " --menu "" 12 50 4 \
          "CONNECT" "Show connection info & QR code" \
          "DISABLE" "Disable Holesail tunnel" \
          3>&1 1>&2 2>&3)
        case $SUBCHOICE in
          CONNECT)
            clear
            /home/admin/config.scripts/bonus.holesail-manager.sh connect lndrest
            ;;
          DISABLE)
            clear
            /home/admin/config.scripts/bonus.holesail-manager.sh remove lndrest
            echo ""
            echo "Press ENTER to continue..."
            read -r
            ;;
        esac
      else
        whiptail --title " Enable LND REST Holesail " --yesno "
This will create a Holesail tunnel for LND REST API.

You will receive a unique connector string that can be 
used to connect to your LND REST API from anywhere.

Enable Holesail tunnel for LND REST?
" 12 55
        if [ $? -eq 0 ]; then
          clear
          /home/admin/config.scripts/bonus.holesail-manager.sh add lndrest
          echo ""
          echo "Press ENTER to continue..."
          read -r
        fi
      fi
      ;;
      
    ELECTRS)
      if isHolesailEnabled "electrs"; then
        SUBCHOICE=$(whiptail --title " Electrs Holesail " --menu "" 12 50 4 \
          "CONNECT" "Show connection info & QR code" \
          "DISABLE" "Disable Holesail tunnel" \
          3>&1 1>&2 2>&3)
        case $SUBCHOICE in
          CONNECT)
            clear
            /home/admin/config.scripts/bonus.holesail-manager.sh connect electrs
            ;;
          DISABLE)
            clear
            /home/admin/config.scripts/bonus.holesail-manager.sh remove electrs
            echo ""
            echo "Press ENTER to continue..."
            read -r
            ;;
        esac
      else
        whiptail --title " Enable Electrs Holesail " --yesno "
This will create a Holesail tunnel for Electrs.

You will receive a unique connector string that can be 
used to connect to your Electrum server from anywhere.

Enable Holesail tunnel for Electrs?
" 12 55
        if [ $? -eq 0 ]; then
          clear
          /home/admin/config.scripts/bonus.holesail-manager.sh add electrs
          echo ""
          echo "Press ENTER to continue..."
          read -r
        fi
      fi
      ;;
      
    FULCRUM)
      if isHolesailEnabled "fulcrum"; then
        SUBCHOICE=$(whiptail --title " Fulcrum Holesail " --menu "" 12 50 4 \
          "CONNECT" "Show connection info & QR code" \
          "DISABLE" "Disable Holesail tunnel" \
          3>&1 1>&2 2>&3)
        case $SUBCHOICE in
          CONNECT)
            clear
            /home/admin/config.scripts/bonus.holesail-manager.sh connect fulcrum
            ;;
          DISABLE)
            clear
            /home/admin/config.scripts/bonus.holesail-manager.sh remove fulcrum
            echo ""
            echo "Press ENTER to continue..."
            read -r
            ;;
        esac
      else
        whiptail --title " Enable Fulcrum Holesail " --yesno "
This will create a Holesail tunnel for Fulcrum.

You will receive a unique connector string that can be 
used to connect to your Electrum server from anywhere.

Enable Holesail tunnel for Fulcrum?
" 12 55
        if [ $? -eq 0 ]; then
          clear
          /home/admin/config.scripts/bonus.holesail-manager.sh add fulcrum
          echo ""
          echo "Press ENTER to continue..."
          read -r
        fi
      fi
      ;;
      
    STATUS)
      clear
      echo "=============================================="
      echo "  HOLESAIL STATUS"
      echo "=============================================="
      echo ""
      
      # Show holesail version
      VERSION=$(holesail --version 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+)*$')
      echo "Holesail Version: ${VERSION}"
      echo ""
      
      # Show status of each service
      for SERVICE in clnrest lndrest electrs fulcrum; do
        if isHolesailEnabled "${SERVICE}"; then
          CONNECTOR=$(getConnector "${SERVICE}")
          ACTIVE=$(sudo systemctl is-active holesail-${SERVICE} 2>/dev/null)
          echo "${SERVICE}:"
          echo "  Status: ${ACTIVE}"
          echo "  Connector: ${CONNECTOR}"
          echo ""
        fi
      done
      
      # Show systemd status
      echo "----------------------------------------------"
      echo "Systemd Services:"
      sudo systemctl list-units 'holesail-*' --no-pager 2>/dev/null || echo "No holesail services running"
      echo ""
      echo "Press ENTER to continue..."
      read -r
      ;;
      
    UNINSTALL)
      whiptail --title " Uninstall Holesail " --yesno "
This will:
- Stop all Holesail tunnels
- Remove all connector strings
- Uninstall Holesail from the system

Are you sure you want to uninstall Holesail?
" 12 55
      if [ $? -eq 0 ]; then
        clear
        /home/admin/config.scripts/bonus.holesail-manager.sh off
        echo ""
        echo "Press ENTER to continue..."
        read -r
      fi
      ;;
  esac
  
  exit 0
fi