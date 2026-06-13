from fastapi import APIRouter, UploadFile, File
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from services.speech_service import transcribe_audio, synthesize_speech
import io

router = APIRouter()


@router.post("/transcribe")
async def transcribe(audio: UploadFile = File(...)):
    """Receives audio file, returns transcribed text."""
    audio_bytes = await audio.read()
    text = await transcribe_audio(audio_bytes, audio.filename)
    return {"text": text}


class TTSRequest(BaseModel):
    text: str
    language: str = "en"  # for future multi-language TTS


@router.post("/speak")
async def speak(req: TTSRequest):
    """Receives text, returns audio file as streaming response."""
    audio_bytes = await synthesize_speech(req.text)
    return StreamingResponse(
        io.BytesIO(audio_bytes),
        media_type="audio/mpeg",
        headers={"Content-Disposition": "attachment; filename=speech.mp3"}
    )