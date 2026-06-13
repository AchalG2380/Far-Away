from fastapi import APIRouter
from pydantic import BaseModel
from routes.suggestions import paraphrase_sign, ParaphraseRequest

router = APIRouter()


class StitchRequest(BaseModel):
    tokens: list
    store_type: str = "default"
    screen: str = "A"
    conversation_history: list = []


@router.post("/")
async def stitch_signs(req: StitchRequest):
    """
    Receives detected tokens (words or letters).
    Figures out if it's fingerspelled or a word sign.
    Returns a paraphrased sentence ready for chat.
    """
    if len(req.tokens) == 1 and len(req.tokens[0]) > 1:
        raw = req.tokens[0]       # single word token e.g. "HELP"
    else:
        raw = "".join(req.tokens) # letters joined e.g. ["H","E","L","P"] → "HELP"

    paraphrase_req = ParaphraseRequest(
        raw_sign=raw,
        conversation_history=req.conversation_history,
        store_type=req.store_type,
        screen=req.screen
    )
    return await paraphrase_sign(paraphrase_req)