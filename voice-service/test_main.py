"""API regressions with fake local models: no downloads, microphone, or QBO."""
import asyncio
import importlib.util
from pathlib import Path
import sys
import threading
import time
import types
import unittest
from unittest.mock import patch

import httpx

class FakeWhisper:
    def __init__(self, *args, **kwargs): pass
    def transcribe(self, *args, **kwargs):
        return iter([types.SimpleNamespace(text="month end close")]), types.SimpleNamespace(language="en", duration=1)

class FakePiper:
    @classmethod
    def load(cls, path): return cls()
    def synthesize_wav(self, text, wav_file):
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(22050)
        wav_file.writeframes(b'\0\0' * 100)

spec = importlib.util.spec_from_file_location("voice_test_app", Path(__file__).with_name("main.py"))
module = importlib.util.module_from_spec(spec)
with patch.dict(sys.modules, {"faster_whisper": types.SimpleNamespace(WhisperModel=FakeWhisper), "piper": types.SimpleNamespace(PiperVoice=FakePiper)}):
    spec.loader.exec_module(module)

class VoiceServiceTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        module.transcription_slot = asyncio.Semaphore(1)
        module.synthesis_slot = asyncio.Semaphore(1)
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(app=module.app), base_url="http://test")
    async def asyncTearDown(self): await self.client.aclose()

    async def test_payload_validation(self):
        for payload in [{"text": 3}, {"text": None}, {}, {"text": "x" * 12001}]:
            self.assertEqual((await self.client.post('/speak', json=payload)).status_code, 422)
        self.assertEqual((await self.client.post('/speak', json={"text": "   "})).status_code, 400)
        self.assertEqual((await self.client.post('/speak', json={"text": "hello"})).status_code, 200)

    async def test_upload_limit_and_short_audio(self):
        response = await self.client.post('/transcribe', files={"audio": ("test.wav", b'a')})
        self.assertEqual(response.json()['warning'], 'empty_or_too_short')
        with patch.object(module, 'MAX_AUDIO_BYTES', 1000):
            response = await self.client.post('/transcribe', files={"audio": ("test.wav", b'a' * 1001)})
            self.assertEqual(response.status_code, 413)

    async def test_slow_speech_does_not_block_health_or_transcription(self):
        entered = threading.Event()
        release = threading.Event()
        original = module.piper_voice.synthesize_wav
        def slow(text, wav_file):
            entered.set()
            release.wait(2)
            original(text, wav_file)
        with patch.object(module.piper_voice, 'synthesize_wav', slow):
            started = time.monotonic()
            speech = asyncio.create_task(self.client.post('/speak', json={"text": "hello"}))
            try:
                while not entered.is_set(): await asyncio.sleep(0.01)
                health = await asyncio.wait_for(self.client.get('/health'), 0.5)
                transcript = await asyncio.wait_for(self.client.post('/transcribe', files={"audio": ('test.wav', b'a' * 1000)}), 0.5)
                self.assertEqual(health.status_code, 200)
                self.assertEqual(transcript.json()['text'], 'month end close')
                self.assertLess(time.monotonic() - started, 1)
            finally:
                release.set()
                await speech

if __name__ == '__main__': unittest.main()
