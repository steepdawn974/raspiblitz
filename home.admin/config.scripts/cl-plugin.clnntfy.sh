#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "Install the cln-ntfy plugin (ntfy notifications) for Core Lightning"
  echo "Source: https://github.com/yukibtc/cln-ntfy"
  echo
  echo "Usage:"
  echo "cl-plugin.clnntfy.sh [on|off|remove] <testnet|mainnet|signet>"
  echo
  exit 1
fi

# load CLN network aliases and useful vars
# provides: netprefix ("" or "t" or "s"), CLCONF, lightningcli_alias, CLNETWORK
source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

plugin="cln-ntfy"
plugindir="/home/bitcoin/cl-plugins-available/${plugin}"
pluginbin="${plugindir}/target/release/${plugin}"
enabled_dir="/home/bitcoin/${netprefix}cl-plugins-enabled"
symlink_target="${enabled_dir}/${plugin}"
repo_url="https://github.com/yukibtc/cln-ntfy.git"

# ensure enabled directory exists (idempotent)
if [ ! -d "${enabled_dir}" ]; then
  sudo -u bitcoin mkdir -p "${enabled_dir}"
fi

install_build() {
  # clone if missing
  if [ ! -d "${plugindir}/.git" ]; then
    sudo -u bitcoin mkdir -p "/home/bitcoin/cl-plugins-available"
    cd /home/bitcoin/cl-plugins-available || exit 1
    sudo -u bitcoin git clone "${repo_url}" "${plugin}" || exit 1
  else
    # update repo if it exists
    cd "${plugindir}" || exit 1
    sudo -u bitcoin git fetch --all
    sudo -u bitcoin git pull --ff-only || true
  fi

  # build release binary (idempotent) using system-wide Rust (/opt/rust)
  echo "# Building ${plugin} with cargo --release (RUSTUP_HOME=/opt/rust CARGO_HOME=/opt/rust) ..."
  cd "${plugindir}" || exit 1
  sudo -u bitcoin RUSTUP_HOME=/opt/rust CARGO_HOME=/opt/rust cargo build --release || exit 1

  # ensure binary permissions
  if [ -f "${pluginbin}" ]; then
    sudo chmod +x "${pluginbin}"
  else
    echo "# Build seems to have failed, missing ${pluginbin}"
    exit 1
  fi

  # create/refresh symlink into enabled dir
  if [ -L "${symlink_target}" ] || [ -f "${symlink_target}" ]; then
    sudo rm -f "${symlink_target}"
  fi
  sudo ln -s "${pluginbin}" "${enabled_dir}" || exit 1
}

if [ "$1" = "on" ]; then
  install_build

  # set flag in raspiblitz config (idempotent)
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clnntfy "on"

  # set default CLN config options if not present yet
  # ntfy-url is required; only set the optional defaults so the user can fill
  # in their server/topic/auth in the CLN config or via the menu later.
  if ! grep -q "^ntfy-topic=" "${CLCONF}"; then
    echo "# setting ntfy-topic=cln-alerts"
    sudo /home/admin/config.scripts/blitz.conf.sh set "ntfy-topic" "cln-alerts" "${CLCONF}" "noquotes"
  fi
  if ! grep -q "^ntfy-events=" "${CLCONF}"; then
    echo "# setting ntfy-events=all"
    sudo /home/admin/config.scripts/blitz.conf.sh set "ntfy-events" "all" "${CLCONF}" "noquotes"
  fi

  # restart service to apply updated CLCONF and load plugin (if system is ready)
  source <(/home/admin/_cache.sh get state)
  if [ "${state}" = "ready" ] && [ "$3" != "norestart" ]; then
    echo "# Restarting ${netprefix}lightningd to apply ntfy options and load plugin"
    sudo systemctl restart ${netprefix}lightningd
  fi

  # Display next steps
  echo ""
  echo "#####################################################################################################"
  echo "# cln-ntfy forwards CLN notifications to an ntfy server."
  echo "# https://github.com/yukibtc/cln-ntfy#options"
  echo ""
  echo "# REQUIRED: set your ntfy server URL in ${CLCONF}:"
  echo "#   ntfy-url=https://ntfy.sh"
  echo ""
  echo "# OPTIONAL (basic auth):"
  echo "#   ntfy-username=alice"
  echo "#   ntfy-password=secret"
  echo "# OPTIONAL (access token, mutually exclusive with basic auth):"
  echo "#   ntfy-token=tk_abc123..."
  echo "# OPTIONAL (for .onion servers):"
  echo "#   ntfy-proxy=socks5h://127.0.0.1:9050"
  echo "# OPTIONAL (restrict events):"
  echo "#   ntfy-events=invoice_payment,channel_opened   # or 'all'"
  echo ""
  echo "# After editing ${CLCONF} restart CLN:"
  echo "#   sudo systemctl restart ${netprefix}lightningd"
  echo "#####################################################################################################"

fi

if [ "$1" = "off" ]; then
  echo "# Stop the ${plugin} if running (ignore errors)"
  $lightningcli_alias plugin stop "${symlink_target}" 2>/dev/null || true

  echo "# Remove symlink from enabled dir"
  sudo rm -f "${symlink_target}"

  # remove any explicit plugin options from ${CLCONF} using the ntfy-* keys (no-op if none)
  echo "# Clean any ntfy-* options from ${CLCONF} (if present)"
  sudo sed -i "/^ntfy-/d" ${CLCONF}

  # set flag in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clnntfy "off"

  echo "# The ${plugin} has been disabled"
fi

if [ "$1" = "remove" ]; then
  # ensure it's turned off first
  $0 off $2 norestart

  echo "# Removing plugin source directory ${plugindir}"
  sudo rm -rf "${plugindir}"
  echo "# Removed ${plugin}"
fi
