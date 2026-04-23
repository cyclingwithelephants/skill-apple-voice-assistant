#!/bin/bash
# Installs the apple-voice-assistant openclaw skill and its launchd watcher on a Mac.
# Safe to re-run: it will replace the existing plist and re-bootstrap.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_NAME="apple_voice_assistant"
SKILL_DIR="${HOME}/.openclaw/workspace/skills/${SKILL_NAME}"
STATE_DIR="${HOME}/.local/state/apple-voice-assistant"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
LABEL="com.cyclingwithelephants.apple-voice-assistant"
PLIST_DEST="${LAUNCH_AGENTS_DIR}/${LABEL}.plist"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Validate prerequisites ---
command -v openclaw >/dev/null || die "openclaw not on PATH — install it first (see https://openclaw.ai)"
command -v osascript >/dev/null || die "osascript not found — this skill requires macOS"
command -v timeout >/dev/null || die "timeout(1) not found — install coreutils: brew install coreutils"

# 1. Resolve the Voice Memos recordings dir.
for candidate in \
  "${HOME}/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings" \
  "${HOME}/Library/Application Support/com.apple.voicememos/Recordings"
do
  if [[ -d "${candidate}" ]]; then
    RECORDINGS_DIR="${candidate}"
    break
  fi
done
[[ -n "${RECORDINGS_DIR:-}" ]] || die "Voice Memos recordings dir not found — open Voice Memos once, record a test memo, then re-run"
say "Voice Memos dir: ${RECORDINGS_DIR}"

# 2. Install the skill by symlinking the repo into openclaw's workspace.
mkdir -p "$(dirname "${SKILL_DIR}")"
if [[ -L "${SKILL_DIR}" ]]; then
  rm "${SKILL_DIR}"
elif [[ -e "${SKILL_DIR}" ]]; then
  die "${SKILL_DIR} exists and is not a symlink — move it aside and re-run"
fi
ln -s "${REPO_DIR}" "${SKILL_DIR}"
say "Linked skill: ${SKILL_DIR} -> ${REPO_DIR}"

# 3. Prepare state dir.
mkdir -p "${STATE_DIR}" "${STATE_DIR}/processed"
touch "${STATE_DIR}/seen.txt" "${STATE_DIR}/watcher.log"

# 4. Render the launchd plist with absolute paths.
mkdir -p "${LAUNCH_AGENTS_DIR}"
WATCHER_SCRIPT="${REPO_DIR}/install/watcher.sh"
chmod +x "${WATCHER_SCRIPT}"

sed \
  -e "s|__WATCHER_SCRIPT__|${WATCHER_SCRIPT}|g" \
  -e "s|__RECORDINGS_DIR__|${RECORDINGS_DIR}|g" \
  -e "s|__STATE_DIR__|${STATE_DIR}|g" \
  "${REPO_DIR}/install/${LABEL}.plist" > "${PLIST_DEST}"
say "Wrote launchd plist: ${PLIST_DEST}"

# 5. (Re)load with launchd. `bootout` is a no-op if not loaded.
DOMAIN="gui/$(id -u)"
launchctl bootout "${DOMAIN}" "${PLIST_DEST}" 2>/dev/null || true
launchctl bootstrap "${DOMAIN}" "${PLIST_DEST}"
launchctl enable "${DOMAIN}/${LABEL}"
say "launchd watcher bootstrapped and enabled"

# 6. Install daily health check.
HEALTHCHECK_LABEL="${LABEL}-healthcheck"
HEALTHCHECK_SCRIPT="${REPO_DIR}/install/healthcheck.sh"
HEALTHCHECK_PLIST_DEST="${LAUNCH_AGENTS_DIR}/${HEALTHCHECK_LABEL}.plist"
chmod +x "${HEALTHCHECK_SCRIPT}"

sed \
  -e "s|__HEALTHCHECK_SCRIPT__|${HEALTHCHECK_SCRIPT}|g" \
  -e "s|__STATE_DIR__|${STATE_DIR}|g" \
  "${REPO_DIR}/install/${HEALTHCHECK_LABEL}.plist" > "${HEALTHCHECK_PLIST_DEST}"

launchctl bootout "${DOMAIN}" "${HEALTHCHECK_PLIST_DEST}" 2>/dev/null || true
launchctl bootstrap "${DOMAIN}" "${HEALTHCHECK_PLIST_DEST}"
launchctl enable "${DOMAIN}/${HEALTHCHECK_LABEL}"
say "Daily health check installed (runs at 09:00)"

# 7. Seed or migrate the seen-set to basenames.
# Old installs stored full paths; new format uses basenames only.
# Detect and migrate, or seed fresh if empty.
if [[ -s "${STATE_DIR}/seen.txt" ]]; then
  if head -1 "${STATE_DIR}/seen.txt" | grep -q '/'; then
    say "Migrating seen-set from full paths to basenames..."
    while IFS= read -r line; do
      printf '%s\n' "${line##*/}"
    done < "${STATE_DIR}/seen.txt" > "${STATE_DIR}/seen.txt.tmp"
    mv "${STATE_DIR}/seen.txt.tmp" "${STATE_DIR}/seen.txt"
    say "Migrated seen-set ($(wc -l < "${STATE_DIR}/seen.txt" | tr -d ' ') entries)"
  fi
else
  find "${RECORDINGS_DIR}" -maxdepth 1 -name '*.m4a' -type f -exec basename {} \; > "${STATE_DIR}/seen.txt" || true
  say "Seeded seen-set with existing memos ($(wc -l < "${STATE_DIR}/seen.txt" | tr -d ' ') files)"
fi

cat <<EOF

Install complete.

  skill:     ${SKILL_DIR}
  watcher:   ${WATCHER_SCRIPT}
  plist:     ${PLIST_DEST}
  state:     ${STATE_DIR}
  logs:      ${STATE_DIR}/watcher.log
             ${STATE_DIR}/launchd.{out,err}.log

Record a new voice memo on your iPhone — it should sync to the Mac mini and fire openclaw.
You can tail the watcher log to confirm:

  tail -f "${STATE_DIR}/watcher.log"

To uninstall:

  launchctl bootout "${DOMAIN}" "${PLIST_DEST}"
  launchctl bootout "${DOMAIN}" "${HEALTHCHECK_PLIST_DEST}"
  rm "${PLIST_DEST}" "${HEALTHCHECK_PLIST_DEST}"
  rm "${SKILL_DIR}"

EOF
