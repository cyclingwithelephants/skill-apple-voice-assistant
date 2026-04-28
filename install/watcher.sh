#!/bin/bash
# Fires on every change to the Voice Memos iCloud sync dir.
# Finds new Voice Memos audio files (.m4a and .qta) and hands each one to Hermes.
# Serialized via mkdir-based lock. Validates file stability before processing.
#
# Note: new memos are processed sequentially — each Hermes call can take up to
# HERMES_TIMEOUT seconds. With multiple long memos this queues work rather than
# running concurrent transcriptions. Intentional: simpler + safer for reminders,
# files, and outbound audit messages.

set -euo pipefail

export HOME="${HOME:-/Users/adam}"
export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"

STATE_DIR="${HOME}/.local/state/apple-voice-assistant"
SEEN_FILE="${STATE_DIR}/seen.txt"
LOG_FILE="${STATE_DIR}/watcher.log"
LOCK_DIR="${STATE_DIR}/watcher.lock"
PROCESSED_DIR="${STATE_DIR}/processed"
MAX_LOG_BYTES=$((10 * 1024 * 1024))  # 10 MB
HERMES_TIMEOUT="${APPLE_VOICE_ASSISTANT_HERMES_TIMEOUT:-900}"  # 15 minutes per Hermes attempt
LOCK_STALE_SECONDS=$((HERMES_TIMEOUT * 4 + 120))  # covers 3 attempts + retry sleeps
HERMES_SKILL="apple-voice-assistant"
HERMES_TOOLSETS="file,terminal,messaging,memory,todo"
PYTHON_BIN="${APPLE_VOICE_ASSISTANT_PYTHON:-${HERMES_HOME}/hermes-agent/venv/bin/python}"
SELF_CHECK_MODE="${APPLE_VOICE_ASSISTANT_SELF_CHECK:-0}"
AUDIT_TARGET="${APPLE_VOICE_ASSISTANT_AUDIT_TARGET:-}"

# Require timeout(1) from coreutils.
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="$(command -v timeout)"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="$(command -v gtimeout)"
else
  echo "ERROR: timeout(1) not found. Ensure coreutils is installed and on PATH." >&2
  exit 1
fi

TMP_AUDIO_DIR="${STATE_DIR}/tmp-audio"

mkdir -p "${STATE_DIR}" "${PROCESSED_DIR}" "${TMP_AUDIO_DIR}"
touch "${SEEN_FILE}" "${LOG_FILE}"

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >> "${LOG_FILE}"; }

pick_handoff_provider() {
  if [[ -n "${APPLE_VOICE_ASSISTANT_PROVIDER:-}" || -n "${APPLE_VOICE_ASSISTANT_MODEL:-}" ]]; then
    printf '%s\t%s\n' "${APPLE_VOICE_ASSISTANT_PROVIDER:-}" "${APPLE_VOICE_ASSISTANT_MODEL:-}"
    return 0
  fi

  if [[ ! -f "${HERMES_HOME}/auth.json" ]]; then
    printf '%s\t%s\n' "llama-local" "qwen3.6-35b-a3b"
    return 0
  fi

  if "${PYTHON_BIN}" - "${HERMES_HOME}/auth.json" <<'PY' >/dev/null 2>&1
import json
import sys
from pathlib import Path

auth = json.loads(Path(sys.argv[1]).read_text())
providers = auth.get("providers", {})
pool = auth.get("credential_pool", {})

has_codex = bool(providers.get("openai-codex")) or bool(pool.get("openai-codex"))
sys.exit(0 if has_codex else 1)
PY
  then
    printf '%s\t%s\n' "openai-codex" "gpt-5.5"
    return 0
  fi

  if "${PYTHON_BIN}" - "${HERMES_HOME}/auth.json" <<'PY' >/dev/null 2>&1
import json
import sys
from pathlib import Path

auth = json.loads(Path(sys.argv[1]).read_text())
pool = auth.get("credential_pool", {})
has_openrouter = bool(pool.get("openrouter"))
sys.exit(0 if has_openrouter else 1)
PY
  then
    printf '%s\t%s\n' "openrouter" "google/gemini-2.5-flash-preview:free"
    return 0
  fi

  printf '%s\t%s\n' "llama-local" "qwen3.6-35b-a3b"
}

normalized_stem() {
  local name="$1"
  if [[ "$name" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})\ ([0-9]{2})([0-9]{2})([0-9]{2})(-(.+))?$ ]]; then
    local suffix=""
    if [[ -n "${BASH_REMATCH[8]:-}" ]]; then
      suffix="-${BASH_REMATCH[8],,}"
    fi
    printf '%s-%s-%s-%s-%s-%s%s\n' \
      "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" \
      "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}" "${BASH_REMATCH[6]}" \
      "$suffix"
  else
    printf '%s\n' "$name" | tr '[:upper:] ' '[:lower:]-'
  fi
}

# --- Acquire lock (serialize processing, no concurrent runs) ---
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  if [[ -d "${LOCK_DIR}" ]]; then
    # Check for stale lock. Must exceed worst-case normal runtime; otherwise
    # a long transcription can be falsely treated as stale and run concurrently.
    lock_age=$(( $(date +%s) - $(/usr/bin/stat -f%m "${LOCK_DIR}" 2>/dev/null || echo 0) ))
    if (( lock_age > LOCK_STALE_SECONDS )); then
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
  log_size=$(/usr/bin/stat -f%z "${LOG_FILE}" 2>/dev/null || echo 0)
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

if [[ ! -x "${PYTHON_BIN}" ]]; then
  log "ERROR: Hermes Python not found at ${PYTHON_BIN}"
  exit 1
fi

if [[ "${SELF_CHECK_MODE}" == "1" ]]; then
  if ! "${PYTHON_BIN}" - "${RECORDINGS_DIR}" <<'PY' >/dev/null 2>&1
from pathlib import Path
import sys

recordings = Path(sys.argv[1])
if not recordings.is_dir():
    raise SystemExit(1)
for _ in recordings.iterdir():
    break
PY
  then
    log "ERROR: watcher self-check failed to enumerate recordings dir"
    exit 1
  fi
  log "watcher self-check ok"
  exit 0
fi

# --- Collect unseen files and copy them out of the protected Voice Memos dir ---
# macOS TCC currently grants the Nix Python runtime access to Voice Memos, while
# /bin/bash, ls, find, and shell globs can be denied. Keep all directory reads and
# source-file copying inside Python, then hand only the temp copy to shell tools.
declare -a new_memos=()
declare -a new_sources=()
declare -a new_sizes=()

discover_file="$(mktemp "${STATE_DIR}/discover.XXXXXX")"
"${PYTHON_BIN}" - "${RECORDINGS_DIR}" "${SEEN_FILE}" "${TMP_AUDIO_DIR}" >"${discover_file}" 2>>"${LOG_FILE}" <<'PY'
import shutil, sys, time
from pathlib import Path
recordings = Path(sys.argv[1])
seen_file = Path(sys.argv[2])
tmp_dir = Path(sys.argv[3])
seen = set(seen_file.read_text().splitlines()) if seen_file.exists() else set()
tmp_dir.mkdir(parents=True, exist_ok=True)
for src in sorted(recordings.iterdir(), key=lambda p: p.stat().st_mtime):
    if not src.is_file():
        continue
    if src.suffix.lower() not in {'.m4a', '.qta'}:
        continue
    if src.name in seen:
        continue
    st1 = src.stat()
    if st1.st_size <= 0:
        continue
    time.sleep(2)
    st2 = src.stat()
    if st1.st_size != st2.st_size:
        print(f"SYNCING\t{src}\t{st1.st_size}->{st2.st_size}", file=sys.stderr)
        continue
    dest = tmp_dir / src.name
    shutil.copy2(src, dest)
    print(f"{dest}\t{src}\t{st2.st_size}")
PY
while IFS=$'\t' read -r copied source size; do
  [[ -n "${copied:-}" ]] || continue
  new_memos+=("${copied}")
  new_sources+=("${source}")
  new_sizes+=("${size}")
done < "${discover_file}"
rm -f "${discover_file}"

# --- Process new audio files ---
for i in "${!new_memos[@]}"; do
  memo="${new_memos[$i]}"
  source_memo="${new_sources[$i]}"
  memo_basename="${source_memo##*/}"
  memo_ext="${memo_basename##*.}"

  # Validate audio integrity on the temp copy
  if command -v afinfo >/dev/null 2>&1; then
    if ! afinfo "${memo}" &>/dev/null; then
      log "WARN: afinfo failed, file may be corrupt: ${memo_basename}"
      continue
    fi
  fi

  # Flag non-standard filenames (renamed memos, non-English locales).
  # Still process them, but the skill should treat these as medium confidence
  # since we can't derive a reliable timestamp from the filename.
  if [[ ! "${memo_basename}" =~ ^[0-9]{8}\ [0-9]{6}(-[A-Z0-9]+)?\.(m4a|qta)$ ]]; then
    log "WARN: non-standard filename, processing with reduced confidence: ${memo_basename}"
  fi

  memo_id="${memo_basename%.*}"
  normalized_name="$(normalized_stem "${memo_id}")"

  handoff_path="${memo}"
  if [[ "${memo_ext}" == "qta" ]]; then
    converted_m4a="${TMP_AUDIO_DIR}/${normalized_name}.m4a"
    if afconvert -f m4af -d aac "${memo}" "${converted_m4a}" >/dev/null 2>&1; then
      handoff_path="${converted_m4a}"
      log "converted qta to m4a: ${memo_basename} -> ${converted_m4a##*/}"
    else
      log "ERROR: failed to convert qta to m4a: ${memo_basename}"
      continue
    fi
  fi

  log "new memo: ${memo_basename}"

  session_id="apple-voice-assistant:${normalized_name}"
  IFS=$'\t' read -r HERMES_PROVIDER HERMES_MODEL < <(pick_handoff_provider)
  provider_args=()
  if [[ -n "${HERMES_PROVIDER}" ]]; then
    provider_args+=(--provider "${HERMES_PROVIDER}")
  fi
  if [[ -n "${HERMES_MODEL}" ]]; then
    provider_args+=(--model "${HERMES_MODEL}")
  fi
  log "using Hermes provider=${HERMES_PROVIDER:-default} model=${HERMES_MODEL:-default} for ${memo_basename}"

  # Hand off to Hermes with a timeout.
  # Current Hermes CLI uses `chat -q`; the old OpenClaw flags (--agent,
  # --session-id, --deliver, --reply-*) no longer exist.
  prompt=$'new voice memo at `'
  prompt+="${handoff_path}"
  prompt+=$'`\n\nProcess it with apple-voice-assistant.'
  if [[ -n "${AUDIT_TARGET}" ]]; then
    prompt+=$' At the audit step, send the audit summary using explicit target `'
    prompt+="${AUDIT_TARGET}"
    prompt+=$'` if the messaging tool is available; otherwise print the audit summary to stdout.'
  else
    prompt+=$' At the audit step, send the audit summary through the configured messaging channel if available; otherwise print the audit summary to stdout.'
  fi

  handoff_ok=0
  for attempt in 1 2 3; do
    if "${TIMEOUT_BIN}" "${HERMES_TIMEOUT}" \
      "${PYTHON_BIN}" "${HERMES_HOME}/hermes-agent/hermes" chat \
        --source "apple-voice-assistant" \
        --skills "${HERMES_SKILL}" \
        --toolsets "${HERMES_TOOLSETS}" \
        --pass-session-id \
        --quiet \
        "${provider_args[@]}" \
        --query "${prompt}" \
        >> "${LOG_FILE}" 2>&1; then
      handoff_ok=1
      break
    fi
    log "WARN: Hermes handoff failed for ${memo_basename} (attempt ${attempt}/3)"
    sleep 5
  done
  if [[ "${handoff_ok}" -eq 1 ]]; then
    # Record in seen-set only after Hermes accepted the handoff. If handoff fails,
    # leave it unseen so a later watcher run can retry.
    printf '%s\n' "${memo_basename}" >> "${SEEN_FILE}"
  else
    log "ERROR: Hermes invocation failed after retries for ${memo_basename}"
  fi
done

# --- Heartbeat: always touch the log so healthcheck knows we ran ---
log "watcher run complete"
