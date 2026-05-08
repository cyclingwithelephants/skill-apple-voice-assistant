#!/bin/bash
# Thin wrapper for watcher.py — sets up PATH and env for launchd/Nix,
# then hands off to Python for all logic.

set -euo pipefail

: "${HOME:?HOME must be set}"
export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"

PYTHON_BIN="${APPLE_VOICE_ASSISTANT_PYTHON:-${HERMES_HOME}/hermes-agent/venv/bin/python}"
if [[ ! -x "${PYTHON_BIN}" ]]; then
  PYTHON_BIN="$(command -v python3 || true)"
fi
if [[ -z "${PYTHON_BIN}" ]]; then
  echo "ERROR: no Python interpreter found" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${PYTHON_BIN}" "${SCRIPT_DIR}/watcher.py" "$@"
