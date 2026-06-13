import os
import sys
import json
from groq import Groq
from dotenv import load_dotenv

load_dotenv()

# ── SentenceFormatter for offline fallback (no API key required) ─────────────
_ROUTE_DIR   = os.path.dirname(os.path.abspath(__file__))
_BACKEND_DIR = os.path.dirname(_ROUTE_DIR)
_REPO_ROOT   = os.path.dirname(os.path.dirname(_BACKEND_DIR))
_ASL_ML_DIR  = os.path.join(_REPO_ROOT, 'asl_ml')
if _ASL_ML_DIR not in sys.path:
    sys.path.insert(0, _ASL_ML_DIR)

try:
    from sentence_formatter import SentenceFormatter as _SF
    _sentence_fmt = _SF()
    _FORMATTER_AVAILABLE = True
    print("[gemini_service] SentenceFormatter loaded for offline fallback")
except ImportError:
    _FORMATTER_AVAILABLE = False
    print("[gemini_service] SentenceFormatter not available")

# ── Groq client — optional, works without API key (offline fallback used) ─────
_groq_key = os.getenv("GROQ_API_KEY", "").strip()
if _groq_key:
    client = Groq(api_key=_groq_key)
    print("[gemini_service] Groq AI enabled")
else:
    client = None
    print("[gemini_service] No GROQ_API_KEY — using offline fallback (add key to .env for AI features)")
MODEL = "llama-3.3-70b-versatile"
FALLBACK_MODEL = "llama-3.1-8b-instant"

RULE_BASED_FALLBACK = {
    "HELP": ["I need help, please", "Can someone assist me?", "Could you help me?"],
    "PRICE": ["How much does this cost?", "What is the price?", "Can you tell me the price?"],
    "THANK": ["Thank you!", "Thanks very much!", "I really appreciate it"],
    "BATHROOM": ["Where is the bathroom?", "Could you direct me to the restroom?"],
    "BAG": ["Can I get a bag please?", "I need a carry bag"],
    "HELLO": ["Hello!", "Hi there!", "Good day!"],
    "REPEAT": ["Could you please repeat that?", "Sorry, could you say that again?"],
    "DEFAULT": ["Could you help me?", "I have a question", "Excuse me"]
}


def _format_history(history: list) -> str:
    """Safely formats history regardless of whether items are dicts or strings."""
    lines = []
    for m in history[-4:]:
        if isinstance(m, dict):
            lines.append(f"{m.get('sender', '?')}: {m.get('text', '')}")
        else:
            lines.append(str(m))
    return "\n".join(lines)


async def get_smart_suggestion(detected_sign: str, history: list, screen: str, store_type: str):
    try:
        result = await _call_groq(detected_sign, history, screen, store_type, MODEL)
        if result:
            return result
    except Exception as e:
        print(f"Primary model failed: {e}")

    try:
        result = await _call_groq(detected_sign, history, screen, store_type, FALLBACK_MODEL)
        if result:
            return result
    except Exception as e:
        print(f"Fallback model failed: {e}")

    print("Using rule-based fallback")
    return RULE_BASED_FALLBACK.get(detected_sign.upper(), RULE_BASED_FALLBACK["DEFAULT"])


async def get_followup_suggestions(chosen: str, history: list, store_type: str):
    context = _format_history(history)

    prompt = f"""You are a suggestion engine for a retail store ASL tablet.
The user just said: "{chosen}"
Store type: {store_type}
Recent conversation: {context}

Give exactly 3 short follow-up sentences the user might say next.
Return ONLY a JSON array of 3 strings. No explanation. No markdown.
Example: ["I need help with billing", "I need help finding a product", "I need help with a return"]"""

    try:
        if not client:
            raise RuntimeError("No Groq client")
        response = client.chat.completions.create(
            model=MODEL,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=120,
            temperature=0.5
        )
        text = response.choices[0].message.content.strip()
        text = text.replace("```json", "").replace("```", "").strip()
        return json.loads(text)[:3]
    except Exception as e:
        print(f"Followup error: {e}")
        return []


async def get_paraphrase(raw_sign: str, history: list, screen: str, store_type: str):
    context = _format_history(history)
    who = "deaf customer" if screen == "A" else "deaf store employee"

    prompt = f"""You are a translator for a retail store ASL tablet.
A {who} just signed the word: "{raw_sign}"
Store: {store_type}
Recent conversation: {context}

Convert this signed word into ONE natural, complete, polite sentence for a retail context.
Return ONLY the sentence. No explanation. No quotes."""

    try:
        if not client:
            raise RuntimeError("No Groq client")
        response = client.chat.completions.create(
            model=MODEL,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=60,
            temperature=0.3
        )
        return response.choices[0].message.content.strip()
    except Exception as e:
        print(f"Paraphrase error: {e}")
        # ── Offline fallback: SentenceFormatter lookup (no API needed) ──────
        if _FORMATTER_AVAILABLE:
            result = _sentence_fmt.format_sign(raw_sign, language="en")
            return result.get("en", f"I need {raw_sign.lower()}.")
        return f"I need {raw_sign.lower()}."


async def _call_groq(detected_sign, history, screen, store_type, model_name):
    context = _format_history(history)
    who = "deaf customer" if screen == "A" else "deaf store employee"

    prompt = f"""You are a smart suggestion engine for a retail store ASL tablet.
Person signing is a {who} in a {store_type}.
Sign detected: "{detected_sign}"
Recent conversation: {context}

Give exactly 3 short natural sentences this person is likely trying to say.
Return ONLY a JSON array of 3 strings. No explanation. No markdown.
Example: ["I need help", "Can you help me?", "I need assistance"]"""

    if not client:
        raise RuntimeError("No Groq client — offline mode")
    response = client.chat.completions.create(
        model=model_name,
        messages=[{"role": "user", "content": prompt}],
        max_tokens=150,
        temperature=0.4
    )
    text = response.choices[0].message.content.strip()
    text = text.replace("```json", "").replace("```", "").strip()
    return json.loads(text)[:3]