from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import json
import os

router = APIRouter()
SETTINGS_FILE = "data/admin_settings.json"

# Default settings
DEFAULT_SETTINGS = {
    "window_mode": "customer_A_input",  # or "employee_A_input"
    "is_online": True,
    "store_type": "default",
    "custom_suggestions_A": [],
    "custom_suggestions_B": []
}


def load_settings():
    if os.path.exists(SETTINGS_FILE):
        with open(SETTINGS_FILE) as f:
            return json.load(f)
    return DEFAULT_SETTINGS.copy()


def save_settings(settings: dict):
    os.makedirs("data", exist_ok=True)
    with open(SETTINGS_FILE, "w") as f:
        json.dump(settings, f, indent=2)


class AdminLoginRequest(BaseModel):
    password: str

class UpdateSettingsRequest(BaseModel):
    password: str
    window_mode: str = None
    is_online: bool = None
    store_type: str = None
    custom_suggestions_A: list = None
    custom_suggestions_B: list = None


@router.post("/login")
def admin_login(req: AdminLoginRequest):
    """Simple password check. Returns a token if correct."""
    if req.password != os.getenv("ADMIN_PASSWORD", "admin123"):
        raise HTTPException(status_code=401, detail="Incorrect password")
    # For hackathon: just return a simple token, not full JWT
    return {"token": "admin_authenticated", "message": "Login successful"}


@router.get("/settings")
def get_settings(token: str):
    """Returns current settings. Requires admin token."""
    if token != "admin_authenticated":
        raise HTTPException(status_code=401, detail="Unauthorized")
    return load_settings()


@router.post("/settings/update")
def update_settings(req: UpdateSettingsRequest):
    """Updates one or more settings."""
    if req.password != os.getenv("ADMIN_PASSWORD", "admin123"):
        raise HTTPException(status_code=401, detail="Unauthorized")
    
    settings = load_settings()
    
    if req.window_mode is not None:
        settings["window_mode"] = req.window_mode
    if req.is_online is not None:
        settings["is_online"] = req.is_online
    if req.store_type is not None:
        settings["store_type"] = req.store_type
    if req.custom_suggestions_A is not None:
        settings["custom_suggestions_A"] = req.custom_suggestions_A
    if req.custom_suggestions_B is not None:
        settings["custom_suggestions_B"] = req.custom_suggestions_B
    
    save_settings(settings)
    return {"status": "updated", "settings": settings}


@router.get("/settings/public")
def get_public_settings():
    """Non-admin endpoint — Flutter calls this on startup to get current mode."""
    settings = load_settings()
    # Only expose what the app needs, not admin credentials
    return {
        "window_mode": settings["window_mode"],
        "is_online": settings["is_online"],
        "store_type": settings["store_type"]
    }