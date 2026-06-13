import cv2
import numpy as np
import json
import time
from typing import Optional

from keypoint_extractor import KeypointExtractor
from boundary_detector import BoundaryDetector
from sentence_formatter import SentenceFormatter


# ─── Output format (also in mock_output.json) ────────────────────────────────
"""
OUTPUT FORMAT:
{
    "status": "idle" | "signing" | "sign_detected" | "sentence_complete",
    "raw_sign": "HELP",                          # null if idle
    "confidence": 0.92,                          # null if idle
    "formatted_sentence_en": "I need help.",     # Current sentence (EN)
    "formatted_sentence_hi": "मुझे मदद चाहिए।",  # Current sentence (HI)
    "is_sentence_complete": false,
    "conversation_en": ["Hello!", "I need help."],  # Full chat history
    "conversation_hi": ["नमस्ते!", "मुझे मदद चाहिए।"],
    "suggestions_en": ["I need help.", "Can you help?"],
    "suggestions_hi": ["मुझे मदद चाहिए।", "क्या आप मदद कर सकते हैं?"],
    "velocity": 0.045,                          # Hand velocity (for UI)
    "hands_detected": true,
    "partial_word": null,                        # For letter-by-letter spelling
    "timestamp": 1700000000.0
}
"""


class ASLInferencePipeline:
    def __init__(
        self,
        dynamic_model_path: str,
        letter_model_path: str,
        dynamic_labels_path: str,
        letter_labels_path: str,
        confidence_threshold: float = 0.75,
        language: str = "en",
    ):
        print("Initializing ASL Inference Pipeline...")

        # Components
        self.extractor = KeypointExtractor()
        self.boundary = BoundaryDetector()
        self.formatter = SentenceFormatter()

        self.confidence_threshold = confidence_threshold
        self.language = language

        # Load TFLite models
        import tensorflow as tf
        
        print(f"  Loading dynamic model: {dynamic_model_path}")
        self.dynamic_interpreter = tf.lite.Interpreter(model_path=dynamic_model_path)
        self.dynamic_interpreter.allocate_tensors()
        self.dynamic_input = self.dynamic_interpreter.get_input_details()[0]
        self.dynamic_output = self.dynamic_interpreter.get_output_details()[0]

        try:
            print(f"  Loading letter model: {letter_model_path}")
            self.letter_interpreter = tf.lite.Interpreter(model_path=letter_model_path)
            self.letter_interpreter.allocate_tensors()
            self.letter_input = self.letter_interpreter.get_input_details()[0]
            self.letter_output = self.letter_interpreter.get_output_details()[0]
            self.has_letter_model = True
        except Exception as e:
            print(f"  Letter model not found, skipping: {e}")
            self.has_letter_model = False

        # Load labels
        with open(dynamic_labels_path) as f:
            self.dynamic_labels = json.load(f)
        
        if self.has_letter_model:
            with open(letter_labels_path) as f:
                self.letter_labels = json.load(f)

        # State
        self.conversation_en = []
        self.conversation_hi = []
        self.current_sentence_en = ""
        self.current_sentence_hi = ""
        self.is_letter_mode = False

        print("Pipeline ready!")

    def process_frame(self, frame_bgr: np.ndarray) -> dict:
        """
        Process one webcam frame.
        
        Args:
            frame_bgr: BGR numpy array from cv2
            
        Returns:
            dict with full output (see OUTPUT FORMAT above)
        """
        # Step 1: Extract keypoints
        keypoints = self.extractor.extract(frame_bgr)
        hands_detected = keypoints is not None

        # Step 2: Boundary detection
        boundary_result = self.boundary.update(keypoints)
        velocity = boundary_result["velocity"]
        state = boundary_result["state"]

        result = self._build_result(
            status=state if state != "boundary" else "signing",
            hands_detected=hands_detected,
            velocity=velocity
        )

        # Step 3: If boundary detected, classify the buffered sequence
        if boundary_result["should_classify"] and boundary_result["buffer"]:
            sequence = self._pad_sequence(boundary_result["buffer"])
            raw_sign, confidence = self._classify_dynamic(sequence)

            # Also check if it's a letter (if in letter mode or confidence low)
            if self.is_letter_mode and self.has_letter_model:
                middle_frame = sequence[len(sequence)//2]
                letter_sign, letter_conf = self._classify_letter(middle_frame)
                if letter_conf > confidence:
                    raw_sign = letter_sign
                    confidence = letter_conf

            if raw_sign and confidence >= self.confidence_threshold:
                # Format the sign
                formatted = self.formatter.format_sign(raw_sign, self.language)
                
                self.current_sentence_en += (" " if self.current_sentence_en else "") + formatted["en"]
                self.current_sentence_hi += (" " if self.current_sentence_hi else "") + formatted["hi"]

                suggestions_en = self.formatter.get_suggestions(raw_sign, "en")
                suggestions_hi = self.formatter.get_suggestions(raw_sign, "hi")

                result["status"] = "sign_detected"
                result["raw_sign"] = raw_sign
                result["confidence"] = round(confidence, 3)
                result["formatted_sentence_en"] = self.current_sentence_en
                result["formatted_sentence_hi"] = self.current_sentence_hi
                result["suggestions_en"] = suggestions_en
                result["suggestions_hi"] = suggestions_hi
                result["partial_word"] = formatted.get("partial_word")

        return result

    def complete_sentence(self):
        """
        Called when user signals end of sentence (pause, button press).
        Adds current sentence to conversation history.
        """
        if self.current_sentence_en:
            self.conversation_en.append(self.current_sentence_en)
            self.conversation_hi.append(self.current_sentence_hi)
            self.current_sentence_en = ""
            self.current_sentence_hi = ""
            self.formatter.reset()
            return True
        return False

    def set_language(self, language: str):
        """Switch display language ('en' or 'hi')."""
        self.language = language

    def set_letter_mode(self, enabled: bool):
        """Toggle letter-by-letter spelling mode."""
        self.is_letter_mode = enabled

    def clear_conversation(self):
        """Clear chat history (temporary storage only)."""
        self.conversation_en.clear()
        self.conversation_hi.clear()
        self.current_sentence_en = ""
        self.current_sentence_hi = ""
        self.formatter.reset()

    def get_annotated_frame(self, frame_bgr: np.ndarray) -> np.ndarray:
        """Return frame with landmark skeleton drawn."""
        frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        results = self.extractor.hands.process(frame_rgb)
        return self.extractor.draw_landmarks(frame_bgr.copy(), results)

    def _classify_dynamic(self, sequence: np.ndarray):
        """Run LSTM model on a (30, 126) sequence."""
        input_data = sequence.reshape(1, 30, 126).astype(np.float32)
        self.dynamic_interpreter.set_tensor(self.dynamic_input['index'], input_data)
        self.dynamic_interpreter.invoke()
        probs = self.dynamic_interpreter.get_tensor(self.dynamic_output['index'])[0]
        
        best_idx = int(np.argmax(probs))
        confidence = float(probs[best_idx])
        label = self.dynamic_labels[best_idx] if best_idx < len(self.dynamic_labels) else None
        
        return label, confidence

    def _classify_letter(self, frame: np.ndarray):
        """Run Dense model on a single (126,) frame."""
        if not self.has_letter_model:
            return None, 0.0
        input_data = frame.reshape(1, 126).astype(np.float32)
        self.letter_interpreter.set_tensor(self.letter_input['index'], input_data)
        self.letter_interpreter.invoke()
        probs = self.letter_interpreter.get_tensor(self.letter_output['index'])[0]
        
        best_idx = int(np.argmax(probs))
        confidence = float(probs[best_idx])
        label = self.letter_labels[best_idx] if best_idx < len(self.letter_labels) else None
        
        return label, confidence

    def _pad_sequence(self, frames: list, target_len=30) -> np.ndarray:
        """Pad or trim frame list to target_len."""
        arr = np.array(frames, dtype=np.float32)
        
        if len(arr) < target_len:
            padding = np.zeros((target_len - len(arr), 126), dtype=np.float32)
            arr = np.vstack([padding, arr])
        elif len(arr) > target_len:
            indices = np.linspace(0, len(arr)-1, target_len, dtype=int)
            arr = arr[indices]
        
        return arr

    def _build_result(self, status="idle", hands_detected=False, velocity=0.0) -> dict:
        return {
            "status": status,
            "raw_sign": None,
            "confidence": None,
            "formatted_sentence_en": self.current_sentence_en,
            "formatted_sentence_hi": self.current_sentence_hi,
            "is_sentence_complete": False,
            "conversation_en": list(self.conversation_en),
            "conversation_hi": list(self.conversation_hi),
            "suggestions_en": [],
            "suggestions_hi": [],
            "velocity": round(velocity, 4),
            "hands_detected": hands_detected,
            "partial_word": None,
            "timestamp": time.time()
        }

    def close(self):
        self.extractor.close()


# ─── Mock pipeline for testing without trained model ─────────────────────────

class MockASLPipeline:
    """
    Drop-in replacement for testing without a trained model.
    Cycles through demo signs so Person 1 can test the Flutter UI.
    """
    DEMO_SEQUENCE = [
        ("HELLO", 0.95),
        ("HOW_MUCH", 0.88),
        ("THANK_YOU", 0.91),
        ("HELP", 0.87),
        ("YES", 0.93),
        ("WATER", 0.89),
        ("RECEIPT", 0.84),
    ]

    def __init__(self, language="en"):
        self.language = language
        self.formatter = SentenceFormatter()
        self.demo_idx = 0
        self.frame_count = 0
        self.conversation_en = []
        self.conversation_hi = []
        self.current_sentence_en = ""
        self.current_sentence_hi = ""

    def process_frame(self, frame_bgr):
        self.frame_count += 1

        # Simulate a sign detection every 60 frames (~2 seconds at 30fps)
        if self.frame_count % 60 == 0:
            sign, confidence = self.DEMO_SEQUENCE[self.demo_idx % len(self.DEMO_SEQUENCE)]
            self.demo_idx += 1

            formatted = self.formatter.format_sign(sign, self.language)
            self.current_sentence_en += (" " if self.current_sentence_en else "") + formatted["en"]
            self.current_sentence_hi += (" " if self.current_sentence_hi else "") + formatted["hi"]

            return {
                "status": "sign_detected",
                "raw_sign": sign,
                "confidence": confidence,
                "formatted_sentence_en": self.current_sentence_en,
                "formatted_sentence_hi": self.current_sentence_hi,
                "is_sentence_complete": False,
                "conversation_en": list(self.conversation_en),
                "conversation_hi": list(self.conversation_hi),
                "suggestions_en": self.formatter.get_suggestions(sign, "en"),
                "suggestions_hi": self.formatter.get_suggestions(sign, "hi"),
                "velocity": 0.05,
                "hands_detected": True,
                "partial_word": None,
                "timestamp": time.time()
            }

        status = "signing" if (self.frame_count % 60) < 45 else "idle"
        return {
            "status": status,
            "raw_sign": None,
            "confidence": None,
            "formatted_sentence_en": self.current_sentence_en,
            "formatted_sentence_hi": self.current_sentence_hi,
            "is_sentence_complete": False,
            "conversation_en": list(self.conversation_en),
            "conversation_hi": list(self.conversation_hi),
            "suggestions_en": [],
            "suggestions_hi": [],
            "velocity": 0.03 if status == "signing" else 0.0,
            "hands_detected": status == "signing",
            "partial_word": None,
            "timestamp": time.time()
        }

    def complete_sentence(self):
        if self.current_sentence_en:
            self.conversation_en.append(self.current_sentence_en)
            self.conversation_hi.append(self.current_sentence_hi)
            self.current_sentence_en = ""
            self.current_sentence_hi = ""
            return True
        return False

    def set_language(self, language): self.language = language
    def set_letter_mode(self, enabled): pass
    def clear_conversation(self):
        self.conversation_en.clear()
        self.conversation_hi.clear()
        self.current_sentence_en = ""
        self.current_sentence_hi = ""
    def close(self): pass


# ─── Live demo ────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    import sys
    
    # Use mock pipeline if model files don't exist yet
    USE_MOCK = not __import__('os').path.exists('models/asl_dynamic_model.tflite')
    
    if USE_MOCK:
        print("Model not found — using MOCK pipeline for demo")
        pipeline = MockASLPipeline()
    else:
        pipeline = ASLInferencePipeline(
            dynamic_model_path='models/asl_dynamic_model.tflite',
            letter_model_path='models/asl_letter_model.tflite',
            dynamic_labels_path='models/dynamic_labels.json',
            letter_labels_path='models/letter_labels.json',
        )

    cap = cv2.VideoCapture(0)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

    print("\nLive ASL Demo — Press Q to quit, SPACE to complete sentence")

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        frame = cv2.flip(frame, 1)
        h, w = frame.shape[:2]

        result = pipeline.process_frame(frame)
        
        if not USE_MOCK:
            frame = pipeline.get_annotated_frame(frame)

        # ── Draw UI ──────────────────────────────────────────────────────
        overlay = frame.copy()
        cv2.rectangle(overlay, (0, h-180), (w, h), (0,0,0), -1)
        cv2.addWeighted(overlay, 0.6, frame, 0.4, 0, frame)

        # Status
        status_colors = {
            "idle": (128, 128, 128),
            "signing": (0, 165, 255),
            "sign_detected": (0, 255, 0),
            "sentence_complete": (0, 255, 255)
        }
        color = status_colors.get(result["status"], (255, 255, 255))
        cv2.putText(frame, f"Status: {result['status'].upper()}", (10, h-150),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)

        # Current sign
        if result["raw_sign"]:
            cv2.putText(frame, f"Sign: {result['raw_sign']} ({result['confidence']:.0%})",
                        (10, h-120), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)

        # Current sentence
        sen_en = result["formatted_sentence_en"]
        cv2.putText(frame, f"EN: {sen_en[:60]}", (10, h-85),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.65, (255, 255, 255), 1)
        
        sen_hi = result["formatted_sentence_hi"]
        cv2.putText(frame, f"HI: {sen_hi[:40] if sen_hi else '-'}", (10, h-55),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (200, 200, 255), 1)

        # Velocity bar
        vel = min(result["velocity"] * 500, w - 20)
        cv2.rectangle(frame, (10, h-30), (10 + int(vel), h-15), (0, 200, 100), -1)
        cv2.rectangle(frame, (10, h-30), (w-10, h-15), (80, 80, 80), 1)
        cv2.putText(frame, "velocity", (10, h-8), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (150,150,150), 1)

        cv2.imshow("ASL Translator — Live Demo", frame)

        key = cv2.waitKey(10) & 0xFF
        if key == ord('q'):
            break
        elif key == ord(' '):
            completed = pipeline.complete_sentence()
            if completed:
                print(f"\n  Sentence added to chat: {result['formatted_sentence_en']}")

    cap.release()
    cv2.destroyAllWindows()
    pipeline.close()
