#!/bin/bash
# Fires on every change to the Voice Memos iCloud sync dir.
# Finds new .m4a files (vs. a seen-set of basenames) and hands each one to openclaw.
# Serialized via mkdir-based lock. Validates file stability before processing.

set -euo pipefail

STATE_DIR="${HOME}/.local/state/apple-voice-assistant"
SEEN_FILE="${STATE_DIR}/seen.txt"
LOG_FILE="${STATE_DIR}/watcher.log"
LOCK_DIR="${STATE_DIR}/watcher.lock"
PROCESSED_DIR="${STATE_DIR}/processed"
MAX_LOG_BYTES=$((10 * 1024 * 1024))  # 10 MB
OPENCLAW_TIMEOUT=300                   # 5 minutes

mkdir -p "${STATE_DIR}" "${PROCESSED_DIR}"
touch "${SEEN_FILE}" "${LOG_FILE}"

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >> "${LOG_FILE}"; }

# --- Log rotation: truncate if over MAX_LOG_BYTES ---
if [[ -f "${LOG_FILE}" ]]; then
  log_size=$(stat -f%z "${LOG_FILE}" 2>/dev/null || echo 0)
  if (( log_size > MAX_LOG_BYTES )); then
    tail -c $(( MAX_LOG_BYTES / 2 )) "${LOG_FILE}" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "${LOG_FILE}"
    log "rotated log (was ${log_size} bytes)"
  fi
fi

# --- Acquire lock (serialize processing, no concurrent runs) ---
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  # Check for stale lock: if the lock dir is older than OPENCLAW_TIMEOUT*2, remove it
  if [[ -d "${LOCK_DIR}" ]]; then
    lock_age=$(( $(date +%s) - $(stat -f%m "${LOCK_DIR}" 2>/dev/null || echo 0) ))
    if (( lock_age > OPENCLAW_TIMEOUT * 2 )); then
      log "removing stale lock (age: ${lock_age}s)"
      rmdir "${LOCK_DIR}" 2>/dev/null || true
      mkdir "${LOCK_DIR}" 2>/dev/null || { log "still locked after stale removal"; exit 0; }
    else
      log "another instance running (lock age: ${lock_age}s), exiting"
      exit 0
    fi
  fi
fi
trap 'rmdir "${LOCK_DIR}" 2>/dev/null' EXIT

# --- Resolve the Voice Memos recordings dir ---
for candidate in \
  "${HOME}/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings" \
  "${HOME}/Library/Application Support/com.apple.voicememos/Recordings"
do
  if [[ -d "${candidate}" ]]; then
    RECORDINGS_DIR="${candidate}"
    break
  fi
done

if [[ -z "${RECORDINGS_DIR:-}" ]]; then
  log "ERROR: no Voice Memos recordings dir found"
  exit 1
fi

# --- Request downloads for iCloud placeholders ---
shopt -s nullglob
if command -v brctl >/dev/null 2>&1; then
  for placeholder in "${RECORDINGS_DIR}"/.*.m4a.icloud; do
    log "requesting iCloud download: ${placeholder}"
    brctl download "${placeholder}" 2>>"${LOG_FILE}" || true
  done
fi

# --- Scan for new .m4a files ---
for memo in "${RECORDINGS_DIR}"/*.m4a; do
  [[ -f "${memo}" ]] || continue

  basename="${memo##*/}"

  # Validate filename matches expected Voice Memos pattern
  if [[ ! "${basename}" =~ ^[0-9]{8}\ [0-9]{6}\.m4a$ ]]; then
    log "WARN: unexpected filename pattern, skipping: ${basename}"
    continue
  fi

  # Check against seen-set (basenames only)
  if /usr/bin/grep -Fxq "${basename}" "${SEEN_FILE}" 2>/dev/null; then
    continue
  fi

  # Skip empty or partial files
  if [[ ! -s "${memo}" ]]; then
    log "skipping empty file: ${basename}"
    continue
  fi

  # Wait for file stability: size must not change over 2 seconds
  size1=$(stat -f%z "${memo}" 2>/dev/null) || continue
  sleep 2
  size2=$(stat -f%z "${memo}" 2>/dev/null) || continue
  if [[ "${size1}" != "${size2}" ]]; then
    log "file still syncing (size changed ${size1} -> ${size2}): ${basename}"
    continue
  fi

  # Validate audio integrity
  if command -v afinfo >/dev/null 2>&1; then
    if ! afinfo "${memo}" &>/dev/null; then
      log "WARN: afinfo failed, file may be corrupt: ${basename}"
      continue
    fi
  fi

  log "new memo: ${basename}"

  # Record in seen-set (basename only, for consistent matching)
  printf '%s\n' "${basename}" >> "${SEEN_FILE}"

  # Hand off to openclaw with a timeout.
  # The skill reads the path out of the message, attaches the audio, and transcribes.
  if ! (
    # Background kill timer
    ( sleep "${OPENCLAW_TIMEOUT}"; kill 0 2>/dev/null ) &
    timer_pid=$!
    /usr/bin/env openclaw agent \
      --message "new voice memo at ${memo}" \
      >> "${LOG_FILE}" 2>&1
    kill "${timer_pid}" 2>/dev/null
  ); then
    log "ERROR: openclaw invocation failed or timed out for ${basename}"
  fi
done
