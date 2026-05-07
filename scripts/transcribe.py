#!/usr/bin/env python3
"""Transcription fallback helper for Apple Voice Assistant."""

from __future__ import annotations

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import uuid
from pathlib import Path


def have_module(name: str) -> bool:
    return importlib.util.find_spec(name) is not None


def write(text: str, output: Path) -> None:
    output.write_text(text.strip() + "\n", encoding="utf-8")


def synthetic(audio: Path, output: Path) -> bool:
    source = Path(str(audio) + ".transcript.txt")
    if not source.exists():
        return False
    shutil.copyfile(source, output)
    print(f"Using synthetic transcript from {source}", file=sys.stderr)
    return True


def local_api(audio: Path, output: Path) -> bool:
    base = os.environ.get("APPLE_VOICE_ASSISTANT_WHISPER_API_BASE", "http://127.0.0.1:9099")
    try:
        urllib.request.urlopen(f"{base}/health", timeout=5).close()
    except Exception:
        return False
    boundary = f"----apple-voice-assistant-{uuid.uuid4().hex}"
    body = b"".join([
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="file"; filename="{audio.name}"\r\n'.encode(),
        b"Content-Type: application/octet-stream\r\n\r\n",
        audio.read_bytes(),
        f"\r\n--{boundary}--\r\n".encode(),
    ])
    req = urllib.request.Request(
        f"{base}/v1/audio/transcriptions",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            text = json.loads(resp.read().decode()).get("text", "").strip()
    except Exception:
        return False
    if not text:
        return False
    write(text, output)
    print(f"Transcribed using local Whisper API at {base}", file=sys.stderr)
    return True


def swift(audio: Path, output: Path) -> bool:
    script = Path(os.environ.get("APPLE_VOICE_ASSISTANT_SWIFT_TRANSCRIBE", ""))
    if not script.exists():
        runtime_home = Path(os.environ.get("HERMES_HOME", str(Path.home() / ".hermes")))
        script = runtime_home / "tmp_speech_transcribe.swift"
    if not script.exists() or shutil.which("swift") is None:
        return False
    with output.open("w", encoding="utf-8") as out:
        ok = subprocess.run(["swift", str(script), str(audio)], stdout=out, stderr=subprocess.DEVNULL).returncode == 0
    if ok:
        print("Transcribed using SFSpeechRecognizer", file=sys.stderr)
    return ok


def mlx_whisper(audio: Path, output: Path) -> bool:
    if not have_module("mlx_whisper"):
        return False
    import mlx_whisper
    result = mlx_whisper.transcribe(str(audio), path_or_hf_repo="mlx-community/whisper-large-v3-turbo")
    text = result.get("text", "").strip()
    if not text:
        return False
    write(text, output)
    print(f"mlx-whisper large-v3-turbo lang={result.get('language', 'unknown')}", file=sys.stderr)
    return True


def faster_whisper(audio: Path, output: Path) -> bool:
    if not have_module("faster_whisper"):
        return False
    from faster_whisper import WhisperModel
    model = WhisperModel("tiny.en", device="cpu", compute_type="int8")
    segments, info = model.transcribe(str(audio), beam_size=1, vad_filter=True)
    text = " ".join(seg.text.strip() for seg in segments).strip()
    if not text:
        return False
    write(text, output)
    print(f"{info.language}:{info.language_probability:.3f}", file=sys.stderr)
    return True


def openai_whisper(audio: Path, output: Path) -> bool:
    helper = os.environ.get("APPLE_VOICE_ASSISTANT_OPENAI_WHISPER_SCRIPT", "/opt/homebrew/lib/node_modules/Hermes/skills/openai-whisper-api/scripts/transcribe.sh")
    if not os.environ.get("OPENAI_API_KEY") or not Path(helper).exists():
        return False
    return subprocess.run(["bash", helper, str(audio), "--out", str(output)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: transcribe.py AUDIO_FILE [OUTPUT_FILE]", file=sys.stderr)
        return 2
    audio = Path(sys.argv[1])
    output = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(tempfile.gettempdir()) / "apple-voice-assistant-transcript.txt"
    for method in (synthetic, local_api, swift, mlx_whisper, faster_whisper, openai_whisper):
        try:
            if method(audio, output):
                return 0
        except Exception as exc:
            print(f"{method.__name__} failed: {exc}", file=sys.stderr)
    print("ERROR: All transcription methods failed", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
