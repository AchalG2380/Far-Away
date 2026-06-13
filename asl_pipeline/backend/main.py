from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routes import suggestions, chat, speech, admin, stitch, predict

app = FastAPI(
    title="CosmicSigns ASL Backend",
    description="Real-time ASL recognition backend for the CosmicSigns retail tablet system.",
    version="1.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(suggestions.router, prefix="/suggestions")
app.include_router(chat.router, prefix="/chat")
app.include_router(speech.router, prefix="/speech")
app.include_router(admin.router, prefix="/admin")
app.include_router(stitch.router, prefix="/stitch")
app.include_router(predict.router)


@app.get("/")
def root():
    return {"status": "running", "version": "1.1.0"}


@app.get("/health")
def health_check():
    """Health probe — used by Flutter on startup and load balancers."""
    return {
        "status": "ok",
        "models": {
            "letter": "asl_letter_model.tflite",
            "word": "Final_ASL_Model_fixed.h5 (Conv1D, 20 classes)",
        },
    }