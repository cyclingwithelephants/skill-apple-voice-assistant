#!/bin/bash
# Health check for the apple-voice-assistant launchd watcher.
# Alerts if the watcher log hasn't been written to in over 24 hours.
# Install as a daily launchd job or cron entry.

set -euo pipefail

STATE_DIR="${HOME}/.local/state/apple-voice-assistant"
LOG_FILE="${STATE_DIR}/watcher.log"
ALERT_FILE="${STATE_DIR}/healthcheck.alert"
MAX_SILENCE_SECONDS=86400  # 24 hours

if [[ ! -f "${LOG_FILE}" ]]; then
  echo "WARN: watcher log does not exist at ${LOG_FILE}" >&2
  exit 1
fi

last_modified=$(stat -f%m "${LOG_FILE}" 2>/dev/null || echo 0)
now=$(date +%s)
age=$(( now - last_modified ))

if (( age > MAX_SILENCE_SECONDS )); then
  hours=$(( age / 3600 ))
  msg="apple-voice-assistant watcher has been silent for ${hours}h (last log entry $(date -r "${last_modified}" +%FT%TZ))"

  # Write alert file for other tools to pick up
  echo "${msg}" > "${ALERT_FILE}"

  # Try to notify via osascript (macOS notification center)
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${msg}\" with title \"Voice Assistant Health Check\" sound name \"Basso\"" 2>/dev/null || true
  fi

  echo "ALERT: ${msg}" >&2
  exit 1
else
  # Clear any previous alert
  rm -f "${ALERT_FILE}"
  exit 0
fi
