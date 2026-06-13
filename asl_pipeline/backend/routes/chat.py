from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from services.translate_service import translate_text
import uuid
from typing import Dict, List
from datetime import datetime

router = APIRouter()

# In-memory session store — disappears when server restarts
# Structure: { session_id: [ {sender, text, timestamp, edited}, ... ] }
SESSIONS: dict = {}


class ConnectionManager:
    def __init__(self):
        # Map: session_id -> list of WebSocket connections
        self.active_connections: Dict[str, List[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, session_id: str):
        await websocket.accept()
        if session_id not in self.active_connections:
            self.active_connections[session_id] = []
        self.active_connections[session_id].append(websocket)

    def disconnect(self, websocket: WebSocket, session_id: str):
        if session_id in self.active_connections:
            if websocket in self.active_connections[session_id]:
                self.active_connections[session_id].remove(websocket)
            if not self.active_connections[session_id]:
                del self.active_connections[session_id]

    async def broadcast_history(self, session_id: str, history: List[dict]):
        if session_id in self.active_connections:
            # Iterate over a copy to avoid modification during iteration issues
            for connection in list(self.active_connections[session_id]):
                try:
                    await connection.send_json({"type": "history", "history": history})
                except Exception:
                    pass


manager = ConnectionManager()


class StartSessionRequest(BaseModel):
    pass  # No body needed

class MessageRequest(BaseModel):
    session_id: str
    sender: str   # "A" or "B"
    text: str

class TranslateRequest(BaseModel):
    text: str
    target_language: str  # e.g. "hi" for Hindi, "en" for English

class ClearSessionRequest(BaseModel):
    session_id: str


@router.post("/session/start")
def start_session():
    """Creates a new session and returns the ID."""
    session_id = str(uuid.uuid4())
    SESSIONS[session_id] = []
    return {
        "session_id": session_id,
        "greeting": "Hi! Please sign or type what you'd like to say."
    }


@router.post("/session/message")
async def add_message(req: MessageRequest):
    """Adds a message to the session history."""
    if req.session_id not in SESSIONS:
        return {"error": "Session not found"}, 404
    
    message = {
        "sender": req.sender,
        "text": req.text,
        "timestamp": datetime.now().isoformat()
    }
    SESSIONS[req.session_id].append(message)
    
    # Broadcast updated history to all connected websockets
    await manager.broadcast_history(req.session_id, SESSIONS[req.session_id])
    
    return {"status": "ok", "message": message}


@router.get("/session/{session_id}/history")
def get_history(session_id: str):
    """Returns full conversation history for this session."""
    if session_id not in SESSIONS:
        return {"error": "Session not found"}
    return {"history": SESSIONS[session_id]}


@router.post("/session/clear")
async def clear_session(req: ClearSessionRequest):
    """Ends the session and deletes all conversation data."""
    if req.session_id in SESSIONS:
        del SESSIONS[req.session_id]
    
    # Broadcast empty history to all connected websockets
    await manager.broadcast_history(req.session_id, [])
    
    return {"status": "cleared"}


@router.post("/translate")
async def translate(req: TranslateRequest):
    """Translates a piece of text to the target language."""
    translated = await translate_text(req.text, req.target_language)
    return {"original": req.text, "translated": translated, "language": req.target_language}


class EditMessageRequest(BaseModel):
    session_id: str
    message_index: int   # which bubble to edit (its position in history)
    new_text: str
    sender: str          # "A" or "B"


@router.post("/session/message/edit")
async def edit_message(req: EditMessageRequest):
    if req.session_id not in SESSIONS:
        raise HTTPException(status_code=404, detail="Session not found")
    
    history = SESSIONS[req.session_id]
    
    # Check the message exists
    if req.message_index >= len(history):
        raise HTTPException(status_code=404, detail="Message not found")
    
    # Check it belongs to the right sender
    if history[req.message_index]["sender"] != req.sender:
        raise HTTPException(status_code=403, detail="Cannot edit other person's message")
    
    # Check no newer message from same sender exists after this one
    for msg in history[req.message_index + 1:]:
        if msg["sender"] == req.sender:
            raise HTTPException(
                status_code=403, 
                detail="Cannot edit — a newer message from same sender exists"
            )
    
    # All good — edit it
    history[req.message_index]["text"] = req.new_text
    history[req.message_index]["edited"] = True
    
    # Broadcast updated history to all connected websockets
    await manager.broadcast_history(req.session_id, history)
    
    return {"status": "edited", "message": history[req.message_index]}


@router.websocket("/ws/{session_id}")
async def websocket_endpoint(websocket: WebSocket, session_id: str):
    await manager.connect(websocket, session_id)
    # Send initial history
    history = SESSIONS.get(session_id, [])
    try:
        await websocket.send_json({"type": "history", "history": history})
        while True:
            # We just wait for client to close/ping
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket, session_id)
    except Exception:
        manager.disconnect(websocket, session_id)