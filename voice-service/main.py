"""
Voice Ledger local voice service.

Two endpoints, both fully local/private:
  POST /transcribe  -- audio in, text out (faster-whisper)
  POST /speak        -- text in, wav audio out (Piper TTS)

Neither endpoint computes or knows anything about financial data. This is
pure speech<->text plumbing; the Swift desktop app and its Node backend own
everything that touches real numbers (docs/VOICE_LEDGER_SPEC.md's own
"/voice -- whisper.cpp, local intent parser, optional LLM fallback" line --
faster-whisper substitutes for whisper.cpp here; see
docs/VOICE_LEDGER_HANDOFF.md for why).

No CORS middleware: unlike the browser-based reference app this was ported
from, the only caller here is the native Swift desktop app via URLSession,
which isn't subject to (or helped by) CORS at all.
"""
import io
import os
import wave

from fastapi import FastAPI, UploadFile, File
from fastapi.responses import Response
from faster_whisper import WhisperModel
from piper import PiperVoice

WHISPER_MODEL = os.environ.get("WHISPER_MODEL", "base.en")
PIPER_MODEL_PATH = os.environ.get(
    "PIPER_MODEL_PATH",
    os.path.join(os.path.dirname(__file__), "models", "en_GB-jenny_dioco-medium.onnx"),
)

app = FastAPI(title="voiceledger-voice-service")

print(f"[voice-service] loading whisper model '{WHISPER_MODEL}'...")
whisper_model = WhisperModel(WHISPER_MODEL, device="cpu", compute_type="int8")

print(f"[voice-service] loading piper voice '{PIPER_MODEL_PATH}'...")
piper_voice = PiperVoice.load(PIPER_MODEL_PATH)

print("[voice-service] ready")


@app.get("/health")
def health():
    return {"status": "ok", "whisper_model": WHISPER_MODEL}


@app.post("/transcribe")
async def transcribe(audio: UploadFile = File(...)):
    raw = await audio.read()
    print(f"[voice-service] /transcribe received {len(raw)} bytes ({audio.content_type})")
    if len(raw) < 500:
        # A real recording, even a short one, is at least a few KB. This
        # small almost always means the mic captured nothing (permission
        # granted but silent/wrong device) or the recording was interrupted
        # before any audio was flushed -- not a decode-worthy file at all.
        return {"text": "", "language": None, "duration": 0, "warning": "empty_or_too_short"}
    buf = io.BytesIO(raw)
    try:
        segments, info = whisper_model.transcribe(buf, language="en", vad_filter=True)
        text = " ".join(seg.text.strip() for seg in segments).strip()
        print(f"[voice-service] /transcribe heard: {text!r}")
    except Exception as exc:
        print(f"[voice-service] /transcribe decode failed on {len(raw)} bytes: {exc}")
        return Response(status_code=422, content=f"Could not decode audio: {exc}")
    return {"text": text, "language": info.language, "duration": info.duration}


@app.post("/speak")
async def speak(payload: dict):
    text = (payload or {}).get("text", "").strip()
    if not text:
        return Response(status_code=400, content="text is required")

    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav_file:
        piper_voice.synthesize_wav(text, wav_file)
    buf.seek(0)
    return Response(content=buf.read(), media_type="audio/wav")
