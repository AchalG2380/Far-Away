"""
predict.py — ASL prediction routes for the FastAPI backend.

Endpoints:
  POST /predict        — single frame → letter prediction (basic)
  POST /predict/frame  — single frame → letter + 84 keypoints + boundary state
  POST /predict/word   — 40-frame keypoint sequence → word prediction
  POST /predict/reset  — reset the boundary detector state (call on new session)

New in v1.1:
  BoundaryDetector is now integrated into /predict/frame.
  When the server detects a complete sign boundary (velocity-based), it
  automatically runs the word model and returns:
    - boundary_detected: True
    - word_from_boundary: the detected word
    - formatted_sentence: human-readable sentence (EN)
  This removes the need for the client to guess when classification should run.

  SentenceFormatter is used for the offline formatted_sentence fallback.
"""

import os
import sys
import json
import numpy as np
import cv2

# ── Add asl_ml/ to path so we can import BoundaryDetector + SentenceFormatter ─
_ROUTE_DIR    = os.path.dirname(os.path.abspath(__file__))
_BACKEND_DIR  = os.path.dirname(_ROUTE_DIR)                  # asl_pipeline/backend
_REPO_ROOT    = os.path.dirname(os.path.dirname(_BACKEND_DIR))  # repo root
_ASL_ML_DIR   = os.path.join(_REPO_ROOT, 'asl_ml')

if _ASL_ML_DIR not in sys.path:
    sys.path.insert(0, _ASL_ML_DIR)

# ── Protobuf ≥ 4.x monkey-patch for MediaPipe compatibility ─────────────────
# SymbolDatabase.GetPrototype() was removed in protobuf 4.x.
# MediaPipe's packet_getter.py still calls it; patch it back.
from google.protobuf import symbol_database as _sym_db_mod
from google.protobuf import message_factory as _msg_factory
_sym_db = _sym_db_mod.Default()
if not hasattr(_sym_db, 'GetPrototype'):
    _sym_db.GetPrototype = _msg_factory.GetMessageClass
# ────────────────────────────────────────────────────────────────────────────

import mediapipe as mp

os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
os.environ['TF_ENABLE_ONEDNN_OPTS'] = '0'
import tensorflow as tf
from typing import List, Optional

from fastapi import APIRouter, File, UploadFile
from pydantic import BaseModel

router = APIRouter()

# ── Resolve model paths relative to the repo root ───────────────────────────
_LETTER_MODEL_PATH  = os.path.join(_REPO_ROOT, 'asl_ml', 'models', 'asl_letter_model.tflite')
_LETTER_LABELS_PATH = os.path.join(_REPO_ROOT, 'asl_ml', 'models', 'letter_labels.json')

_WORDS_DIR    = os.path.join(_REPO_ROOT, 'Words')
_META_FILE    = os.path.join(_WORDS_DIR, 'model_meta.json')
_CLASSES_FILE = os.path.join(_WORDS_DIR, 'Final_ASL_Classes.npy')
_WEIGHT_FILES = [
    os.path.join(_WORDS_DIR, 'Final_ASL_Model_fixed.weights.h5'),
    os.path.join(_WORDS_DIR, 'Final_ASL_Model_fixed.h5'),
    os.path.join(_WORDS_DIR, 'Final_ASL_Model.h5'),
]


# ── Pydantic models ──────────────────────────────────────────────────────────

class PredictResponse(BaseModel):
    letter: str
    confidence: float
    detected: bool


class PredictFrameResponse(BaseModel):
    # Letter detection (same as before)
    letter: str
    confidence: float
    detected: bool
    keypoints: List[float]          # 84 floats (x,y only, both hands)

    # NEW — boundary detection fields
    signing_state: str              # "idle" | "signing" | "boundary"
    velocity: float                 # hand movement velocity (for UI animation)
    boundary_detected: bool         # True when a complete sign was just captured
    word_from_boundary: str         # word model result on boundary (if detected)
    word_confidence: float          # word model confidence (if detected)
    formatted_sentence: str         # human-readable sentence (EN) via SentenceFormatter


class WordSequenceRequest(BaseModel):
    sequence: List[List[float]]     # shape (40, 84)


class WordSequenceResponse(BaseModel):
    word: str
    confidence: float
    detected: bool


# ── Lazy-loaded singletons ───────────────────────────────────────────────────

class _HandDetector:
    """MediaPipe Hands for keypoint extraction (lazy-loaded)."""
    _instance = None

    def __init__(self):
        self._hands = mp.solutions.hands.Hands(
            static_image_mode=True,
            max_num_hands=1,
            # Raised from 0.3 → 0.5 to reduce false positives on local hardware
            min_detection_confidence=0.5,
        )

    @classmethod
    def get(cls):
        if cls._instance is None:
            cls._instance = cls()
            print("[predict] MediaPipe Hands initialised (confidence=0.5)")
        return cls._instance

    def extract_keypoints(self, image_bytes: bytes):
        """Returns 126-float keypoint array (2 hands × 21 × 3) or None."""
        arr = np.frombuffer(image_bytes, np.uint8)
        frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if frame is None:
            return None

        frame = cv2.resize(frame, (960, 720))
        img_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = self._hands.process(img_rgb)

        if not results.multi_hand_landmarks:
            return None

        landmarks = np.array(
            [[lm.x, lm.y, lm.z] for lm in results.multi_hand_landmarks[0].landmark],
            dtype=np.float32,
        )
        wrist = landmarks[0].copy()
        landmarks -= wrist
        max_val = np.max(np.abs(landmarks)) + 1e-6
        landmarks /= max_val

        full = np.zeros((2, 21, 3), dtype=np.float32)
        full[0] = landmarks
        return full.flatten()   # shape (126,)


class _LetterPredictor:
    """TFLite letter model (lazy-loaded)."""
    _instance = None

    def __init__(self):
        self.interpreter = tf.lite.Interpreter(model_path=_LETTER_MODEL_PATH)
        self.interpreter.allocate_tensors()
        self.inp = self.interpreter.get_input_details()
        self.out = self.interpreter.get_output_details()

        with open(_LETTER_LABELS_PATH) as f:
            self.labels = json.load(f)

        print(f"[predict] LetterPredictor ready — {len(self.labels)} labels")

    @classmethod
    def get(cls):
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def predict(self, keypoints: np.ndarray):
        """keypoints: shape (126,) → (letter, confidence)"""
        x = keypoints.reshape(1, 126).astype(np.float32)
        self.interpreter.set_tensor(self.inp[0]['index'], x)
        self.interpreter.invoke()
        probs = self.interpreter.get_tensor(self.out[0]['index'])[0]
        idx = int(np.argmax(probs))
        return self.labels[idx], float(probs[idx])


class _WordPredictor:
    """Conv1D/BiLSTM word model (lazy-loaded)."""
    _instance = None

    def __init__(self):
        from tensorflow import keras
        from tensorflow.keras.models import Sequential
        from tensorflow.keras.layers import (
            LSTM, Dense, Dropout, Conv1D, MaxPooling1D,
            BatchNormalization, GlobalAveragePooling1D, Bidirectional,
        )

        # Load metadata
        meta = {}
        if os.path.exists(_META_FILE):
            with open(_META_FILE) as f:
                meta = json.load(f)

        self.max_frames  = int(meta.get('max_frames', 40))
        self.feat_size   = int(meta.get('feat_size', 84))
        self.conf_thresh = 0.50
        self.margin      = 0.10

        # Load classes
        self.classes = [str(c) for c in np.load(_CLASSES_FILE, allow_pickle=True)]
        n_classes = len(self.classes)
        print(f"[predict] WordPredictor — {n_classes} classes: {self.classes}")

        winner = meta.get('winner', 'Conv1D')

        def build_conv1d(fr, ft, nc):
            return Sequential([
                keras.Input(shape=(fr, ft)), BatchNormalization(),
                Conv1D(64, 3, activation='relu', padding='same'), MaxPooling1D(2), Dropout(0.25),
                Conv1D(128, 3, activation='relu', padding='same'), MaxPooling1D(2), Dropout(0.25),
                GlobalAveragePooling1D(), Dense(128, activation='relu'), Dropout(0.4),
                Dense(nc, activation='softmax'),
            ], name='Conv1D')

        def build_bilstm(fr, ft, nc):
            return Sequential([
                keras.Input(shape=(fr, ft)), BatchNormalization(),
                Bidirectional(LSTM(64, return_sequences=True, dropout=0.2)), Dropout(0.3),
                Bidirectional(LSTM(64, return_sequences=False, dropout=0.2)), Dropout(0.3),
                Dense(64, activation='relu'), Dropout(0.4),
                Dense(nc, activation='softmax'),
            ], name='BiLSTM')

        def build_old_lstm(fr, ft, nc):
            return Sequential([
                keras.Input(shape=(fr, ft)),
                LSTM(64, return_sequences=True, activation='tanh'), Dropout(0.2),
                LSTM(128, activation='tanh'), Dropout(0.2),
                Dense(64, activation='relu'),
                Dense(nc, activation='softmax'),
            ], name='OldLSTM')

        arch_order = (
            [('BiLSTM', build_bilstm), ('Conv1D', build_conv1d), ('OldLSTM', build_old_lstm)]
            if winner == 'BiLSTM'
            else [('Conv1D', build_conv1d), ('BiLSTM', build_bilstm), ('OldLSTM', build_old_lstm)]
        )

        self.model = None
        for path in _WEIGHT_FILES:
            if not os.path.exists(path):
                continue
            print(f"[predict] Trying {os.path.basename(path)}")
            try:
                self.model = tf.keras.models.load_model(path, compile=False)
                print(f"[predict] Full load OK  output={self.model.output_shape}")
                break
            except Exception as e:
                print(f"  Full failed: {str(e)[:80]}")

            for arch_name, builder in arch_order:
                try:
                    m = builder(self.max_frames, self.feat_size, n_classes)
                    m.compile(optimizer='adam', loss='categorical_crossentropy', metrics=['accuracy'])
                    m.load_weights(path)
                    self.model = m
                    print(f"[predict] Weights OK ({arch_name})")
                    break
                except Exception as e:
                    print(f"  Weights failed ({arch_name}): {str(e)[:60]}")

            if self.model:
                break

        if self.model is None:
            print("[predict] WARNING: word model not loaded — word detection disabled")

    @classmethod
    def get(cls):
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def predict(self, sequence: list):
        """sequence: list of 40 sub-lists each with 84 floats.
        Returns: (word, confidence, detected)"""
        if self.model is None:
            return '', 0.0, False

        arr = np.array(sequence, dtype='float32')
        if arr.shape != (self.max_frames, self.feat_size):
            return '', 0.0, False

        inp = np.expand_dims(arr, 0)
        probs = self.model(inp, training=False)[0].numpy()

        top_idx  = int(np.argmax(probs))
        top_conf = float(probs[top_idx])
        sec_conf = float(np.sort(probs)[-2])
        margin   = top_conf - sec_conf

        if top_conf >= self.conf_thresh and margin >= self.margin:
            return self.classes[top_idx], top_conf, True
        return '', top_conf, False

    def predict_from_sequence_126(self, frames_126: list):
        """
        Predict word from a list of 126-feature frames (BoundaryDetector output).
        Automatically converts 126 → 84 (x,y only) and pads/trims to max_frames.
        Returns: (word, confidence, detected)
        """
        if self.model is None or not frames_126:
            return '', 0.0, False

        arr126 = np.array(frames_126, dtype=np.float32)  # (N, 126)

        # Pad or sample to max_frames
        n = len(arr126)
        if n < self.max_frames:
            pad = np.zeros((self.max_frames - n, 126), dtype=np.float32)
            arr126 = np.vstack([pad, arr126])
        elif n > self.max_frames:
            indices = np.linspace(0, n - 1, self.max_frames, dtype=int)
            arr126 = arr126[indices]

        # Convert (max_frames, 126) → (max_frames, 84): drop z-coord
        arr = arr126.reshape(self.max_frames, 2, 21, 3)[:, :, :, :2].reshape(self.max_frames, 84)

        inp = np.expand_dims(arr, 0)
        probs = self.model(inp, training=False)[0].numpy()

        top_idx  = int(np.argmax(probs))
        top_conf = float(probs[top_idx])
        sec_conf = float(np.sort(probs)[-2])
        margin   = top_conf - sec_conf

        if top_conf >= self.conf_thresh and margin >= self.margin:
            return self.classes[top_idx], top_conf, True
        return '', top_conf, False


class _BoundaryState:
    """
    Wraps BoundaryDetector as a global singleton.
    There is effectively one signer at a time (single camera), so one
    global instance is appropriate and keeps the API stateless.
    """
    _instance = None

    def __init__(self):
        from boundary_detector import BoundaryDetector
        # Use slightly relaxed thresholds for web camera (400→200ms frames,
        # more compression noise, lower resolution than native webcam)
        self.detector = BoundaryDetector(
            window_size=30,
            velocity_threshold=0.018,   # slightly lower than default 0.02
            rest_frames_needed=4,       # 4 × 200ms = 800ms pause = sign done
            min_signing_frames=8,       # require at least 8 frames of movement
        )
        print("[predict] BoundaryDetector ready")

    @classmethod
    def get(cls):
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def update(self, keypoints):
        return self.detector.update(keypoints)

    def reset(self):
        self.detector._reset()
        print("[predict] BoundaryDetector reset")


class _FormatterState:
    """Wraps SentenceFormatter as a global singleton."""
    _instance = None

    def __init__(self):
        from sentence_formatter import SentenceFormatter
        self.fmt = SentenceFormatter()
        print("[predict] SentenceFormatter ready")

    @classmethod
    def get(cls):
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def format_sign(self, sign: str) -> str:
        """Returns the English sentence for a sign. Falls back to generic."""
        result = self.fmt.format_sign(sign, language="en")
        return result.get("en", f"I need {sign.lower()}.")

    def reset(self):
        self.fmt.reset()


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.post("/predict", response_model=PredictResponse)
async def predict(file: UploadFile = File(...)):
    """Single-frame letter prediction. Flutter sends a JPEG frame."""
    image_bytes = await file.read()
    kp = _HandDetector.get().extract_keypoints(image_bytes)

    if kp is None:
        return PredictResponse(letter="", confidence=0.0, detected=False)

    letter, confidence = _LetterPredictor.get().predict(kp)
    return PredictResponse(letter=letter, confidence=confidence, detected=True)


@router.post("/predict/frame", response_model=PredictFrameResponse)
async def predict_frame(file: UploadFile = File(...)):
    """
    Extended single-frame endpoint — returns letter + 84 keypoints + boundary state.

    The BoundaryDetector tracks hand velocity across calls.
    When boundary_detected=True, word_from_boundary and formatted_sentence
    are populated — the client should use these directly without buffering.
    """
    image_bytes = await file.read()
    kp126 = _HandDetector.get().extract_keypoints(image_bytes)

    # ── Run boundary detector (even on no-hand frames — it needs velocity=0) ──
    boundary_result = _BoundaryState.get().update(kp126)
    signing_state   = boundary_result["state"]
    velocity        = float(boundary_result["velocity"])
    should_classify = boundary_result["should_classify"]
    frame_buffer    = boundary_result.get("buffer") or []

    # ── No hand detected ──────────────────────────────────────────────────────
    if kp126 is None:
        return PredictFrameResponse(
            letter="", confidence=0.0, detected=False, keypoints=[],
            signing_state=signing_state,
            velocity=velocity,
            boundary_detected=False,
            word_from_boundary="",
            word_confidence=0.0,
            formatted_sentence="",
        )

    # ── Letter prediction ─────────────────────────────────────────────────────
    letter, confidence = _LetterPredictor.get().predict(kp126)

    # ── Convert 126 → 84 keypoints (x,y only, for client-side word buffer) ───
    kp126_arr = kp126.reshape(2, 21, 3)
    kp84_arr  = kp126_arr[:, :, :2]
    kp84      = kp84_arr.flatten().tolist()

    # ── Boundary-triggered word prediction ───────────────────────────────────
    word_from_boundary = ""
    word_confidence    = 0.0
    formatted_sentence = ""

    if should_classify and frame_buffer:
        word, w_conf, w_detected = _WordPredictor.get().predict_from_sequence_126(frame_buffer)
        if w_detected and word:
            word_from_boundary = word
            word_confidence    = w_conf
            formatted_sentence = _FormatterState.get().format_sign(word)
            print(f"[predict] Boundary → word='{word}' ({w_conf:.2%}) → '{formatted_sentence}'")
        else:
            # Word model not confident — fall back to the letter as a single-sign sentence
            if letter and confidence >= 0.60:
                formatted_sentence = _FormatterState.get().format_sign(letter)

    return PredictFrameResponse(
        letter=letter,
        confidence=confidence,
        detected=True,
        keypoints=kp84,
        signing_state=signing_state,
        velocity=velocity,
        boundary_detected=(should_classify and bool(word_from_boundary)),
        word_from_boundary=word_from_boundary,
        word_confidence=word_confidence,
        formatted_sentence=formatted_sentence,
    )


@router.post("/predict/word", response_model=WordSequenceResponse)
async def predict_word(req: WordSequenceRequest):
    """
    Word prediction from a 40-frame keypoint sequence (84 features each).
    Called by the Flutter client when it accumulates its own 40-frame buffer.
    Still supported for compatibility, but boundary-based detection via
    /predict/frame is now the preferred approach.
    """
    seq = req.sequence
    if len(seq) < 40:
        return WordSequenceResponse(word="", confidence=0.0, detected=False)

    seq40 = seq[-40:]
    word, confidence, detected = _WordPredictor.get().predict(seq40)
    return WordSequenceResponse(word=word, confidence=confidence, detected=detected)


@router.post("/predict/reset")
async def reset_boundary():
    """
    Reset the boundary detector state. Call this when starting a new session
    or when the user presses 'New Conversation' so leftover signing state
    from the previous session doesn't contaminate the next one.
    """
    _BoundaryState.get().reset()
    _FormatterState.get().reset()
    return {"status": "reset"}


# ── Spelling suggestion models ────────────────────────────────────────────────

class SpellingSuggestRequest(BaseModel):
    partial_word: str           # e.g. "HEL"
    context: str = "retail"    # "retail" | "general"
    max_suggestions: int = 5


class SpellingSuggestResponse(BaseModel):
    suggestions: List[str]      # e.g. ["HELLO", "HELP", "HEY"]
    corrected: str              # best correction if partial looks like a typo, else ""


# Common retail words for offline fallback (covers most signing scenarios)
_RETAIL_WORDS = [
    "HELLO", "HELP", "PLEASE", "THANK", "THANKS", "SORRY", "YES", "NO",
    "PRICE", "COST", "HOW", "WHAT", "WHERE", "WHEN", "WATER", "BATHROOM",
    "CHANGE", "CARD", "CASH", "BAG", "RECEIPT", "REFUND", "EXCHANGE",
    "NAME", "GOOD", "BAD", "MORE", "LESS", "BIG", "SMALL", "DISCOUNT",
    "WAIT", "OPEN", "CLOSE", "BUY", "WANT", "NEED", "HAVE", "GIVE",
    "TIME", "TODAY", "NOW", "FREE", "SALE", "ITEM", "STORE", "DOOR",
]


def _offline_spelling_suggest(partial: str, max_n: int) -> List[str]:
    """Return retail words that start with the partial string."""
    p = partial.upper()
    matches = [w for w in _RETAIL_WORDS if w.startswith(p) and w != p]
    # Also fuzzy: if partial is 3+ chars, allow 1-char off at last position
    if len(matches) < max_n and len(p) >= 3:
        for w in _RETAIL_WORDS:
            if w not in matches and len(w) >= len(p) and w[:len(p)-1] == p[:len(p)-1]:
                matches.append(w)
    return matches[:max_n]


@router.post("/predict/spelling/suggest", response_model=SpellingSuggestResponse)
async def spelling_suggest(req: SpellingSuggestRequest):
    """
    AI-powered fingerspelling autocomplete.

    As the user signs letters one by one, Flutter calls this endpoint with the
    partial word so far. Returns up to 5 word completions.

    - Uses Groq (Llama 3.3) for smart context-aware suggestions.
    - Falls back to offline retail-word list if Groq is unavailable or slow.
    - Also returns a `corrected` field if the partial looks like a 1-off typo
      (e.g. "HLEP" → corrected="HELP").
    """
    partial = req.partial_word.strip().upper()

    if len(partial) < 1:
        return SpellingSuggestResponse(suggestions=[], corrected="")

    # ── Offline fast-path for very short partials (1 char) ───────────────────
    if len(partial) == 1:
        offline = _offline_spelling_suggest(partial, req.max_suggestions)
        return SpellingSuggestResponse(suggestions=offline, corrected="")

    # ── Try Groq for smart completions ────────────────────────────────────────
    try:
        from services.gemini_service import client, MODEL, FALLBACK_MODEL

        prompt = (
            f"You are an ASL fingerspelling assistant for a retail store tablet.\n"
            f"The signer has spelled so far: \"{partial}\"\n"
            f"Context: {req.context} store.\n\n"
            f"Return ONLY a JSON object with two keys:\n"
            f"  \"suggestions\": list of {req.max_suggestions} most likely complete English words "
            f"that start with or closely match \"{partial}\" in a retail context. "
            f"All UPPERCASE. Order by likelihood.\n"
            f"  \"corrected\": if \"{partial}\" looks like a 1-letter signing mistake "
            f"(e.g. adjacent letter on hand), return the most likely intended word (UPPERCASE). "
            f"Otherwise return empty string \"\".\n"
            f"Example: {{\"suggestions\": [\"HELLO\", \"HELP\"], \"corrected\": \"\"}}\n"
            f"Return ONLY the JSON. No explanation."
        )

        resp = client.chat.completions.create(
            model=MODEL,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=120,
            temperature=0.2,
        )
        raw = resp.choices[0].message.content.strip()

        # Strip markdown code fences if present
        if raw.startswith("```"):
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]

        data = json.loads(raw)
        suggestions = [str(s).upper() for s in data.get("suggestions", [])][:req.max_suggestions]
        corrected   = str(data.get("corrected", "")).upper().strip()

        # Merge with offline suggestions to ensure at least 3 results
        offline = _offline_spelling_suggest(partial, req.max_suggestions)
        for w in offline:
            if w not in suggestions:
                suggestions.append(w)
            if len(suggestions) >= req.max_suggestions:
                break

        return SpellingSuggestResponse(suggestions=suggestions, corrected=corrected)

    except Exception as e:
        print(f"[spelling/suggest] Groq failed: {e} — using offline fallback")
        offline = _offline_spelling_suggest(partial, req.max_suggestions)
        return SpellingSuggestResponse(suggestions=offline, corrected="")

