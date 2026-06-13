import os
import io
from dotenv import load_dotenv
from groq import Groq
from gtts import gTTS

# Load environment variables
load_dotenv()

# Initialize the Groq client
# Make sure GROQ_API_KEY is added to your .env file
client = Groq(api_key=os.getenv("GROQ_API_KEY"))

async def transcribe_audio(audio_bytes: bytes, filename: str) -> str:
    """Uses Groq Cloud Whisper API to convert audio to text instantly."""
    try:
        # Groq accepts raw bytes directly if formatted as a tuple.
        # This replaces the old logic of saving a temporary file to disk.
        file_tuple = (filename or "audio.webm", audio_bytes)
        
        # Run transcription through Groq's fast API
        transcription = client.audio.transcriptions.create(
            file=file_tuple,
            model="whisper-large-v3-turbo", 
            response_format="json"
        )
        
        return transcription.text
        
    except Exception as e:
        print(f"Groq Whisper STT error: {e}")
        return ""


async def synthesize_speech(text: str) -> bytes:
    """Uses gTTS (Google Text-to-Speech) to convert text to audio bytes."""
    try:
        # Create the gTTS object
        tts = gTTS(text=text, lang='en', slow=False)
        
        # Save the audio to an in-memory bytes buffer
        audio_fp = io.BytesIO()
        tts.write_to_fp(audio_fp)
        
        # Return the bytes exactly as the original OpenAI code did
        return audio_fp.getvalue()
        
    except Exception as e:
        print(f"gTTS error: {e}")
        return b""
    #edited by gemini 