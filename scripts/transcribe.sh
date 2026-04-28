#!/bin/bash
# Transcription fallback for apple-voice-assistant skill
# Priority:
# 1) synthetic transcript
# 2) local Whisper API
# 3) Swift SFSpeechRecognizer
# 4) mlx-whisper (M4 GPU)
# 5) faster-whisper (CPU)
# 6) OpenAI Whisper

set -euo pipefail

AUDIO_FILE="$1"
OUTPUT_FILE="${2:-/tmp/apple-voice-assistant-transcript.txt}"
WHISPER_API_BASE="${APPLE_VOICE_ASSISTANT_WHISPER_API_BASE:-http://127.0.0.1:9099}"

# Check for synthetic transcript first
SYNTHETIC="${AUDIO_FILE}.transcript.txt"
if [[ -f "$SYNTHETIC" ]]; then
    cp "$SYNTHETIC" "$OUTPUT_FILE"
    echo "Using synthetic transcript from $SYNTHETIC" >&2
    exit 0
fi

# Prefer a local Whisper API when available.
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    if curl -sf --max-time 5 "${WHISPER_API_BASE}/health" >/dev/null 2>&1; then
        transcript_json="$(mktemp -t apple-voice-assistant-whisper.XXXXXX.json)"
        trap 'rm -f "$transcript_json"' EXIT
        if curl -sf --max-time 180 \
            -F "file=@${AUDIO_FILE}" \
            "${WHISPER_API_BASE}/v1/audio/transcriptions" >"$transcript_json"; then
            text="$(jq -r '.text // ""' "$transcript_json" 2>/dev/null || true)"
            if [[ -n "$text" ]]; then
                printf '%s\n' "$text" >"$OUTPUT_FILE"
                echo "Transcribed using local Whisper API at ${WHISPER_API_BASE}" >&2
                exit 0
            fi
        fi
        rm -f "$transcript_json"
        trap - EXIT
    fi
fi

# Try Swift SFSpeechRecognizer
SWIFT_SCRIPT="/Users/adam/.hermes/tmp_speech_transcribe.swift"
if [[ -f "$SWIFT_SCRIPT" ]]; then
    if swift "$SWIFT_SCRIPT" "$AUDIO_FILE" > "$OUTPUT_FILE" 2>/dev/null; then
        echo "Transcribed using SFSpeechRecognizer" >&2
        exit 0
    fi
fi

PYTHON_BIN="${APPLE_VOICE_ASSISTANT_PYTHON:-/Users/adam/.hermes/hermes-agent/venv/bin/python}"
if [[ ! -x "$PYTHON_BIN" ]]; then
    PYTHON_BIN="$(command -v python3 || true)"
fi

# Try mlx-whisper (Apple Silicon GPU-accelerated, large-v3-turbo)
if [[ -n "$PYTHON_BIN" ]] && "$PYTHON_BIN" - <<'PY' >/dev/null 2>&1
import importlib.util, sys
sys.exit(0 if importlib.util.find_spec('mlx_whisper') else 1)
PY
then
    if "$PYTHON_BIN" - "$AUDIO_FILE" "$OUTPUT_FILE" <<'PY'
import sys
import mlx_whisper

audio_file = sys.argv[1]
out_file = sys.argv[2]
result = mlx_whisper.transcribe(
    audio_file,
    path_or_hf_repo='mlx-community/whisper-large-v3-turbo',
)
text = result['text'].strip()
if not text:
    raise SystemExit(1)
with open(out_file, 'w', encoding='utf-8') as f:
    f.write(text + '\n')
lang = result.get('language', 'unknown')
print(f'mlx-whisper large-v3-turbo lang={lang}', file=sys.stderr)
PY
    then
        echo "Transcribed using mlx-whisper (large-v3-turbo, M4 GPU)" >&2
        exit 0
    fi
fi

# Fallback: faster-whisper (CPU)
if [[ -n "$PYTHON_BIN" ]] && "$PYTHON_BIN" - <<'PY' >/dev/null 2>&1
import importlib.util, sys
sys.exit(0 if importlib.util.find_spec('faster_whisper') else 1)
PY
then
    if "$PYTHON_BIN" - "$AUDIO_FILE" "$OUTPUT_FILE" <<'PY'
import sys
from faster_whisper import WhisperModel

audio_file = sys.argv[1]
out_file = sys.argv[2]
model = WhisperModel('tiny.en', device='cpu', compute_type='int8')
segments, info = model.transcribe(audio_file, beam_size=1, vad_filter=True)
text = ' '.join(seg.text.strip() for seg in segments).strip()
if not text:
    raise SystemExit(1)
with open(out_file, 'w', encoding='utf-8') as f:
    f.write(text + '\n')
print(f'{info.language}:{info.language_probability:.3f}', file=sys.stderr)
PY
    then
        echo "Transcribed using faster-whisper" >&2
        exit 0
    fi
fi

# Try OpenAI Whisper API
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    if bash /opt/homebrew/lib/node_modules/Hermes/skills/openai-whisper-api/scripts/transcribe.sh "$AUDIO_FILE" --out "$OUTPUT_FILE" 2>/dev/null; then
        echo "Transcribed using OpenAI Whisper" >&2
        exit 0
    fi
fi

echo "ERROR: All transcription methods failed" >&2
exit 1
