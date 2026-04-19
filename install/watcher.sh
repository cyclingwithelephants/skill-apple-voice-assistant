#!/bin/bash
# Fires on every change to the Voice Memos iCloud sync dir.
# Finds new .m4a files (vs. a seen-set state file) and hands each one to openclaw.

set -euo pipefail

STATE_DIR="${HOME}/.local/state/apple-voice-assistant"
SEEN_FILE="${STATE_DIR}/seen.txt"
LOG_FILE="${STATE_DIR}/watcher.log"
mkdir -p "${STATE_DIR}"
touch "${SEEN_FILE}" "${LOG_FILE}"

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >> "${LOG_FILE}"; }

# Resolve the Voice Memos recordings dir. The modern group-container path
# covers Ventura+; fall back to the legacy Application Support path.
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

# If iCloud has a placeholder (.foo.m4a.icloud) request the actual file.
shopt -s nullglob
for placeholder in "${RECORDINGS_DIR}"/.*.m4a.icloud; do
  log "requesting iCloud download: ${placeholder}"
  /usr/bin/brctl download "${placeholder}" 2>>"${LOG_FILE}" || true
done

# Scan for .m4a files and diff against the seen set.
for memo in "${RECORDINGS_DIR}"/*.m4a; do
  [[ -f "${memo}" ]] || continue
  if ! /usr/bin/grep -Fxq "${memo}" "${SEEN_FILE}"; then
    log "new memo: ${memo}"
    printf '%s\n' "${memo}" >> "${SEEN_FILE}"

    # Hand off to openclaw. Inline file-path pattern — the skill reads the
    # path out of the message, attaches the audio, and transcribes natively.
    if ! /usr/bin/env openclaw agent \
        --message "new voice memo at ${memo}" \
        >> "${LOG_FILE}" 2>&1
    then
      log "ERROR: openclaw invocation failed for ${memo}"
    fi
  fi
done
