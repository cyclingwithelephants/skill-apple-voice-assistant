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

# --- Acquire lock (serialize processing, no concurrent runs) ---
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  if [[ -d "${LOCK_DIR}" ]]; then
    # Check for stale lock: if older than OPENCLAW_TIMEOUT*2, remove and re-acquire
    lock_age=$(( $(date +%s) - $(stat -f%m "${LOCK_DIR}" 2>/dev/null || echo 0) ))
    if (( lock_age > OPENCLAW_TIMEOUT * 2 )); then
      log "removing stale lock (age: ${lock_age}s)"
      rm -rf "${LOCK_DIR}"
      mkdir "${LOCK_DIR}" 2>/dev/null || { log "still locked after stale removal"; exit 0; }
    else
      log "another instance running (lock age: ${lock_age}s), exiting"
      exit 0
    fi
  else
    # Lock dir vanished between mkdir fail and -d check — retry once
    mkdir "${LOCK_DIR}" 2>/dev/null || { log "lock race, exiting"; exit 0; }
  fi
fi
trap 'rm -rf "${LOCK_DIR}" 2>/dev/null' EXIT

# --- Log rotation: truncate if over MAX_LOG_BYTES ---
if [[ -f "${LOG_FILE}" ]]; then
  log_size=$(stat -f%z "${LOG_FILE}" 2>/dev/null || echo 0)
  if (( log_size > MAX_LOG_BYTES )); then
    tail -c $(( MAX_LOG_BYTES / 2 )) "${LOG_FILE}" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "${LOG_FILE}"
    log "rotated log (was ${log_size} bytes)"
  fi
fi

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

# --- Batch file stability check ---
# Snapshot sizes for all .m4a files, sleep once, then recheck.
# Files whose size changed are still syncing and will be skipped.
declare -A file_sizes
for memo in "${RECORDINGS_DIR}"/*.m4a; do
  [[ -f "${memo}" ]] || continue
  file_sizes["${memo}"]=$(stat -f%z "${memo}" 2>/dev/null || echo -1)
done

if (( ${#file_sizes[@]} > 0 )); then
  sleep 2
fi

# --- Process new .m4a files ---
for memo in "${RECORDINGS_DIR}"/*.m4a; do
  [[ -f "${memo}" ]] || continue

  memo_basename="${memo##*/}"

  # Check against seen-set (basenames only)
  if /usr/bin/grep -Fxq "${memo_basename}" "${SEEN_FILE}" 2>/dev/null; then
    continue
  fi

  # Skip empty or partial files
  if [[ ! -s "${memo}" ]]; then
    log "skipping empty file: ${memo_basename}"
    continue
  fi

  # Check file stability from batch snapshot
  size_before="${file_sizes["${memo}"]:-0}"
  size_now=$(stat -f%z "${memo}" 2>/dev/null || echo -1)
  if [[ "${size_before}" != "${size_now}" ]]; then
    log "file still syncing (size changed ${size_before} -> ${size_now}): ${memo_basename}"
    continue
  fi

  # Validate audio integrity
  if command -v afinfo >/dev/null 2>&1; then
    if ! afinfo "${memo}" &>/dev/null; then
      log "WARN: afinfo failed, file may be corrupt: ${memo_basename}"
      continue
    fi
  fi

  # Flag non-standard filenames (renamed memos, non-English locales).
  # Still process them, but the skill should treat these as medium confidence
  # since we can't derive a reliable timestamp from the filename.
  if [[ ! "${memo_basename}" =~ ^[0-9]{8}\ [0-9]{6}\.m4a$ ]]; then
    log "WARN: non-standard filename, processing with reduced confidence: ${memo_basename}"
  fi

  log "new memo: ${memo_basename}"

  # Record in seen-set (basename only, for consistent matching)
  printf '%s\n' "${memo_basename}" >> "${SEEN_FILE}"

  # Hand off to openclaw with a PID-targeted timeout.
  /usr/bin/env openclaw agent \
    --message "new voice memo at ${memo}" \
    >> "${LOG_FILE}" 2>&1 &
  oclaw_pid=$!
  ( sleep "${OPENCLAW_TIMEOUT}"; kill "${oclaw_pid}" 2>/dev/null ) &
  timer_pid=$!
  if ! wait "${oclaw_pid}" 2>/dev/null; then
    log "ERROR: openclaw invocation failed or timed out for ${memo_basename}"
  fi
  kill "${timer_pid}" 2>/dev/null || true
  wait "${timer_pid}" 2>/dev/null || true
done

# --- Heartbeat: always touch the log so healthcheck knows we ran ---
log "watcher run complete"
