#!/usr/bin/env bash
# Register the voice-memo webhook subscription with Hermes gateway.
# Idempotent — removes existing subscription before creating.
# Writes the generated webhook secret to the env file so process-memo.py can sign requests.
# Run after the gateway is up: hermes webhook subscribe ...
set -euo pipefail

: "${HOME:?HOME must be set}"
export HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
export PATH="${HERMES_HOME}/hermes-agent/venv/bin:/run/current-system/sw/bin:/usr/bin:/bin:$PATH"

STATE_DIR="${HOME}/.local/state/apple-voice-assistant"
ENV_FILE="${STATE_DIR}/env"
HERMES="${HERMES_HOME}/hermes-agent/venv/bin/python ${HERMES_HOME}/hermes-agent/hermes"

# Audit target — must be set (e.g. matrix:!roomid:server.example.com)
: "${APPLE_VOICE_ASSISTANT_AUDIT_TARGET:?Set APPLE_VOICE_ASSISTANT_AUDIT_TARGET to your Matrix room target (e.g. matrix:!roomid:server.example.com)}"

# Remove existing subscription (ignore errors if it doesn't exist)
$HERMES webhook remove voice-memo 2>/dev/null || true

# Create the subscription and capture output to extract the secret
output=$($HERMES webhook subscribe voice-memo \
  --prompt 'New voice memo from the user.

Memo ID: {memo_id}
Source: {source_filename}
Source mtime: {source_mtime}
Source size (bytes): {source_size_bytes}
Archive: {archive_path}

Transcript:
{transcript}

Follow SKILL.md. Classify the transcript (Step 2), then STOP and read references/action_<STATE>.md where STATE is your classification. Follow that file step-by-step.' \
  --skills apple-voice-assistant \
  --deliver matrix \
  --deliver-chat-id "${APPLE_VOICE_ASSISTANT_AUDIT_TARGET#matrix:}" \
  --description 'Process voice memos: classify transcript, act per skill, audit to Matrix' 2>&1)

echo "$output"

# Extract secret from output and write to env file
secret=$(echo "$output" | sed -n 's/.*Secret:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)
if [[ -n "$secret" ]]; then
  mkdir -p "$STATE_DIR"
  # Remove old webhook secret line if present, then append new one
  if [[ -f "$ENV_FILE" ]]; then
    grep -v '^APPLE_VOICE_ASSISTANT_WEBHOOK_SECRET=' "$ENV_FILE" > "${ENV_FILE}.tmp" || true
    mv "${ENV_FILE}.tmp" "$ENV_FILE"
  fi
  echo "APPLE_VOICE_ASSISTANT_WEBHOOK_SECRET=${secret}" >> "$ENV_FILE"
  chmod 0600 "$ENV_FILE"
  echo "Webhook secret written to ${ENV_FILE}"
else
  echo "WARNING: could not extract webhook secret from output" >&2
fi

echo "voice-memo webhook registered"
