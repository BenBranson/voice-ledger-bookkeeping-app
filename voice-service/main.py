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
import asyncio
import io
import logging
import os
import wave

from fastapi import FastAPI, UploadFile, File
from fastapi.responses import Response
from starlette.concurrency import run_in_threadpool
from pydantic import BaseModel, Field
from faster_whisper import WhisperModel
from piper import PiperVoice

WHISPER_MODEL = os.environ.get("WHISPER_MODEL", "base.en")
PIPER_MODEL_PATH = os.environ.get(
    "PIPER_MODEL_PATH",
    os.path.join(os.path.dirname(__file__), "models", "en_GB-jenny_dioco-medium.onnx"),
)

app = FastAPI(title="voiceledger-voice-service")
logger = logging.getLogger("voiceledger.voice")

print(f"[voice-service] loading whisper model '{WHISPER_MODEL}'...")
whisper_model = WhisperModel(WHISPER_MODEL, device="cpu", compute_type="int8")

print(f"[voice-service] loading piper voice '{PIPER_MODEL_PATH}'...")
piper_voice = PiperVoice.load(PIPER_MODEL_PATH)

# Serialize each model independently; CPU inference must not block the event
# loop or stop health checks/transcription while a reply is synthesized.
transcription_slot = asyncio.Semaphore(1)
synthesis_slot = asyncio.Semaphore(1)
MAX_AUDIO_BYTES = 32 * 1024 * 1024

class SpeechRequest(BaseModel):
    text: str = Field(min_length=1, max_length=12_000)

print("[voice-service] ready")


@app.get("/health")
def health():
    return {"status": "ok", "whisper_model": WHISPER_MODEL}


@app.post("/transcribe")
async def transcribe(audio: UploadFile = File(...)):
    raw = await audio.read(MAX_AUDIO_BYTES + 1)
    await audio.close()
    if len(raw) > MAX_AUDIO_BYTES:
        return Response(status_code=413, content="Audio exceeds the 32 MB limit")
    async with transcription_slot:
        return await run_in_threadpool(transcribe_audio, raw)


def transcribe_audio(raw: bytes):
    logger.info("/transcribe received %d bytes", len(raw))
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
        logger.info("/transcribe completed (%d characters)", len(text))
    except Exception as exc:
        logger.warning("/transcribe failed for %d bytes: %s", len(raw), exc)
        return Response(status_code=422, content="Could not decode audio")
    return {"text": text, "language": info.language, "duration": info.duration}


@app.post("/speak")
async def speak(payload: SpeechRequest):
    text = payload.text.strip()
    if not text:
        return Response(status_code=400, content="text is required")

    async with synthesis_slot:
        return await run_in_threadpool(synthesize_audio, text)


def synthesize_audio(text: str):
    try:
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wav_file:
            piper_voice.synthesize_wav(text, wav_file)
        buf.seek(0)
        return Response(content=buf.read(), media_type="audio/wav")
    except Exception as exc:
        logger.warning("/speak failed: %s", exc)
        return Response(status_code=503, content="Speech synthesis is temporarily unavailable")
