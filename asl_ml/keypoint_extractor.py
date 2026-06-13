import cv2
import numpy as np
import mediapipe as mp
import mediapipe.python.solutions as mp_solutions
mp.solutions = mp_solutions

# Protobuf ≥ 4.x fix — restore removed GetPrototype() for MediaPipe
from google.protobuf import symbol_database as _sym_db_mod
from google.protobuf import message_factory as _msg_factory
_sym_db = _sym_db_mod.Default()
if not hasattr(_sym_db, 'GetPrototype'):
    _sym_db.GetPrototype = _msg_factory.GetMessageClass


class KeypointExtractor:
    def __init__(self, max_num_hands=2, min_detection_confidence=0.7, min_tracking_confidence=0.5):
        self.mp_hands = mp.solutions.hands
        self.mp_drawing = mp.solutions.drawing_utils
        self.mp_drawing_styles = mp.solutions.drawing_styles

        self.hands = self.mp_hands.Hands(
            static_image_mode=False,
            max_num_hands=max_num_hands,
            min_detection_confidence=min_detection_confidence,
            min_tracking_confidence=min_tracking_confidence
        )

    def extract(self, frame_bgr):
        frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        frame_rgb.flags.writeable = False
        results = self.hands.process(frame_rgb)
        frame_rgb.flags.writeable = True

        if not results.multi_hand_landmarks:
            return None

        keypoints = np.zeros((2, 21, 3), dtype=np.float32)

        for hand_idx, hand_landmarks in enumerate(results.multi_hand_landmarks):
            if hand_idx >= 2:
                break
            landmarks = np.array(
                [[lm.x, lm.y, lm.z] for lm in hand_landmarks.landmark],
                dtype=np.float32
            )
            wrist = landmarks[0].copy()
            landmarks -= wrist
            max_val = np.max(np.abs(landmarks)) + 1e-6
            landmarks /= max_val
            keypoints[hand_idx] = landmarks

        return keypoints.flatten()

    def extract_with_handedness(self, frame_bgr):
        frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        frame_rgb.flags.writeable = False
        results = self.hands.process(frame_rgb)
        frame_rgb.flags.writeable = True

        if not results.multi_hand_landmarks:
            return None, []

        keypoints = np.zeros((2, 21, 3), dtype=np.float32)
        handedness_labels = []

        for hand_idx, (hand_landmarks, handedness) in enumerate(
            zip(results.multi_hand_landmarks, results.multi_handedness)
        ):
            if hand_idx >= 2:
                break
            label = handedness.classification[0].label
            handedness_labels.append(label)
            landmarks = np.array(
                [[lm.x, lm.y, lm.z] for lm in hand_landmarks.landmark],
                dtype=np.float32
            )
            wrist = landmarks[0].copy()
            landmarks -= wrist
            max_val = np.max(np.abs(landmarks)) + 1e-6
            landmarks /= max_val
            keypoints[hand_idx] = landmarks

        return keypoints.flatten(), handedness_labels

    def draw_landmarks(self, frame_bgr):
        frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        results = self.hands.process(frame_rgb)

        if results.multi_hand_landmarks:
            for hand_landmarks in results.multi_hand_landmarks:
                self.mp_drawing.draw_landmarks(
                    frame_bgr,
                    hand_landmarks,
                    self.mp_hands.HAND_CONNECTIONS,
                    self.mp_drawing_styles.get_default_hand_landmarks_style(),
                    self.mp_drawing_styles.get_default_hand_connections_style()
                )
        return frame_bgr

    def get_wrist_velocity(self, prev_keypoints, curr_keypoints):
        if prev_keypoints is None or curr_keypoints is None:
            return 0.0
        return float(np.linalg.norm(curr_keypoints[:3] - prev_keypoints[:3]))

    def close(self):
        self.hands.close()


if __name__ == "__main__":
    extractor = KeypointExtractor()
    cap = cv2.VideoCapture(0)
    print("Webcam running. Press Q to quit.")

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        frame = cv2.flip(frame, 1)
        keypoints = extractor.extract(frame)

        if keypoints is not None:
            print(f"Keypoints: {keypoints.shape}, first 6: {keypoints[:6].round(3)}")
            cv2.putText(frame, "HANDS DETECTED", (10, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
        else:
            cv2.putText(frame, "No hands", (10, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 2)

        frame = extractor.draw_landmarks(frame)
        cv2.imshow("Keypoint Extractor Test", frame)
        cv2.setWindowProperty("Keypoint Extractor Test", cv2.WND_PROP_TOPMOST, 1)
        if cv2.waitKey(10) & 0xFF == ord('q'):
            break

    cap.release()
    cv2.destroyAllWindows()
    extractor.close()