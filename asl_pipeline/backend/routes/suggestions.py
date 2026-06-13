from fastapi import APIRouter
from pydantic import BaseModel
from services.gemini_service import (
    get_smart_suggestion,
    get_followup_suggestions,
    get_paraphrase
)
import json as json_lib

router = APIRouter()

with open("data/predefined_suggestions.json") as f:
    PREDEFINED = json_lib.load(f)

with open("data/rule_templates.json") as f:
    RULE_TEMPLATES = json_lib.load(f)


# --- REQUEST MODELS ---

class SmartSuggestionRequest(BaseModel):
    detected_sign: str
    conversation_history: list   # list of dicts: {"sender": "A", "text": "..."}
    screen: str
    store_type: str = "default"

class FollowupRequest(BaseModel):
    chosen_suggestion: str
    conversation_history: list
    store_type: str = "default"

class PredefinedRequest(BaseModel):
    store_type: str = "default"
    screen: str = "A"

class TemplateRequest(BaseModel):
    detected_sign: str
    screen: str = "A"

class ParaphraseRequest(BaseModel):
    raw_sign: str
    conversation_history: list
    store_type: str = "default"
    screen: str = "A"


# --- ENDPOINTS ---

@router.post("/smart")
async def smart_suggestion(req: SmartSuggestionRequest):
    suggestions = await get_smart_suggestion(
        req.detected_sign,
        req.conversation_history,
        req.screen,
        req.store_type
    )
    return {"suggestions": suggestions}


@router.post("/followup")
async def followup_suggestion(req: FollowupRequest):
    suggestions = await get_followup_suggestions(
        req.chosen_suggestion,
        req.conversation_history,
        req.store_type
    )
    return {"suggestions": suggestions}


@router.post("/predefined")
def predefined_suggestions(req: PredefinedRequest):
    store_data = PREDEFINED.get(req.store_type, PREDEFINED["default"])
    default_data = PREDEFINED["default"]
    combined = default_data[req.screen] + store_data.get(req.screen, [])
    return {"suggestions": list(dict.fromkeys(combined))}


@router.post("/template")
def get_template_suggestions(req: TemplateRequest):
    sign_upper = req.detected_sign.upper()
    for template_name, template in RULE_TEMPLATES.items():
        if sign_upper in template["triggers"]:
            key = f"{req.screen}_responses"
            return {
                "matched": True,
                "template": template_name,
                "suggestions": template.get(key, [])
            }
    return {"matched": False, "suggestions": []}


@router.post("/paraphrase")
async def paraphrase_sign(req: ParaphraseRequest):
    sentence = await get_paraphrase(
        req.raw_sign,
        req.conversation_history,
        req.screen,
        req.store_type
    )
    return {"paraphrased": sentence, "raw": req.raw_sign}