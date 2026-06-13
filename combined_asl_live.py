"""
combined_asl_live.py  --  Single-window, single-camera ASL detector
    python combined_asl_live.py

Auto-detects WORD vs LETTER:
  - Hand moving (large spread over 1 sec)  -> Word model
  - Hand held still for ~1 sec             -> Letter model

Motion is measured as the SPATIAL SPREAD (std-dev) of the wrist
position over the last 30 frames, NOT frame-to-frame delta.
This makes the detector immune to mediapipe jitter / small shakes.

Keys: Q=quit  C=clear  S=toggle status  D=debug velocity
"""

import os, sys, json
import threading
import asyncio
import websockets
from queue import Queue
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
os.environ['TF_ENABLE_ONEDNN_OPTS'] = '0'

import cv2
import numpy as np
import mediapipe as mp
import mediapipe.python.solutions as mp_solutions
mp.solutions = mp_solutions

# ── Protobuf ≥ 4.x monkey-patch for MediaPipe compatibility ──────────────────
# SymbolDatabase.GetPrototype() was removed in protobuf 4.x.
# MediaPipe's packet_getter.py still calls it; patch it back to the modern equivalent.
from google.protobuf import symbol_database as _sym_db_mod
from google.protobuf import message_factory as _msg_factory
_sym_db = _sym_db_mod.Default()
if not hasattr(_sym_db, 'GetPrototype'):
    _sym_db.GetPrototype = _msg_factory.GetMessageClass
# ─────────────────────────────────────────────────────────────────────────────

import tensorflow as tf
from tensorflow import keras
from collections import deque
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import (
    LSTM, Dense, Dropout, Conv1D, MaxPooling1D,
    BatchNormalization, GlobalAveragePooling1D, Bidirectional
)

# ─────────────────────────────────────────────────────────────
# WebSocket Server — broadcasts detections to Flutter
# ─────────────────────────────────────────────────────────────
sign_queue        = Queue()
frame_queue       = Queue(maxsize=1)   # latest camera frame as base64 JPEG
ws_clients        = set()
_stored_session_id = ""   # Device A registers its session; Device B gets it automatically
_frame_counter    = 0     # used to throttle frame sends to ~10 fps

async def _ws_handler(websocket):
    global ws_clients, _stored_session_id
    ws_clients.add(websocket)
    print(f"[WS] Flutter connected  (total={len(ws_clients)})")

    # Auto-send stored session ID to newly connected client (Device B)
    if _stored_session_id:
        try:
            await websocket.send(json.dumps({
                "type": "session_info",
                "session_id": _stored_session_id
            }))
            print(f"[WS] Sent session_info to new client: {_stored_session_id}")
        except Exception:
            pass

    try:
        # Handle incoming messages from Flutter
        async for raw in websocket:
            try:
                data = json.loads(raw)
                if data.get("type") == "session_register":
                    _stored_session_id = data.get("session_id", "")
                    print(f"[WS] Session registered: {_stored_session_id}")
                elif data.get("type") == "screen_switch":
                    # Relay to all OTHER connected clients
                    screen = data.get("screen", "")
                    print(f"[WS] Relaying screen_switch: {screen}")
                    relay_msg = json.dumps({"type": "screen_switch", "screen": screen})
                    dead = set()
                    for other in list(ws_clients):
                        if other is websocket:
                            continue
                        try:
                            await other.send(relay_msg)
                        except Exception:
                            dead.add(other)
                    ws_clients -= dead
            except Exception:
                pass
    finally:
        ws_clients.discard(websocket)
        print(f"[WS] Flutter disconnected (total={len(ws_clients)})")


async def _broadcaster():
    global ws_clients  # ← required: ws_clients -= dead would make it local otherwise
    while True:
        await asyncio.sleep(0.04)   # ~25 times/sec

        # ── Broadcast sign detections ──────────────────────────────
        while not sign_queue.empty():
            msg = sign_queue.get()
            dead = set()
            for ws in list(ws_clients):
                try:
                    await ws.send(msg)
                except Exception:
                    dead.add(ws)
            ws_clients -= dead

        # ── Broadcast latest camera frame (10 fps throttle) ────────
        if not frame_queue.empty():
            frame_msg = frame_queue.get()   # get the most recent frame
            dead = set()
            for ws in list(ws_clients):
                try:
                    await ws.send(frame_msg)
                except Exception:
                    dead.add(ws)
            ws_clients -= dead

async def _ws_main():
    import socket as _socket
    try:
        lan_ip = _socket.gethostbyname(_socket.gethostname())
    except Exception:
        lan_ip = "localhost"
    async with websockets.serve(_ws_handler, "0.0.0.0", 8765):
        print(f"[WS] WebSocket server running on port 8765")
        print(f"[WS]   Local:   ws://localhost:8765")
        print(f"[WS]   Network: ws://{lan_ip}:8765  (use this on Device B)")
        await _broadcaster()

def _start_ws():
    asyncio.run(_ws_main())

threading.Thread(target=_start_ws, daemon=True).start()

def emit_sign(sign: str, confidence: float, source: str):
    """Call this whenever a sign is confirmed. Thread-safe."""
    msg = json.dumps({"sign": sign, "confidence": round(confidence, 3), "source": source})
    sign_queue.put(msg)
    print(f"[WS] Emitting -> {msg}")


def emit_frame(bgr_frame):
    """Encode a BGR OpenCV frame as JPEG base64 and push to frame_queue (non-blocking).
    Only keeps the most recent frame — older ones are dropped if not yet consumed."""
    import base64
    ok, buf = cv2.imencode('.jpg', bgr_frame, [cv2.IMWRITE_JPEG_QUALITY, 55])
    if not ok:
        return
    b64 = base64.b64encode(buf.tobytes()).decode('ascii')
    msg = json.dumps({"type": "frame", "data": b64})
    # Drop the old frame if the queue is full (always keep latest)
    if frame_queue.full():
        try:
            frame_queue.get_nowait()
        except Exception:
            pass
    frame_queue.put_nowait(msg)


# ─────────────────────────────────────────────────────────────
# Paths
# ─────────────────────────────────────────────────────────────
BASE_DIR   = os.path.dirname(os.path.abspath(__file__))
WORDS_DIR  = os.path.join(BASE_DIR, 'Words')
ASL_ML_DIR = os.path.join(BASE_DIR, 'asl_ml')
MODELS_DIR = os.path.join(ASL_ML_DIR, 'models')

sys.path.insert(0, ASL_ML_DIR)
from keypoint_extractor import KeypointExtractor

# ─────────────────────────────────────────────────────────────
# WORDS model -- hyperparams
# ─────────────────────────────────────────────────────────────
MAX_FRAMES      = 40
FEAT_SIZE       = 84
W_CONF_THRESH   = 0.50
W_CONSEC_NEEDED = 4
W_COOLDOWN_F    = 20
EMA_ALPHA       = 0.6
W_MARGIN        = 0.10

META_FILE    = os.path.join(WORDS_DIR, 'model_meta.json')
CLASSES_FILE = os.path.join(WORDS_DIR, 'Final_ASL_Classes.npy')
WEIGHT_FILES = [
    os.path.join(WORDS_DIR, 'Final_ASL_Model_fixed.weights.h5'),
    os.path.join(WORDS_DIR, 'Final_ASL_Model_fixed.h5'),
    os.path.join(WORDS_DIR, 'Final_ASL_Model.h5'),
]

META = {}
if os.path.exists(META_FILE):
    with open(META_FILE) as f:
        META = json.load(f)
    MAX_FRAMES = META.get('max_frames', MAX_FRAMES)
    FEAT_SIZE  = META.get('feat_size',  FEAT_SIZE)
    print(f"[Words] meta: winner={META.get('winner','?')}  val_acc={META.get('val_acc',0)*100:.1f}%")
else:
    print("[Words] No model_meta.json — using defaults")

word_classes = [str(c) for c in np.load(CLASSES_FILE, allow_pickle=True)]
N_WORDS = len(word_classes)
print(f"[Words] {N_WORDS} classes: {word_classes}")


def build_conv1d(fr, ft, nc):
    return Sequential([
        keras.Input(shape=(fr, ft)), BatchNormalization(),
        Conv1D(64, 3, activation='relu', padding='same'), MaxPooling1D(2), Dropout(0.25),
        Conv1D(128, 3, activation='relu', padding='same'), MaxPooling1D(2), Dropout(0.25),
        GlobalAveragePooling1D(), Dense(128, activation='relu'), Dropout(0.4),
        Dense(nc, activation='softmax')
    ], name='Conv1D')

def build_bilstm(fr, ft, nc):
    return Sequential([
        keras.Input(shape=(fr, ft)), BatchNormalization(),
        Bidirectional(LSTM(64, return_sequences=True, dropout=0.2)), Dropout(0.3),
        Bidirectional(LSTM(64, return_sequences=False, dropout=0.2)), Dropout(0.3),
        Dense(64, activation='relu'), Dropout(0.4),
        Dense(nc, activation='softmax')
    ], name='BiLSTM')

def build_old_lstm(fr, ft, nc):
    return Sequential([
        keras.Input(shape=(fr, ft)),
        LSTM(64, return_sequences=True, activation='tanh'), Dropout(0.2),
        LSTM(128, activation='tanh'), Dropout(0.2),
        Dense(64, activation='relu'),
        Dense(nc, activation='softmax')
    ], name='OldLSTM')

winner = META.get('winner', 'Conv1D')
arch_order = (
    [('BiLSTM', build_bilstm), ('Conv1D', build_conv1d), ('OldLSTM', build_old_lstm)]
    if winner == 'BiLSTM'
    else [('Conv1D', build_conv1d), ('BiLSTM', build_bilstm), ('OldLSTM', build_old_lstm)]
)

word_model = None
for path in WEIGHT_FILES:
    if not os.path.exists(path):
        continue
    print(f"\n[Words] Trying {os.path.basename(path)}")
    try:
        word_model = tf.keras.models.load_model(path, compile=False)
        print(f"  Full load OK  output={word_model.output_shape}")
        break
    except Exception as e:
        print(f"  Full failed: {str(e)[:80]}")
    for arch_name, builder in arch_order:
        try:
            m = builder(MAX_FRAMES, FEAT_SIZE, N_WORDS)
            m.compile(optimizer='adam', loss='categorical_crossentropy', metrics=['accuracy'])
            m.load_weights(path)
            word_model = m
            print(f"  Weights OK ({arch_name})")
            break
        except Exception as e:
            print(f"  Weights failed ({arch_name}): {str(e)[:60]}")
    if word_model:
        break

if word_model is None:
    print("\n[Words] ERROR: could not load any model.")
    sys.exit(1)

print("[Words] Ready!")

# ─────────────────────────────────────────────────────────────
# LETTERS model -- TFLite
# ─────────────────────────────────────────────────────────────
LETTER_MODEL  = os.path.join(MODELS_DIR, 'asl_letter_model.tflite')
LETTER_LABELS = os.path.join(MODELS_DIR, 'letter_labels.json')

print(f"\n[Letters] {os.path.basename(LETTER_MODEL)}")
letter_interp = tf.lite.Interpreter(model_path=LETTER_MODEL)
letter_interp.allocate_tensors()
l_inp_d = letter_interp.get_input_details()
l_out_d = letter_interp.get_output_details()
with open(LETTER_LABELS) as f:
    LETTERS = json.load(f)
print(f"[Letters] {len(LETTERS)} labels OK")

# Letter detection params
L_CONF_THRESH   = 0.72    # per-frame min confidence
L_CONSEC_NEEDED = 12      # consecutive stable frames to confirm (≈0.4 s)
L_COOLDOWN_F    = 25

def predict_letter(kp126):
    x = kp126.reshape(1, 126).astype(np.float32)
    letter_interp.set_tensor(l_inp_d[0]['index'], x)
    letter_interp.invoke()
    probs = letter_interp.get_tensor(l_out_d[0]['index'])[0]
    idx = int(np.argmax(probs))
    return LETTERS[idx], float(probs[idx])

# ─────────────────────────────────────────────────────────────
# Motion detection — ROBUST rolling-window spread
# ─────────────────────────────────────────────────────────────
#
# Instead of frame-to-frame delta (jitter-prone), we measure the
# spatial SPREAD (std-dev) of the wrist position over the last
# WRIST_WINDOW frames.  MediaPipe noise has a tiny std; genuine
# hand motion has a large one.
#
# Static = spread < STATIC_SPREAD_THRESH  for MIN_STATIC_FRAMES consecutive frames
# Motion = spread > MOTION_SPREAD_THRESH  (resets letter state immediately)
#
WRIST_WINDOW         = 30    # frames to keep (~1 s at 30 fps)
STATIC_SPREAD_THRESH = 0.012 # normalised units — below this = hand is still
MOTION_SPREAD_THRESH = 0.022 # above this = clear intentional motion
MIN_STATIC_FRAMES    = 20    # frames of stillness before letter mode UNLOCKS

wrist_history   = deque(maxlen=WRIST_WINDOW)
static_count    = 0          # consecutive frames with spread < STATIC_SPREAD_THRESH
letter_unlocked = False      # True only after MIN_STATIC_FRAMES of stillness

# ─────────────────────────────────────────────────────────────
# MediaPipe
# ─────────────────────────────────────────────────────────────
mp_hands     = mp.solutions.hands
mp_draw      = mp.solutions.drawing_utils
mp_draw_sty  = mp.solutions.drawing_styles
hands_solver = mp_hands.Hands(
    max_num_hands=2,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5
)
letter_extractor = KeypointExtractor(max_num_hands=1, min_detection_confidence=0.35)

# ─────────────────────────────────────────────────────────────
# Camera
# ─────────────────────────────────────────────────────────────
def open_camera():
    for backend in [cv2.CAP_DSHOW, None]:
        for idx in range(5):
            args = (idx, backend) if backend is not None else (idx,)
            cap  = cv2.VideoCapture(*args)
            if cap.isOpened():
                ret, frame = cap.read()
                if ret and frame is not None:
                    cap.set(cv2.CAP_PROP_FRAME_WIDTH,  640)
                    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
                    print(f"[Camera] index={idx}")
                    return cap
            cap.release()
    return None

print("\nOpening camera...")
cap = open_camera()
if cap is None:
    print("ERROR: no camera found.")
    sys.exit(1)

CAM_W = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
CAM_H = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
print(f"Camera {CAM_W}x{CAM_H}  |  Q=quit C=clear S=status D=debug\n" + "-"*60)

# ─────────────────────────────────────────────────────────────
# State
# ─────────────────────────────────────────────────────────────
w_sequence     = []
w_smoothed     = np.zeros(N_WORDS)
w_last_probs   = np.zeros(N_WORDS)
w_consec_word  = ""
w_consec_count = 0
w_cooldown     = 0

l_consec_letter = ""
l_consec_count  = 0
l_cooldown      = 0

sentence        = []
last_label      = ""
last_label_conf = 0.0
last_label_type = ""
flash_frames    = 0
FLASH_DURATION  = 40

show_status  = True
show_debug   = False

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────
FONT = cv2.FONT_HERSHEY_SIMPLEX

def extract_word_kp(results):
    kp = np.zeros(84)
    if results.multi_hand_landmarks:
        for i, hl in enumerate(results.multi_hand_landmarks):
            if i > 1: break
            off = i * 42
            for j, lm in enumerate(hl.landmark):
                kp[off + j*2]   = lm.x
                kp[off + j*2+1] = lm.y
    return kp

def get_wrist_xy(results):
    if results.multi_hand_landmarks:
        lm = results.multi_hand_landmarks[0].landmark[0]
        return lm.x, lm.y
    return None

def add_to_sentence(token):
    sentence.append(token)
    if len(sentence) > 8:
        sentence.pop(0)

def reset_word_state():
    global w_consec_word, w_consec_count, w_smoothed
    w_consec_word  = ""
    w_consec_count = 0
    w_smoothed     = np.zeros(N_WORDS)
    w_sequence.clear()          # clear stale sequence on mode switch

def reset_letter_state():
    global l_consec_letter, l_consec_count
    l_consec_letter = ""
    l_consec_count  = 0

# ─────────────────────────────────────────────────────────────
# Main loop
# ─────────────────────────────────────────────────────────────
while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        break

    # ── MediaPipe (word coords — unflipped) ─────────────────
    rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    w_results = hands_solver.process(rgb_frame)

    display = frame.copy()
    if w_results.multi_hand_landmarks:
        for hl in w_results.multi_hand_landmarks:
            mp_draw.draw_landmarks(display, hl, mp_hands.HAND_CONNECTIONS,
                mp_draw_sty.get_default_hand_landmarks_style(),
                mp_draw_sty.get_default_hand_connections_style())

    hand_active = bool(w_results.multi_hand_landmarks)

    # ── Rolling spread (robust motion metric) ──────────────
    wrist = get_wrist_xy(w_results)
    if wrist:
        wrist_history.append(wrist)
    else:
        wrist_history.clear()   # hand left frame — reset history

    if len(wrist_history) >= 10:
        pts = np.array(wrist_history)
        spread = float(np.std(pts[:, 0]) + np.std(pts[:, 1]))  # combined spread
    else:
        spread = 0.0

    # ── Update static counter ────────────────────────────────
    if spread < STATIC_SPREAD_THRESH and hand_active:
        static_count = min(static_count + 1, MIN_STATIC_FRAMES + 10)
    else:
        # Any motion or hand-loss immediately resets letter mode
        if spread >= MOTION_SPREAD_THRESH:
            static_count = 0
            if letter_unlocked:
                reset_letter_state()   # cancel partial letter streak
        elif not hand_active:
            static_count = max(static_count - 2, 0)  # gentle decay
        else:
            static_count = max(static_count - 1, 0)  # micro-jitter: slow decay

    letter_unlocked = (static_count >= MIN_STATIC_FRAMES)

    # ── Word pipeline (always collecting, confirms only when moving / hand present)
    kp_word = extract_word_kp(w_results)
    if not letter_unlocked:          # only feed sequence when NOT in static mode
        w_sequence.append(kp_word)
    w_sequence = w_sequence[-MAX_FRAMES:]
    if w_cooldown > 0: w_cooldown -= 1

    if (len(w_sequence) == MAX_FRAMES and hand_active
            and w_cooldown == 0 and not letter_unlocked):
        inp       = np.expand_dims(np.array(w_sequence, dtype='float32'), 0)
        raw_probs = word_model(inp, training=False)[0].numpy()

        if np.all(w_smoothed == 0):
            w_smoothed = raw_probs.copy()
        else:
            w_smoothed = EMA_ALPHA * raw_probs + (1 - EMA_ALPHA) * w_smoothed

        w_last_probs = w_smoothed
        top_idx  = int(np.argmax(w_smoothed))
        top_conf = float(w_smoothed[top_idx])
        top_word = word_classes[top_idx]
        sec_conf = float(np.sort(w_smoothed)[-2])

        margin_ok = (top_conf - sec_conf) >= W_MARGIN
        if top_conf >= W_CONF_THRESH and margin_ok:
            if top_word == w_consec_word:
                w_consec_count += 1
            else:
                w_consec_word  = top_word
                w_consec_count = 1
        else:
            w_consec_word  = ""
            w_consec_count = 0

        if w_consec_count >= W_CONSEC_NEEDED:
            last_label      = top_word
            last_label_conf = top_conf
            last_label_type = "WORD"
            flash_frames    = FLASH_DURATION
            w_cooldown      = W_COOLDOWN_F
            reset_word_state()
            reset_letter_state()
            add_to_sentence(top_word)
            print(f">>> WORD: {top_word} ({top_conf*100:.0f}%)")
            emit_sign(top_word, top_conf, "word_model")
    elif not hand_active:
        reset_word_state()

    # ── Letter pipeline (ONLY when hand is confirmed static) ─
    if l_cooldown > 0: l_cooldown -= 1

    if letter_unlocked and hand_active and l_cooldown == 0:
        flipped = cv2.flip(frame, 1)
        l_kp = letter_extractor.extract(flipped)

        if l_kp is not None:
            letter, l_conf = predict_letter(l_kp)

            if l_conf >= L_CONF_THRESH:
                if letter == l_consec_letter:
                    l_consec_count += 1
                else:
                    l_consec_letter = letter
                    l_consec_count  = 1
            else:
                reset_letter_state()

            if l_consec_count >= L_CONSEC_NEEDED:
                last_label      = letter
                last_label_conf = l_conf
                last_label_type = "LETTER"
                flash_frames    = FLASH_DURATION
                l_cooldown      = L_COOLDOWN_F
                reset_letter_state()
                reset_word_state()
                add_to_sentence(letter)
                print(f">>> LETTER: {letter} ({l_conf*100:.0f}%)")
                emit_sign(letter, l_conf, "alphabet_model")
        else:
            reset_letter_state()
    elif not letter_unlocked:
        reset_letter_state()

    if flash_frames > 0:
        flash_frames -= 1

    # ─────────────────────────────────────────────────────────
    # Draw UI
    # ─────────────────────────────────────────────────────────

    # Header bar
    cv2.rectangle(display, (0, 0), (CAM_W, 100), (10, 10, 16), -1)

    # ── Large confirmed sign ─────────────────────────────────
    if last_label:
        pulse = flash_frames > 0
        if last_label_type == "WORD":
            sign_col  = (40, 255, 110) if pulse else (0, 210, 80)
            badge_col = (10, 140, 50)
        else:
            sign_col  = (100, 200, 255) if pulse else (30, 150, 255)
            badge_col = (10, 60, 140)

        cv2.putText(display, last_label.upper(), (14, 72),
                    FONT, 1.8, sign_col, 3, cv2.LINE_AA)
        cv2.putText(display, f"[{last_label_type}]  {int(last_label_conf*100)}%",
                    (14, 93), FONT, 0.42, sign_col, 1, cv2.LINE_AA)
    else:
        cv2.putText(display, "Show your sign...", (14, 62),
                    FONT, 1.1, (70, 70, 70), 2, cv2.LINE_AA)

    # ── Mode badge (top-right) ───────────────────────────────
    # STATIC = green = letter mode active
    # MOVING = orange = word mode  |  WAITING = gray = warming up
    if not hand_active:
        mode_txt, mode_col = "NO HAND", (60, 60, 60)
    elif letter_unlocked:
        mode_txt, mode_col = "STATIC ", (40, 220, 80)
    elif static_count > 0:
        pct = int(static_count / MIN_STATIC_FRAMES * 100)
        mode_txt, mode_col = f"HOLD {pct}%", (0, 180, 200)
    else:
        mode_txt, mode_col = "MOVING ", (0, 150, 255)

    cv2.putText(display, mode_txt, (CAM_W - 105, 22),
                FONT, 0.5, mode_col, 1, cv2.LINE_AA)

    # Static fill bar — how close to letter unlock
    sb_pct = min(static_count / MIN_STATIC_FRAMES, 1.0)
    cv2.rectangle(display, (CAM_W - 106, 27), (CAM_W - 6, 33), (30, 30, 30), -1)
    if sb_pct > 0:
        cv2.rectangle(display, (CAM_W - 106, 27),
                      (CAM_W - 106 + int(100 * sb_pct), 33), mode_col, -1)

    # ── Status overlay (S to toggle) ───────────────────────
    if show_status:
        # Word progress bar
        w_pct = min(w_consec_count / W_CONSEC_NEEDED, 1.0)
        cv2.rectangle(display, (0, 100), (CAM_W, 109), (18, 18, 18), -1)
        if w_pct > 0:
            cv2.rectangle(display, (0, 100), (int(CAM_W * w_pct), 109), (0, 200, 70), -1)
        cv2.putText(display, "WORD", (3, 108), FONT, 0.3, (0, 200, 70), 1)

        # Letter progress bar  (only shows when letter UNLOCKED)
        l_pct = min(l_consec_count / L_CONSEC_NEEDED, 1.0) if letter_unlocked else 0.0
        cv2.rectangle(display, (0, 110), (CAM_W, 119), (18, 18, 18), -1)
        if l_pct > 0:
            cv2.rectangle(display, (0, 110), (int(CAM_W * l_pct), 119), (30, 130, 255), -1)
        cv2.putText(display, "LETTER", (3, 118), FONT, 0.3, (30, 130, 255), 1)

        # Hand indicator
        dot_col = (0, 240, 0) if hand_active else (0, 0, 200)
        cv2.circle(display, (16, 134), 7, dot_col, -1)
        cv2.putText(display, "Hand" if hand_active else "No hand",
                    (28, 138), FONT, 0.38, dot_col, 1)

        # Top-3 word confidences (right side)
        if hand_active and np.any(w_last_probs > 0):
            bx = CAM_W - 155
            cv2.rectangle(display, (bx - 3, 122), (CAM_W, 122 + 3 * 22 + 4), (14, 14, 14), -1)
            for rank, idx in enumerate(np.argsort(w_last_probs)[-3:][::-1]):
                by  = 138 + rank * 22
                bw  = int(135 * float(w_last_probs[idx]))
                cv2.rectangle(display, (bx, by - 12), (bx + 135, by + 4), (32, 32, 32), -1)
                if bw > 0:
                    col = (0, 190, 70) if rank == 0 else (0, 70, 160)
                    cv2.rectangle(display, (bx, by - 12), (bx + bw, by + 4), col, -1)
                cv2.putText(display,
                            f"{word_classes[idx][:9]} {w_last_probs[idx]*100:.0f}%",
                            (bx + 2, by), FONT, 0.33, (200, 200, 200), 1)

    # ── Debug spread value (D to toggle) ─────────────────────
    if show_debug:
        cv2.putText(display,
                    f"spread={spread:.4f}  static={static_count}/{MIN_STATIC_FRAMES}  "
                    f"unlocked={letter_unlocked}",
                    (4, CAM_H - 50), FONT, 0.36, (200, 200, 60), 1)

    # ── Sentence bar ────────────────────────────────────────
    cv2.rectangle(display, (0, CAM_H - 44), (CAM_W, CAM_H), (8, 8, 12), -1)
    cv2.line(display, (0, CAM_H - 44), (CAM_W, CAM_H - 44), (40, 40, 50), 1)

    if sentence:
        stxt = "  >  ".join(sentence)
        scol = (200, 200, 255)
    else:
        stxt = "Sentence appears here..."
        scol = (50, 50, 55)
    cv2.putText(display, stxt, (10, CAM_H - 22), FONT, 0.58, scol, 1, cv2.LINE_AA)
    cv2.putText(display, "Q=quit C=clear S=status D=debug",
                (CAM_W - 218, CAM_H - 8), FONT, 0.35, (50, 50, 55), 1)

    # ── Flash border on confirmation ──────────────────────────
    if flash_frames > 0:
        border_col = (30, 220, 80) if last_label_type == "WORD" else (30, 130, 255)
        cv2.rectangle(display, (0, 0), (CAM_W - 1, CAM_H - 1), border_col, 3)

    cv2.imshow("SignBridge  ASL Live", display)

    # ── Stream frame to Flutter at ~10 fps (every 3rd frame @ 30 fps) ──
    _frame_counter += 1
    if _frame_counter % 3 == 0:
        small = cv2.resize(display, (480, 270))
        emit_frame(small)

    key = cv2.waitKey(1) & 0xFF

    if key == ord('q'):
        break
    elif key == ord('c'):
        sentence.clear(); last_label = ""; last_label_conf = 0.0; last_label_type = ""
        flash_frames = 0; reset_word_state(); reset_letter_state()
        wrist_history.clear(); static_count = 0; letter_unlocked = False
        print("--- Cleared ---")
    elif key == ord('s'):
        show_status = not show_status
    elif key == ord('d'):
        show_debug = not show_debug
        print(f"Debug: {'ON' if show_debug else 'OFF'}")

# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────
cap.release()
cv2.destroyAllWindows()
hands_solver.close()
letter_extractor.close()
print("Done.")
