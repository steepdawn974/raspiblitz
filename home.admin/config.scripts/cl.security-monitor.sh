#!/bin/bash

# cl.security-monitor.sh
# Monitors a Core Lightning node for suspicious behaviour during active security advisories.
# Alerts are sent via ntfy via a systemd timer (every 10 min by default).
#
# Usage:
#   cl.security-monitor.sh on <mainnet|testnet|signet> [interval]  # install systemd service+timer
#   cl.security-monitor.sh off <mainnet|testnet|signet>            # remove systemd service+timer
#   cl.security-monitor.sh <mainnet|testnet|signet>                # one-shot check + alert on anomalies
#   cl.security-monitor.sh <mainnet|testnet|signet> baseline       # capture current state as baseline
#
# Examples:
#   cl.security-monitor.sh on mainnet          # install with default 10min interval
#   cl.security-monitor.sh on mainnet 5min     # install with 5min interval
#   cl.security-monitor.sh mainnet baseline    # capture baseline after confirming node is healthy
#   cl.security-monitor.sh mainnet             # run a single check

set -euo pipefail

# --- help ---
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ] || [ "$1" = "--help" ]; then
  echo "CLN security monitor — alerts on suspicious peer/routing/channel activity"
  echo "Usage:"
  echo "  cl.security-monitor.sh on <mainnet|testnet|signet> [interval]  # install systemd timer"
  echo "  cl.security-monitor.sh off <mainnet|testnet|signet>            # remove systemd timer"
  echo "  cl.security-monitor.sh <mainnet|testnet|signet> [baseline]     # run check or capture baseline"
  echo ""
  echo "  interval: 5min | 10min | 15min | 30min | 1h (default: 10min)"
  exit 1
fi

# --- on/off: manage systemd service + timer ---
if [ "$1" = "on" ] || [ "$1" = "off" ]; then
  action="$1"
  network="${2:-mainnet}"
  interval="${3:-10min}"

  if [ "$EUID" -ne 0 ]; then
    echo "error='run on/off as root (with sudo)'"
    exit 1
  fi

  case "${network}" in
    mainnet|testnet|signet) ;;
    *) echo "error='invalid network: ${network} (use mainnet|testnet|signet)'" && exit 1 ;;
  esac

  # source network vars (provides netprefix, CLCONF, etc.)
  source <(/home/admin/config.scripts/network.aliases.sh getvars cl "${network}")

  SERVICE_NAME="${netprefix}cl-security-monitor"
  SCRIPT_PATH="/home/admin/config.scripts/cl.security-monitor.sh"
  MONITOR_DIR="/home/bitcoin/.lightning/${CLNETWORK}/.security-monitor"

  if [ "$action" = "on" ]; then
    # validate interval
    case "$interval" in
      5min|10min|15min|30min|1h) ;;
      *) echo "error='invalid interval: $interval (use 5min|10min|15min|30min|1h)'" && exit 1 ;;
    esac

    # set up notifications via blitz.notify.sh (writes ntfy defaults to raspiblitz.conf)
    echo "# Setting up notifications"
    if [ -x /home/admin/config.scripts/blitz.notify.sh ]; then
      /home/admin/config.scripts/blitz.notify.sh on
      # set method to ntfy for security alerts
      /home/admin/config.scripts/blitz.conf.sh set notifyMethod ntfy
    else
      echo "# WARNING: blitz.notify.sh not found — alerts will be log-only"
    fi

    echo "# Creating /etc/systemd/system/${SERVICE_NAME}.service"
    echo "
[Unit]
Description=CLN security monitor (${network})
Wants=${netprefix}lightningd.service
After=${netprefix}lightningd.service

[Service]
Type=oneshot
ExecStart=${SCRIPT_PATH} ${network}
User=bitcoin
Group=bitcoin
TimeoutSec=120
StandardOutput=journal
StandardError=journal
" | tee /etc/systemd/system/${SERVICE_NAME}.service >/dev/null

    echo "# Creating /etc/systemd/system/${SERVICE_NAME}.timer"
    echo "
[Unit]
Description=Run CLN security monitor every ${interval}

[Timer]
OnBootSec=2min
OnUnitActiveSec=${interval}
Persistent=true

[Install]
WantedBy=timers.target
" | tee /etc/systemd/system/${SERVICE_NAME}.timer >/dev/null

    # logrotate for the monitor log
    echo "# Set logrotate for ${SERVICE_NAME}"
    echo "\
${MONITOR_DIR}/monitor.log
{
        rotate 4
        size 10M
        copytruncate
        missingok
        notifempty
        nocompress
        sharedscripts
        su bitcoin bitcoin
}" | tee /etc/logrotate.d/${SERVICE_NAME} >/dev/null

    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}.timer
    systemctl start ${SERVICE_NAME}.timer
    echo "# Enabled and started ${SERVICE_NAME}.timer (every ${interval})"
    echo "# To check: sudo systemctl list-timers ${SERVICE_NAME}.timer"
    echo "# To view logs: sudo journalctl -u ${SERVICE_NAME}"
    echo "# Log file: ${MONITOR_DIR}/monitor.log"
    echo ""
    echo "# Run a baseline capture now (after confirming node is healthy):"
    echo "  sudo -u bitcoin ${SCRIPT_PATH} ${network} baseline"
    exit 0
  fi

  if [ "$action" = "off" ]; then
    echo "# Removing ${SERVICE_NAME}.timer, .service and logrotate"
    systemctl stop ${SERVICE_NAME}.timer 2>/dev/null || true
    systemctl disable ${SERVICE_NAME}.timer 2>/dev/null || true
    rm -f /etc/systemd/system/${SERVICE_NAME}.timer
    rm -f /etc/systemd/system/${SERVICE_NAME}.service
    rm -f /etc/logrotate.d/${SERVICE_NAME}
    systemctl daemon-reload
    echo "# Removed ${SERVICE_NAME} timer, service and logrotate"
    exit 0
  fi
fi

if [ "${EUID}" -eq 0 ]; then
  exec sudo -u bitcoin -- "$0" "$@"
fi
if [ "$(id -un)" != "bitcoin" ]; then
  echo "error='run checks as bitcoin (sudo -u bitcoin)'"
  exit 1
fi

# --- network setup (sourced like all other cl scripts) ---
case "$1" in
  mainnet|testnet|signet) ;;
  *) echo "error='invalid network: $1 (use mainnet|testnet|signet)'" && exit 1 ;;
esac
source <(/home/admin/config.scripts/network.aliases.sh getvars cl "$1")

# --- state directory ---
STATE_DIR="/home/bitcoin/.lightning/${CLNETWORK}/.security-monitor"
BASELINE_FILE="${STATE_DIR}/baseline.json"
LASTRUN_FILE="${STATE_DIR}/lastrun.json"
FORWARDS_FILE="${STATE_DIR}/forwards.json"
LOG_FILE="${STATE_DIR}/monitor.log"
mkdir -p "${STATE_DIR}"

# --- notification config (optional) ---
# Cascade: raspiblitz.conf → NTFY_* env vars → ntfy-* from CLN config
# If none configured, alerts are log-only.
source /mnt/hdd/app-data/raspiblitz.conf 2>/dev/null

# 1. raspiblitz.conf (written by blitz.notify.sh on)
NTFY_URL="${notifyNtfyUrl:-}"
NTFY_TOPIC="${notifyNtfyTopic:-}"
NTFY_TOKEN="${notifyNtfyToken:-}"

# 2. NTFY_* env vars (override for testing or custom setups)
: "${NTFY_URL:=${NTFY_URL_ENV:-}}"
: "${NTFY_TOPIC:=${NTFY_TOPIC_ENV:-}}"
: "${NTFY_TOKEN:=${NTFY_TOKEN_ENV:-}}"

# 3. ntfy-* from CLN config (e.g. set by cl-plugin.clnntfy.sh)
if [ -z "${NTFY_URL}" ]; then
  NTFY_URL=$(grep '^ntfy-url=' "${CLCONF}" 2>/dev/null | cut -d= -f2- | tr -d ' ')
fi
if [ -z "${NTFY_TOPIC}" ]; then
  NTFY_TOPIC=$(grep '^ntfy-topic=' "${CLCONF}" 2>/dev/null | cut -d= -f2- | tr -d ' ')
fi
if [ -z "${NTFY_TOKEN}" ]; then
  NTFY_TOKEN=$(grep '^ntfy-token=' "${CLCONF}" 2>/dev/null | cut -d= -f2- | tr -d ' ')
fi

# Determine if notifications are available
NOTIFY_SCRIPT="/home/admin/config.scripts/blitz.notify.sh"
NOTIFY_ENABLED=false
if [ -n "${NTFY_URL}" ] && [ -n "${NTFY_TOPIC}" ] && [ "${NTFY_URL}" != "https://ntfy.example.com" ]; then
  NOTIFY_ENABLED=true
fi

# --- helpers ---
timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

log() {
  echo "[$(timestamp)] $*" >> "${LOG_FILE}"
  echo "[$(timestamp)] $*"
}

send_alert() {
  # $1 = priority (urgent | high | default), $2 = title, $3 = message
  local priority="$1" title="$2" message="$3"
  # If notifications are not configured, log the alert only
  if [ "${NOTIFY_ENABLED}" != "true" ]; then
    log "ALERT (log-only) [${priority}] ${title}: ${message}"
    return 0
  fi
  # Send via blitz.notify.sh with JSON message if available, else inline curl
  if [ -x "${NOTIFY_SCRIPT}" ] && grep -Eq "^notify=on" /mnt/hdd/app-data/raspiblitz.conf 2>/dev/null; then
    local jsonMsg
    jsonMsg=$(jq -cn \
      --arg title "${title}" \
      --arg priority "${priority}" \
      --arg tags "warning,cln" \
      --arg message "${message}" \
      '{title: $title, priority: $priority, tags: $tags, message: $message}')
    if "${NOTIFY_SCRIPT}" send "${jsonMsg}" >/dev/null 2>&1; then
      log "ALERT SENT [${priority}] ${title}: ${message}"
    else
      log "ERROR: failed to send alert [${priority}] ${title}: ${message}"
    fi
  else
    # Fallback: inline curl directly to ntfy
    local endpoint="${NTFY_URL}/${NTFY_TOPIC}"
    local headers=(-H "Title: ${title}" -H "Tags: warning,cln")
    if [ -n "${NTFY_TOKEN}" ]; then
      headers+=(-H "Authorization: Bearer ${NTFY_TOKEN}")
    fi
    case "${priority}" in
      urgent) headers+=(-H "Priority: urgent") ;;
      high)   headers+=(-H "Priority: high") ;;
      *)      ;;
    esac
    if curl -sS --connect-timeout 10 --max-time 30 -X POST "${endpoint}" "${headers[@]}" -d "${message}" >/dev/null 2>&1; then
      log "ALERT SENT [${priority}] ${title}: ${message}"
    else
      log "ERROR: failed to send alert [${priority}] ${title}: ${message}"
    fi
  fi
}

# lightning-cli — run directly as bitcoin (service runs as User=bitcoin)
LCLI=(/usr/local/bin/lightning-cli "--conf=${CLCONF}")

fetch_forward_pages() {
  local index="$1" start="$2" end="$3" page page_count page_max all='[]'
  while [ "${start}" -le "${end}" ]; do
    page=$("${LCLI[@]}" listforwards -k "index=${index}" "start=${start}" "limit=1000" 2>/dev/null) || return 1
    page_count=$(echo "${page}" | jq '.forwards | length')
    [ "${page_count}" -eq 0 ] && break
    all=$(jq -cn --argjson all "${all}" --argjson page "${page}" '$all + $page.forwards')
    page_max=$(echo "${page}" | jq -r --arg field "${index}_index" '[.forwards[][$field] // 0] | max // 0')
    [ "${page_max}" -lt "${start}" ] && break
    start=$((page_max + 1))
  done
  echo "${all}"
}

update_forward_cache() {
  local now current_created current_updated previous_created previous_updated cache created='[]' updated='[]' merged recent
  now=$(date +%s)
  current_created=$("${LCLI[@]}" wait -k "subsystem=forwards" "indexname=created" "nextvalue=0" 2>/dev/null | jq -r '.created // 0') || return 1
  current_updated=$("${LCLI[@]}" wait -k "subsystem=forwards" "indexname=updated" "nextvalue=0" 2>/dev/null | jq -r '.updated // 0') || return 1

  if [ -s "${FORWARDS_FILE}" ] && jq -e '.forwards and .created_index != null and .updated_index != null' "${FORWARDS_FILE}" >/dev/null 2>&1; then
    previous_created=$(jq -r '.created_index' "${FORWARDS_FILE}")
    previous_updated=$(jq -r '.updated_index' "${FORWARDS_FILE}")
    cache=$(jq -c '.forwards' "${FORWARDS_FILE}")
  else
    previous_created="${current_created}"
    previous_updated="${current_updated}"
    cache='[]'
  fi

  if [ "${current_created}" -gt "${previous_created}" ]; then
    if ! created=$(fetch_forward_pages created "$((previous_created + 1))" "${current_created}"); then
      log "ERROR: failed to collect newly created forwards" >&2
      current_created="${previous_created}"
      created='[]'
    fi
  fi
  if [ "${current_updated}" -gt "${previous_updated}" ]; then
    if ! updated=$(fetch_forward_pages updated "$((previous_updated + 1))" "${current_updated}"); then
      log "ERROR: failed to collect updated forwards" >&2
      current_updated="${previous_updated}"
      updated='[]'
    fi
  fi

  merged=$(jq -cn --argjson cache "${cache}" --argjson created "${created}" --argjson updated "${updated}" '
    reduce ($cache + $created + $updated)[] as $forward ({}; .[$forward.created_index | tostring] = $forward)
    | [.[]]
  ')
  recent=$(echo "${merged}" | jq --argjson cutoff "$((now - 3600))" '[.[] | select((.received_time // 0) > $cutoff)]')
  jq -n \
    --argjson created_index "${current_created}" \
    --argjson updated_index "${current_updated}" \
    --argjson forwards "${recent}" \
    '{created_index: $created_index, updated_index: $updated_index, forwards: $forwards}' > "${FORWARDS_FILE}"
  jq -n --argjson forwards "${recent}" '{forwards: $forwards}'
}

# --- collect current state ---
collect_state() {
  local getinfo peers channels forwards_recent

  getinfo=$("${LCLI[@]}" getinfo 2>/dev/null) || {
    log "ERROR: cannot reach lightningd via RPC"
    send_alert urgent "CLN RPC unreachable" "lightning-cli getinfo failed — node may be down or unresponsive"
    exit 2
  }

  peers=$("${LCLI[@]}" listpeers 2>/dev/null || echo '{"peers":[]}')
  channels=$("${LCLI[@]}" listpeerchannels 2>/dev/null || echo '{"channels":[]}')

  # pending HTLCs
  local pending_htlc_count pending_htlc_total_msat
  pending_htlc_count=$(echo "${channels}" | jq '[.channels[] | .htlcs[]?] | length' 2>/dev/null || echo 0)
  pending_htlc_total_msat=$(echo "${channels}" | jq '[.channels[] | .htlcs[]? | .amount_msat // 0] | add // 0' 2>/dev/null || echo 0)

  # peer stats
  local num_peers num_connected num_zero_channel_peers zero_channel_peers
  num_peers=$(echo "${getinfo}" | jq -r '.num_peers')
  num_connected=$(echo "${peers}" | jq '[.peers[] | select(.connected == true)] | length')
  num_zero_channel_peers=$(echo "${peers}" | jq '[.peers[] | select(.num_channels == 0 and .connected == true)] | length')
  zero_channel_peers=$(echo "${peers}" | jq -r '[.peers[] | select(.num_channels == 0 and .connected == true) | .id] | join(",")')

  # channel stats
  local num_active num_inactive num_pending num_remote_pending
  num_active=$(echo "${getinfo}" | jq -r '.num_active_channels')
  num_inactive=$(echo "${getinfo}" | jq -r '.num_inactive_channels')
  num_pending=$(echo "${getinfo}" | jq -r '.num_pending_channels')
  num_remote_pending=$(echo "${channels}" | jq '[.channels[] | select(.opener == "remote" and (.state == "OPENINGD" or .state == "CHANNELD_AWAITING_LOCKIN" or .state == "DUALOPEND_OPEN_INIT" or .state == "DUALOPEND_AWAITING_LOCKIN" or .state == "DUALOPEND_OPEN_COMMITTED" or .state == "DUALOPEND_OPEN_COMMIT_READY"))] | length')

  # channel states — look for non-normal states
  local abnormal_channels
  abnormal_channels=$(echo "${channels}" | jq -r '
    [.channels[] | select(.lost_state == true or .state == "AWAITING_UNILATERAL" or .state == "FUNDING_SPEND_SEEN")]
    | length
  ' 2>/dev/null || echo 0)

  # forwarding in last hour (settled + failed)
  local settled_recent failed_recent
  forwards_recent=$(update_forward_cache) || {
    log "ERROR: failed to update forward cache" >&2
    forwards_recent='{"forwards":[]}'
  }
  settled_recent=$(echo "${forwards_recent}" | jq '[.forwards[] | select(.status == "settled")] | length' 2>/dev/null || echo 0)
  failed_recent=$(echo "${forwards_recent}" | jq '[.forwards[] | select(.status == "local_failed" or .status == "failed")] | length' 2>/dev/null || echo 0)

  # large forwards in last hour (> 500k sats = 500000000 msat)
  local large_forwards
  large_forwards=$(echo "${forwards_recent}" | jq '[.forwards[] | select(.status == "settled" and (.in_msat // 0) > 500000000)] | length' 2>/dev/null || echo 0)

  # blockheight
  local blockheight warning_bitcoind_sync warning_lightningd_sync
  blockheight=$(echo "${getinfo}" | jq -r '.blockheight')
  warning_bitcoind_sync=$(echo "${getinfo}" | jq -r '.warning_bitcoind_sync // ""')
  warning_lightningd_sync=$(echo "${getinfo}" | jq -r '.warning_lightningd_sync // ""')

  # fees collected (lifetime)
  local fees_collected_msat
  fees_collected_msat=$(echo "${getinfo}" | jq -r '.fees_collected_msat')

  # build state JSON
  jq -n \
    --arg ts "$(timestamp)" \
    --argjson num_peers "${num_peers:-0}" \
    --argjson num_connected "${num_connected:-0}" \
    --argjson num_zero_channel_peers "${num_zero_channel_peers:-0}" \
    --arg zero_channel_peers "${zero_channel_peers}" \
    --argjson num_active "${num_active:-0}" \
    --argjson num_inactive "${num_inactive:-0}" \
    --argjson num_pending "${num_pending:-0}" \
    --argjson num_remote_pending "${num_remote_pending:-0}" \
    --argjson abnormal_channels "${abnormal_channels:-0}" \
    --argjson pending_htlc_count "${pending_htlc_count:-0}" \
    --argjson pending_htlc_total_msat "${pending_htlc_total_msat:-0}" \
    --argjson settled_recent "${settled_recent:-0}" \
    --argjson failed_recent "${failed_recent:-0}" \
    --argjson large_forwards "${large_forwards:-0}" \
    --argjson blockheight "${blockheight:-0}" \
    --arg warning_bitcoind_sync "${warning_bitcoind_sync}" \
    --arg warning_lightningd_sync "${warning_lightningd_sync}" \
    --arg fees_collected_msat "${fees_collected_msat:-0}" \
    '{
      timestamp: $ts,
      num_peers: $num_peers,
      num_connected: $num_connected,
      num_zero_channel_peers: $num_zero_channel_peers,
      zero_channel_peers: $zero_channel_peers,
      num_active: $num_active,
      num_inactive: $num_inactive,
      num_pending: $num_pending,
      num_remote_pending: $num_remote_pending,
      abnormal_channels: $abnormal_channels,
      pending_htlc_count: $pending_htlc_count,
      pending_htlc_total_msat: $pending_htlc_total_msat,
      settled_recent: $settled_recent,
      failed_recent: $failed_recent,
      large_forwards: $large_forwards,
      blockheight: $blockheight,
      warning_bitcoind_sync: $warning_bitcoind_sync,
      warning_lightningd_sync: $warning_lightningd_sync,
      fees_collected_msat: $fees_collected_msat
    }'
}

# --- baseline mode ---
if [ "${2:-}" = "baseline" ]; then
  log "Capturing baseline state..."
  collect_state > "${BASELINE_FILE}"
  log "Baseline saved to ${BASELINE_FILE}"
  cat "${BASELINE_FILE}" | jq .
  exit 0
fi

# --- main monitoring logic ---
PREVIOUS=''
if [ -s "${LASTRUN_FILE}" ] && jq -e . "${LASTRUN_FILE}" >/dev/null 2>&1; then
  PREVIOUS=$(cat "${LASTRUN_FILE}")
fi
CURRENT=$(collect_state)
echo "${CURRENT}" > "${LASTRUN_FILE}"

ALERTS=0

# If no baseline exists, use current as baseline (first run)
if [ ! -f "${BASELINE_FILE}" ]; then
  log "No baseline found — using current state as baseline. Run with 'baseline' after confirming node is healthy."
  cp "${LASTRUN_FILE}" "${BASELINE_FILE}"
fi

BASELINE=$(cat "${BASELINE_FILE}")

# Helper: compare values
get_val() { echo "$1" | jq -r "$2"; }

# --- CHECK 1: Peer count spike ---
b_peers=$(get_val "${BASELINE}" '.num_peers')
c_peers=$(get_val "${CURRENT}" '.num_peers')
peer_delta=$((c_peers - b_peers))
if [ "${peer_delta}" -gt 5 ]; then
  send_alert high "CLN: Peer count spike" "Peers went from ${b_peers} to ${c_peers} (+${peer_delta}). Possible probing or attack."
  ALERTS=$((ALERTS + 1))
fi
log "Peers: ${c_peers} (baseline: ${b_peers}, delta: ${peer_delta})"

# --- CHECK 2: Excessive zero-channel peers ---
c_zero=$(get_val "${CURRENT}" '.num_zero_channel_peers')
b_zero=$(get_val "${BASELINE}" '.num_zero_channel_peers')
if [ "${c_zero}" -gt 8 ]; then
  send_alert high "CLN: Many no-channel peers" "${c_zero} connected peers have 0 channels (baseline: ${b_zero}). These may be probing nodes. IDs: $(get_val "${CURRENT}" '.zero_channel_peers')"
  ALERTS=$((ALERTS + 1))
fi
log "Zero-channel peers: ${c_zero} (baseline: ${b_zero})"

# --- CHECK 3: Pending HTLC flooding ---
c_htlc_count=$(get_val "${CURRENT}" '.pending_htlc_count')
c_htlc_total=$(get_val "${CURRENT}" '.pending_htlc_total_msat')
# Alert if > 20 pending HTLCs or total value > 5M sats (5,000,000,000 msat)
if [ "${c_htlc_count}" -gt 20 ] || [ "${c_htlc_total}" -gt 5000000000 ]; then
  send_alert urgent "CLN: HTLC flooding" "${c_htlc_count} pending HTLCs (total: $((c_htlc_total / 1000)) sats). Possible HTLC flood attack."
  ALERTS=$((ALERTS + 1))
fi
log "Pending HTLCs: ${c_htlc_count} (total: $((c_htlc_total / 1000)) sats)"

# --- CHECK 4: Abnormal channel states ---
c_abnormal=$(get_val "${CURRENT}" '.abnormal_channels')
if [ "${c_abnormal}" -gt 0 ]; then
  send_alert high "CLN: Critical channel states" "${c_abnormal} channel(s) have lost state or detected a unilateral funding spend. Verify channel state immediately."
  ALERTS=$((ALERTS + 1))
fi
log "Critical channel states: ${c_abnormal}"

# --- CHECK 5: Forwarding anomaly — high failure rate ---
c_settled=$(get_val "${CURRENT}" '.settled_recent')
c_failed=$(get_val "${CURRENT}" '.failed_recent')
total_forwards=$((c_settled + c_failed))
if [ "${total_forwards}" -gt 50 ]; then
  fail_rate=0
  if [ "${total_forwards}" -gt 0 ]; then
    fail_rate=$((c_failed * 100 / total_forwards))
  fi
  if [ "${fail_rate}" -gt 80 ]; then
    send_alert high "CLN: High forward failure rate" "${c_failed} failed / ${total_forwards} total forwards in last hour (${fail_rate}% failure). Possible routing attack."
    ALERTS=$((ALERTS + 1))
  fi
fi
log "Forwards (1h): settled=${c_settled}, failed=${c_failed}"

# --- CHECK 6: Large forwarding burst ---
c_large=$(get_val "${CURRENT}" '.large_forwards')
if [ "${c_large}" -gt 10 ]; then
  send_alert high "CLN: Large forward burst" "${c_large} forwards > 500k sats in last hour. Unusual large-value routing activity."
  ALERTS=$((ALERTS + 1))
fi
log "Large forwards (1h): ${c_large}"

# --- CHECK 7: Blockheight lag (compare to previous run) ---
c_block=$(get_val "${CURRENT}" '.blockheight')
p_block=''
# Only check if the previous run was at least 10 minutes ago
# If blockheight hasn't advanced at all in 10+ min, node may be stuck
if [ -n "${PREVIOUS}" ]; then
  p_block=$(get_val "${PREVIOUS}" '.blockheight')
  p_timestamp=$(get_val "${PREVIOUS}" '.timestamp')
  p_epoch=$(date -d "${p_timestamp}" +%s 2>/dev/null || echo 0)
  if [ "$(( $(date +%s) - p_epoch ))" -ge 600 ] && [ "${c_block}" -le "${p_block}" ]; then
    # Could be normal if blocks are slow, but worth a note
    log "NOTE: Blockheight unchanged since previous run (${c_block})"
  fi
fi
warning_bitcoind_sync=$(get_val "${CURRENT}" '.warning_bitcoind_sync // ""')
warning_lightningd_sync=$(get_val "${CURRENT}" '.warning_lightningd_sync // ""')
if [ -n "${warning_bitcoind_sync}" ] || [ -n "${warning_lightningd_sync}" ]; then
  send_alert high "CLN: Chain synchronization warning" "bitcoind: ${warning_bitcoind_sync:-none}; lightningd: ${warning_lightningd_sync:-none}"
  ALERTS=$((ALERTS + 1))
fi
log "Blockheight: ${c_block} (previous: ${p_block:-unknown})"

# --- CHECK 8: Pending channels (unexpected inbound) ---
c_pending=$(get_val "${CURRENT}" '.num_remote_pending // 0')
b_pending=$(get_val "${BASELINE}" '.num_remote_pending // 0')
if [ "${c_pending}" -gt "${b_pending}" ] && [ "${c_pending}" -gt 2 ]; then
  send_alert high "CLN: New remote pending channels" "${c_pending} remotely opened pending channels (was ${b_pending}). Verify these are legitimate."
  ALERTS=$((ALERTS + 1))
fi
log "Remote pending channels: ${c_pending} (baseline: ${b_pending})"

# --- CHECK 9: Inactive channels spike ---
c_inactive=$(get_val "${CURRENT}" '.num_inactive')
b_inactive=$(get_val "${BASELINE}" '.num_inactive')
if [ "${c_inactive}" -gt 0 ] && [ "${c_inactive}" -gt "${b_inactive}" ]; then
  send_alert default "CLN: Channels went inactive" "${c_inactive} inactive channels (was ${b_inactive}). Peers may have disconnected."
  ALERTS=$((ALERTS + 1))
fi
log "Inactive channels: ${c_inactive} (baseline: ${b_inactive})"

# --- summary ---
c_active=$(get_val "${CURRENT}" '.num_active')
if [ "${ALERTS}" -eq 0 ]; then
  log "OK — no anomalies detected. peers=${c_peers} htlcs=${c_htlc_count} forwards_1h=${total_forwards} channels=${c_active}/${c_inactive}"
else
  log "WARNING — ${ALERTS} alert(s) triggered"
fi

exit 0
