# 🤟 Real-Time ASL-to-Text — ML Pipeline Guide

> **Role: Person 2 (ML Pipeline & Gesture Classification)**
> This guide outlines your complete workflow from local setup, data collection, cloud training, to deploying the final inference pipeline.

---

## 1. Environment & Setup (Completed)

We have successfully built a stable Python environment running locally.

**Important Note for Windows + Python 3.12:**
We *do not* install TensorFlow locally due to dependency conflicts with MediaPipe on newer Python versions. All inference runs locally using TensorFlow Lite (`tflite-runtime` or standard TF Lite delegates) and MediaPipe. All training happens exclusively in Google Colab.

### Activate Local Environment
```powershell
cd Real-Time-ASL-to-Text\asl_ml
asl_env\Scripts\activate
```
*(Dependencies are tracked in `requirements.txt`)*

---

## 2. Directory Structure

Your ML workspace contains the following core components:

*   **`keypoint_extractor.py`**: Wraps MediaPipe Hands. Extracts 126 keypoints (21 * 3 * 2 hands) per frame. Normalizes data so position in the camera frame doesn't matter (translation invariant).
*   **`boundary_detector.py`**: Solves the hardest problem: *when does a sign start and stop?* It calculates hand velocity to trigger recording sequences automatically.
*   **`collect_data.py`**: Real-time dataset collection tool.
*   **`sentence_formatter.py`**: Translates raw labels (e.g., `"HELP"`) into natural English/Hindi sentences (`"I need help."` / `"मुझे मदद चाहिए।"`) and handles offline smart suggestions.
*   **`inference_pipeline.py`**: The main processor. Takes a camera frame, extracts keypoints, handles the sliding window, calls the TFLite models, and formats the output.
*   **`pipeline_server.py`**: A local Flask API running on port `5000`. Flutter apps connect to this to receive live translations and send commands.

---

## 3. Data Collection

You need to coordinate a session to record training data for your target signs.

1.  Run the collection script:
    ```powershell
    python collect_data.py
    ```
2.  Follow on-screen instructions. The script automatically detects when you stop signing and saves exactly 30-frame `.npy` arrays into `data/raw/[SIGN_NAME]/`.
3.  **Target:** Record at least 30-60 samples per sign. Capture slight variations in angle and speed for better generalization.

---

## 4. Google Colab Training Workflow

Once your data is collected locally, zip the `data/raw/` directory and upload it to Google Drive for Colab training.

### Model Architecture Strategy
You will train two separate models:
1.  **Dynamic Sign Model (1D-CNN or LSTM)**: For moving signs like `HELP`, `THANK_YOU`.
    *   *Input Shape:* `(30, 126)` representing 30 frames of 126 features.
2.  **Letter Model (Dense / MLP)**: For static ASL alphabet gestures.
    *   *Input Shape:* `(126,)` representing a single static frame.

### Steps in Colab
1.  Mount Google Drive and extract the dataset.
2.  Apply **Data Augmentation**: Add Gaussian noise to coordinates and scale slightly to synthetically expand your dataset.
3.  Train using Keras/TensorFlow 2.15.0.
4.  Export to TensorFlow Lite (`.tflite`).
5.  Save your class index mappings to `dynamic_labels.json` and `letter_labels.json`.

---

## 5. Integrating Trained Models

Download the trained `.tflite` models and label mapping files from Colab and place them locally in the `models/` directory:

```text
asl_ml/
└── models/
    ├── asl_dynamic_model.tflite
    ├── asl_letter_model.tflite
    ├── dynamic_labels.json
    └── letter_labels.json
```

Once these files exist, `pipeline_server.py` will automatically switch from its "Mock" demonstration mode to using your real trained models!

---

## 6. Handing off to Person 1 (Flutter Frontend)

Person 1 is currently building the frontend UI. To unblock them, the `pipeline_server.py` currently runs in **MOCK** mode if no models are detected. It cycles through a demo sequence of signs.

### API Contract (Running on `http://localhost:5000`)

*   **`POST /process_frame`**: Frontend sends base64 webcam frames, backend returns standard output payload.
*   **`POST /complete_sentence`**: Used when the user presses the "Space/Done" button on the UI.
*   **`POST /set_language`**: Accepts `{"lang": "en" | "hi"}`.
*   **`POST /set_letter_mode`**: Accepts `{"enabled": true | false}`.
*   **`GET /suggestions`**: Core offline suggestions for both input and output screens.

### Output JSON Payload
When Flutter calls `/process_frame`, it expects this response:
```json
{
    "status": "idle",
    "raw_sign": "HELP",
    "confidence": 0.92,
    "formatted_sentence_en": "I need help.",
    "formatted_sentence_hi": "मुझे मदद चाहिए।",
    "is_sentence_complete": false,
    "conversation_en": ["Hello!", "I need help."],
    "conversation_hi": ["नमस्ते!", "मुझे मदद चाहिए।"],
    "suggestions_en": ["I need help.", "Can you help?"],
    "suggestions_hi": ["मुझे मदद चाहिए।", "क्या आप मदद कर सकते हैं?"],
    "velocity": 0.045,
    "hands_detected": true,
    "partial_word": null,
    "timestamp": 1700000000.0
}
```

**Next Immediate Step:** Test out `collect_data.py` to ensure it captures gestures effectively and start assembling your real dataset!
