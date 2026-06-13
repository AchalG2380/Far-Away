# CosmicSigns

> A real-time ASL communication tablet for deaf and hard-of-hearing individuals at retail counters.

---

## What is CosmicSigns?

CosmicSigns is a dual-screen tablet system mounted at a retail counter that enables seamless communication between a deaf or hard-of-hearing person and anyone on the other side — using American Sign Language (ASL). The camera detects the signer's hand gestures, converts them to text instantly, and displays natural-language output to the other person in real time.

The system is designed for two equal scenarios:
- A **deaf customer** communicating with a hearing cashier
- A **deaf employee** communicating with a hearing customer

No architectural change is needed — an administrator toggle switches the orientation.

---

## Features

### Core
- **Real-time ASL recognition** — Hand tracking with a 21-point skeleton overlay and live sign detection
- **Dual-screen display** — One screen for the signer (Input Window), one for the other party (Output Window)
- **Natural language formatting** — Raw sign labels are automatically converted to readable sentences (e.g., `HELP` → *"I need help."*)
- **Text-to-speech** — Any chat bubble can be read aloud via a speaker button
- **Keyboard input** — Fallback typing option for both parties
- **Speech-to-text replies** — Hearing staff can speak their response instead of typing

### Smart Suggestions (Online Mode)
- **Real-time prediction** — Mid-gesture completions via Gemini (OpenRouter API)
- **Contextual follow-ups** — Post-message suggestions tailored to store type and conversation context
- **Role-aware suggestions** — Separate suggestion sets for the signer and the staff member

### Bilingual Support
- Full chat translation via Google Translate API (online)
- English ↔ Hindi static dictionary (offline fallback)
- Language toggle available independently on both screens

### Inventory Integration
- Signer can browse store inventory (name, price, availability)
- Items can be added to a session cart and sent as a message

### Offline Mode
All core features work without internet:
- ASL recognition (TFLite model, fully on-device)
- Pre-defined store-type suggestions (JSON bundles)
- English ↔ Hindi translation (static dictionary)
- Cached inventory from last sync
- Chat, TTS, and keyboard input

What requires internet: Gemini smart suggestions, Google Translate for languages other than Hindi.

---

## System Architecture

### Display
| Screen | Faces | Purpose |
|---|---|---|
| Input Window | Signer | Camera preview, skeleton overlay, sign detection, chat history |
| Output Window | Other party | Large-text chat feed, response suggestions, speech-to-text input |

### Users
| Role | Login | Access |
|---|---|---|
| Administrator | PIN/password (separate device) | Full admin panel — display control, mode toggle, store config, inventory |
| Signer / Staff | None | Main tablet only — no settings access |

### Sessions
Every session is **anonymous and temporary**. No data is retained after a conversation ends. The "New Conversation" button wipes all chat history instantly.

---

## Admin Panel

The admin panel runs on a separate designated device (back-office tablet or manager's phone) and is never accessible from the customer-facing tablet. It has four sections:

- **Display Control** — Toggle Input/Output window orientation
- **Online / Offline Mode** — Switch between full-feature and offline operation
- **Store Configuration** — Select store type (Retail, Coffee Shop, Bakery, Restaurant, Pharmacy, or custom) to load relevant suggestion sets; add custom suggestions
- **Inventory Management** — Add, edit, or remove items (name, price, availability)

> **Note:** There is no "forgot PIN" flow by design. If the PIN is lost, a system reset is required.

---

## How a Conversation Works

1. Deaf customer approaches the counter
2. Camera detects hands — green skeleton overlay appears on signer's screen
3. Customer signs `HELLO` → system shows *"Hello!"* on both screens
4. Cashier taps a suggestion: *"Hi! How can I help you today?"*
5. Customer signs `HOW_MUCH`, points at item → *"How much does this cost?"* is sent
6. Cashier types or speaks the price → appears in customer's chat window
7. Transaction completes
8. Cashier taps **New Conversation** → session is wiped, system resets

---

## Roadmap

### Near-term
- Two-handed sign support (126 keypoint features)
- Fingerspelling recognition (ASL alphabet as fallback)
- Expanded vocabulary (8 signs → 100+ common signs)
- Confidence indicator for detection quality

### Medium-term
- Indian Sign Language (ISL) support
- British Sign Language (BSL), Auslan, and others
- Two-way simultaneous signing (dual-camera setup)
- Dedicated counter hardware with weatherproof enclosure

### Long-term
- Continuous signing recognition (no pauses required between signs)
- Personalized signing models per user
- Sign language generation (animated avatar replies)
- Multi-location sync with centralized admin
- POS system integration

---

## Tech Stack

| Component | Technology |
|---|---|
| ASL Recognition | TFLite (on-device) |
| Smart Suggestions | Gemini via OpenRouter API |
| Translation | Google Translate API / static Hindi dictionary (offline) |
| Speech-to-Text | Cloud speech service |

---

## License

*Add your license information here.*
