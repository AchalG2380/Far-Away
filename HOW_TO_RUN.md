# 🤟 ASL Retail Assistant — How to Run

A real-time American Sign Language (ASL) to text communication system for retail environments.
One device has the camera (signer), the other is the cashier screen — both sync live over WiFi.

---

## 📦 What's in this folder

```
ASL-Retail-Assistant/
├── SETUP.bat              ← Run this ONCE to install everything
├── START_DEVICE_A.bat     ← Device A (signer with camera) — run this daily
├── START_DEVICE_B.bat     ← Device B (cashier screen) — run this on 2nd machine
├── HOW_TO_RUN.md          ← This file
├── requirements.txt       ← All Python dependencies
│
├── frontend/              ← Flutter app (runs on both devices)
│   └── lib/core/constants.dart   ← IP config (auto-updated by BAT files)
│
├── asl_pipeline/backend/  ← FastAPI backend (runs only on Device A)
│   ├── main.py
│   ├── .env               ← Your API keys go here
│   └── .env.example       ← Template for .env
│
├── asl_ml/                ← ML models + MediaPipe
│   ├── models/
│   │   ├── asl_letter_model.tflite   ← Letter recognition model
│   │   └── letter_labels.json
│   └── hand_landmarker.task          ← MediaPipe hand model
│
├── Words/                 ← Word recognition model
│   ├── Final_ASL_Model_fixed.h5
│   └── Final_ASL_Classes.npy
│
└── combined_asl_live.py   ← Python camera + WebSocket engine
```

---

## ✅ Requirements (before first run)

| Software | Version | Download |
|---|---|---|
| **Python** | 3.10.x | https://python.org/downloads — check "Add to PATH" |
| **Flutter** | 3.x+ | https://flutter.dev/docs/get-started/install/windows |
| **Git** (optional) | any | https://git-scm.com |
| **Webcam** | any USB/built-in | Only needed on Device A |
| **GROQ API key** (free) | — | https://console.groq.com |

---

## 🚀 First-Time Setup (Run ONCE)

1. Double-click **`SETUP.bat`**
2. It will:
   - Create a Python virtual environment (`.venv`)
   - Install all Python packages
   - Run `flutter pub get`
   - Create `.env` file from template
3. After it finishes, open `asl_pipeline\backend\.env` and add your GROQ key:
   ```
   GROQ_API_KEY=gsk_xxxxxxxxxxxxxxxxxxxxxxxx
   ```

---

## 📱 Running on ONE machine (testing)

1. Double-click **`START_DEVICE_A.bat`**
2. It opens 3 windows automatically:
   - **Window 1:** FastAPI backend (port 8000)
   - **Window 2:** Python camera engine (port 8765)
   - **Window 3:** Flutter app (choose 1=Windows or 2=Chrome)
3. In Flutter, you'll see the signing screen — show your hand to the camera and sign!

---

## 📱📱 Running on TWO machines (real use)

### Machine A — The Signer (has camera + all models)

1. Double-click **`START_DEVICE_A.bat`**
2. Look at the window — it shows your IP:
   ```
   Your Network IP (tell this to Device B):
     http://10.229.200.34:8000
   ```
3. **Tell this IP to whoever is setting up Device B**

### Machine B — The Cashier (no camera needed)

1. Copy this entire folder to Machine B
2. Run **`SETUP.bat`** on Machine B (just Flutter setup — Python not needed)
3. Double-click **`START_DEVICE_B.bat`**
4. When asked, type Device A's IP: `10.229.200.34`
5. Flutter launches automatically, connecting to Device A

> ⚠️ **Both machines must be on the same WiFi network!**

---

## 🔧 Manual Run (if BAT files don't work)

### Terminal 1 — Backend
```powershell
cd asl_pipeline\backend
..\..\venv\Scripts\activate
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### Terminal 2 — ASL Camera Engine
```powershell
.\.venv\Scripts\activate
python combined_asl_live.py
```

### Terminal 3 — Flutter App
```powershell
cd frontend
flutter run
# Choose: 1 (Windows) or 2 (Chrome)
```

---

## 🤟 How to Use

### Signing Screen (Device A — Customer)
| Feature | How to use |
|---|---|
| **Sign a word** | Show hand to camera, hold sign 1 second |
| **Fingerspell** | Tap **[Spell]** button on camera → sign letters one by one |
| **AI word complete** | After 2+ letters, suggestion chips appear — tap to confirm |
| **Type a message** | Use the text box at the bottom |
| **Listen to message** | Tap the speaker icon on any chat bubble |
| **Switch language** | Tap **EN/HI** button in the bottom bar |

### Output Screen (Device B — Cashier)
| Feature | How to use |
|---|---|
| **See customer's signs** | Appears automatically as chat messages |
| **Reply** | Use the text input, tap send |
| **AI suggestions** | Tap any chip below the chat to quickly reply |

---

## ❓ Troubleshooting

| Problem | Fix |
|---|---|
| `AttributeError: MessageFactory` | Normal warning — ignore, protobuf compatibility issue |
| Camera not found | Check webcam is connected, try USB port |
| `Connection refused` | Make sure backend is running on port 8000 |
| Device B can't connect | Check both on same WiFi; check Windows Firewall allows port 8000 |
| `flutter pub get` fails | Run `flutter doctor` to check Flutter install |
| AI suggestions not working | Check GROQ_API_KEY in `.env` file |
| Words not recognized | Hold sign steady for 1-2 seconds; ensure good lighting |

### Allow port 8000 through Windows Firewall (Device A only)
Run this once in **Admin PowerShell** on Device A:
```powershell
New-NetFirewallRule -DisplayName "ASL Backend" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
New-NetFirewallRule -DisplayName "ASL WebSocket" -Direction Inbound -Protocol TCP -LocalPort 8765 -Action Allow
```

---

## 🔑 API Key Setup

Get a free Groq key (used for AI word suggestions + paraphrasing):
1. Go to https://console.groq.com
2. Sign up free → create an API key
3. Paste into `asl_pipeline\backend\.env`:
   ```
   GROQ_API_KEY=gsk_your_key_here
   ```
The app works without it (offline fallback) but AI features won't be as smart.

---

*Built with Flutter · FastAPI · MediaPipe · TensorFlow Lite · Groq LLaMA*
