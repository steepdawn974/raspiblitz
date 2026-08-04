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
# TODO: switch back to upstream yukibtc/cln-ntfy once the v0.2 refactor is merged
repo_url="https://github.com/steepdawn974/cln-ntfy.git"
repo_branch="refactor-v0.2"

# ensure enabled directory exists (idempotent)
if [ ! -d "${enabled_dir}" ]; then
  sudo -u bitcoin mkdir -p "${enabled_dir}"
fi

install_build() {
  # clone if missing
  if [ ! -d "${plugindir}/.git" ]; then
    sudo -u bitcoin mkdir -p "/home/bitcoin/cl-plugins-available"
    cd /home/bitcoin/cl-plugins-available || exit 1
    sudo -u bitcoin git clone --branch "${repo_branch}" "${repo_url}" "${plugin}" || exit 1
  else
    # update repo if it exists
    cd "${plugindir}" || exit 1
    sudo -u bitcoin git fetch --all
    sudo -u bitcoin git checkout "${repo_branch}" || true
    sudo -u bitcoin git pull --ff-only origin "${repo_branch}" || true
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

  # set default CLN config options if not present yet.
  # SAFE DEFAULTS: the plugin starts but publishes NOTHING until the user
  # explicitly opts in by changing ntfy-events. A random topic is generated so
  # that even when events are later enabled on the public ntfy.sh, the topic
  # is unguessable and the user's notifications stay private.
  if ! grep -q "^ntfy-url=" "${CLCONF}"; then
    echo "# setting ntfy-url=https://ntfy.sh (public server; change to self-hosted if desired)"
    sudo /home/admin/config.scripts/blitz.conf.sh set "ntfy-url" "https://ntfy.sh" "${CLCONF}" "noquotes"
  fi
  if ! grep -q "^ntfy-topic=" "${CLCONF}"; then
    random_suffix=$(head -c 8 /dev/urandom | xxd -p)
    topic="cln-${random_suffix}"
    echo "# setting ntfy-topic=${topic} (random, private)"
    sudo /home/admin/config.scripts/blitz.conf.sh set "ntfy-topic" "${topic}" "${CLCONF}" "noquotes"
  fi
  if ! grep -q "^ntfy-events=" "${CLCONF}"; then
    echo "# setting ntfy-events=none (nothing published until you opt in)"
    sudo /home/admin/config.scripts/blitz.conf.sh set "ntfy-events" "none" "${CLCONF}" "noquotes"
  fi

  # copy the sample template file next to the CLN config (idempotent)
  template_src="${plugindir}/ntfy-template.sample.conf"
  template_dst="/home/bitcoin/.lightning/ntfy-template.conf"
  if [ -f "${template_src}" ] && [ ! -f "${template_dst}" ]; then
    echo "# copying sample template to ${template_dst}"
    sudo cp "${template_src}" "${template_dst}"
    sudo chown bitcoin:bitcoin "${template_dst}"
  fi
  if ! grep -q "^ntfy-template-file=" "${CLCONF}" && [ -f "${template_dst}" ]; then
    echo "# setting ntfy-template-file=${template_dst}"
    sudo /home/admin/config.scripts/blitz.conf.sh set "ntfy-template-file" "${template_dst}" "${CLCONF}" "noquotes"
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
  echo "# cln-ntfy is installed but INERT (ntfy-events=none)."
  echo "# Nothing is published until you enable events in ${CLCONF}."
  echo "# https://github.com/yukibtc/cln-ntfy#options"
  echo ""
  echo "# Defaults already set: ntfy-url, ntfy-topic (random), ntfy-events=none"
  echo ""
  echo "# TO ENABLE NOTIFICATIONS, edit ${CLCONF} and set:"
  echo "#   ntfy-events=all   # or a subset: invoice_payment,channel_opened"
  echo ""
  echo "# OPTIONAL (self-hosted server):"
  echo "#   ntfy-url=https://ntfy.example.com"
  echo "# OPTIONAL (basic auth):"
  echo "#   ntfy-username=alice"
  echo "#   ntfy-password=secret"
  echo "# OPTIONAL (access token, mutually exclusive with basic auth):"
  echo "#   ntfy-token=tk_abc123..."
  echo "# OPTIONAL (for .onion servers):"
  echo "#   ntfy-proxy=socks5h://127.0.0.1:9050"
  echo "# OPTIONAL (custom message templates):"
  echo "#   A sample template was copied to /home/bitcoin/.lightning/ntfy-template.conf"
  echo "#   Edit it to customize titles/messages, or remove ntfy-template-file to use defaults."
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
