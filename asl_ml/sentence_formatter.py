from typing import List, Optional


# ─── Sign → Sentence lookup tables ──────────────────────────────────────────

# Single sign mappings
SINGLE_SIGN_EN = {
    "HELLO": "Hello!",
    "THANK_YOU": "Thank you!",
    "HOW_MUCH": "How much does this cost?",
    "HELP": "I need help, please.",
    "YES": "Yes, please.",
    "NO": "No, thank you.",
    "PLEASE": "Could you please help me?",
    "SORRY": "I'm sorry.",
    "WATER": "I would like some water.",
    "RECEIPT": "Can I have the receipt?",
    "WAIT": "Please wait a moment.",
    "UNDERSTAND": "I understand.",
    "NOT_UNDERSTAND": "I don't understand.",
    "REPEAT": "Could you repeat that?",
    "SLOW": "Please go slow.",
    "WRITE": "Could you write that down?",
    "PRICE": "What is the price?",
    "DISCOUNT": "Is there a discount?",
    "CASH": "I will pay by cash.",
    "CARD": "I will pay by card.",
    "BAG": "Can I have a bag?",
    "CHANGE": "Can I get my change?",
    "EXCHANGE": "I would like to exchange this.",
    "REFUND": "I would like a refund.",
    "SIZE": "Do you have a different size?",
    "COLOR": "Do you have a different color?",
    "MORE": "I need more of this.",
    "DONE": "I am done, thank you.",
    "GOOD": "This is good!",
    "BAD": "This is not good.",
}

SINGLE_SIGN_HI = {
    "HELLO": "नमस्ते!",
    "THANK_YOU": "बहुत धन्यवाद!",
    "HOW_MUCH": "इसकी कीमत क्या है?",
    "HELP": "मुझे मदद चाहिए, कृपया।",
    "YES": "हाँ, कृपया।",
    "NO": "नहीं, धन्यवाद।",
    "PLEASE": "क्या आप मेरी मदद कर सकते हैं?",
    "SORRY": "मुझे माफ़ करें।",
    "WATER": "मुझे थोड़ा पानी चाहिए।",
    "RECEIPT": "क्या मुझे रसीद मिल सकती है?",
    "WAIT": "कृपया एक पल रुकें।",
    "UNDERSTAND": "मैं समझ गया।",
    "NOT_UNDERSTAND": "मुझे समझ नहीं आया।",
    "REPEAT": "क्या आप दोबारा बोल सकते हैं?",
    "SLOW": "कृपया धीरे बोलें।",
    "WRITE": "क्या आप लिख सकते हैं?",
    "PRICE": "कीमत क्या है?",
    "DISCOUNT": "क्या कोई छूट है?",
    "CASH": "मैं नकद भुगतान करूँगा।",
    "CARD": "मैं कार्ड से भुगतान करूँगा।",
    "BAG": "क्या मुझे थैली मिल सकती है?",
    "CHANGE": "क्या मुझे बाकी पैसे मिल सकते हैं?",
    "EXCHANGE": "मैं इसे बदलना चाहता हूँ।",
    "REFUND": "मुझे वापसी चाहिए।",
    "SIZE": "क्या आपके पास अलग साइज़ है?",
    "COLOR": "क्या आपके पास अलग रंग है?",
    "MORE": "मुझे इसमें से और चाहिए।",
    "DONE": "हो गया, धन्यवाद।",
    "GOOD": "यह अच्छा है!",
    "BAD": "यह अच्छा नहीं है।",
}

# Multi-sign phrase mappings (tuples of signs → sentence)
MULTI_SIGN_EN = {
    ("PLEASE", "HELP"): "Could you please help me?",
    ("HOW", "MUCH"): "How much does this cost?",
    ("THANK", "YOU"): "Thank you so much!",
    ("I", "WANT"): "I would like this, please.",
    ("NO", "UNDERSTAND"): "I don't understand.",
    ("PLEASE", "REPEAT"): "Could you please repeat that?",
    ("WANT", "WATER"): "I would like some water.",
    ("WANT", "RECEIPT"): "Could I please have the receipt?",
    ("HOW", "MUCH", "THIS"): "How much does this cost?",
    ("I", "NEED", "HELP"): "I need your help, please.",
}

MULTI_SIGN_HI = {
    ("PLEASE", "HELP"): "क्या आप कृपया मेरी मदद कर सकते हैं?",
    ("HOW", "MUCH"): "इसकी कीमत कितनी है?",
    ("THANK", "YOU"): "आपका बहुत-बहुत धन्यवाद!",
    ("I", "WANT"): "मैं यह लेना चाहता हूँ।",
    ("NO", "UNDERSTAND"): "मुझे समझ नहीं आया।",
    ("PLEASE", "REPEAT"): "क्या आप कृपया दोहरा सकते हैं?",
    ("WANT", "WATER"): "मुझे पानी चाहिए।",
    ("WANT", "RECEIPT"): "क्या मुझे रसीद मिल सकती है?",
    ("HOW", "MUCH", "THIS"): "इसकी कीमत क्या है?",
    ("I", "NEED", "HELP"): "कृपया मेरी मदद करें।",
}


# ─── Formatter class ─────────────────────────────────────────────────────────

class SentenceFormatter:
    def __init__(self):
        self.sign_buffer = []  # Accumulates signs until sentence complete
        self.letter_buffer = []  # Accumulates spelled-out letters

    def format_sign(self, raw_sign: str, language: str = "en") -> dict:
        """
        Convert a single raw sign to human-friendly text.
        
        Args:
            raw_sign: e.g. "HELP", "THANK_YOU", "LETTER_A"
            language: "en" or "hi"
            
        Returns:
            dict with 'en' and 'hi' text
        """
        sign = raw_sign.upper().strip()
        
        # Handle spelled letters
        if sign.startswith("LETTER_"):
            letter = sign.replace("LETTER_", "")
            self.letter_buffer.append(letter)
            # Return partial word
            word = "".join(self.letter_buffer)
            return {
                "en": f"[Spelling: {word}]",
                "hi": f"[वर्तनी: {word}]",
                "is_letter": True,
                "partial_word": word
            }
        
        # Flush letter buffer if we get a non-letter sign
        if self.letter_buffer:
            self.letter_buffer.clear()
        
        self.sign_buffer.append(sign)
        
        # Check multi-sign phrases first
        key = tuple(self.sign_buffer[-3:])  # Check last 3 signs
        for length in [3, 2]:
            k = tuple(self.sign_buffer[-length:])
            if k in MULTI_SIGN_EN:
                en = MULTI_SIGN_EN[k]
                hi = MULTI_SIGN_HI.get(k, en)
                return {"en": en, "hi": hi, "is_letter": False, "partial_word": None}
        
        # Single sign lookup
        en = SINGLE_SIGN_EN.get(sign, self._generic_format(sign))
        hi = SINGLE_SIGN_HI.get(sign, en)
        
        return {
            "en": en,
            "hi": hi,
            "is_letter": False,
            "partial_word": None
        }

    def format_sequence(self, signs: List[str], language: str = "en") -> str:
        """Format a list of signs into a complete sentence."""
        results = [self.format_sign(s, language) for s in signs]
        texts = [r["en"] if language == "en" else r["hi"] for r in results]
        return " ".join(texts)

    def flush_letters(self) -> Optional[str]:
        """Complete a spelled word and return it."""
        if self.letter_buffer:
            word = "".join(self.letter_buffer)
            self.letter_buffer.clear()
            return word
        return None

    def reset(self):
        self.sign_buffer.clear()
        self.letter_buffer.clear()

    def _generic_format(self, sign: str) -> str:
        """Fallback: convert SNAKE_CASE sign to natural language."""
        words = sign.replace("_", " ").lower().split()
        if not words:
            return sign
        
        # Add context words
        if len(words) == 1:
            return f"I need {words[0]}."
        return " ".join(words).capitalize() + "."

    def get_suggestions(self, current_sign: str, language: str = "en") -> List[str]:
        """
        Generate smart suggestions based on current partial sign.
        Used for the predictive suggestions feature.
        """
        sign = current_sign.upper().strip()
        suggestions = []
        
        if language == "en":
            lookup = SINGLE_SIGN_EN
        else:
            lookup = SINGLE_SIGN_HI
        
        # Exact match
        if sign in lookup:
            suggestions.append(lookup[sign])
        
        # Partial matches — signs that start with or contain current sign
        for key, value in lookup.items():
            if key.startswith(sign) and key != sign:
                suggestions.append(value)
        
        # Multi-sign continuations
        if self.sign_buffer:
            for phrase_tuple, sentence in MULTI_SIGN_EN.items():
                if len(phrase_tuple) > 1 and phrase_tuple[0] == self.sign_buffer[-1]:
                    if language == "en":
                        suggestions.append(sentence)
                    else:
                        suggestions.append(MULTI_SIGN_HI.get(phrase_tuple, sentence))
        
        # Default retail suggestions if nothing found
        if not suggestions:
            if language == "en":
                suggestions = [
                    "How much does this cost?",
                    "I need help, please.",
                    "Thank you!",
                    "Yes, please.",
                    "No, thank you."
                ]
            else:
                suggestions = [
                    "इसकी कीमत क्या है?",
                    "मुझे मदद चाहिए।",
                    "धन्यवाद!",
                    "हाँ, कृपया।",
                    "नहीं, धन्यवाद।"
                ]
        
        return suggestions[:5]  # Return max 5 suggestions


# ─── Offline suggestions (no model needed) ──────────────────────────────────

OFFLINE_SUGGESTIONS_CUSTOMER_EN = [
    "Hello!",
    "How much does this cost?",
    "I need help, please.",
    "Thank you!",
    "Yes, please.",
    "No, thank you.",
    "Can I have the receipt?",
    "I would like some water.",
    "I'm sorry.",
    "Could you repeat that?",
]

OFFLINE_SUGGESTIONS_CUSTOMER_HI = [
    "नमस्ते!",
    "इसकी कीमत क्या है?",
    "मुझे मदद चाहिए।",
    "धन्यवाद!",
    "हाँ, कृपया।",
    "नहीं, धन्यवाद।",
    "क्या मुझे रसीद मिल सकती है?",
    "मुझे पानी चाहिए।",
    "मुझे माफ़ करें।",
    "क्या आप दोबारा बोल सकते हैं?",
]

OFFLINE_SUGGESTIONS_RETAILER_EN = [
    "Hello! How can I help you?",
    "The price is...",
    "Would you like a bag?",
    "Cash or card?",
    "Your total is...",
    "Here is your receipt.",
    "Have a great day!",
    "Please wait a moment.",
    "I'm sorry, we don't have that.",
    "Can I show you something else?",
]

OFFLINE_SUGGESTIONS_RETAILER_HI = [
    "नमस्ते! मैं आपकी कैसे मदद कर सकता हूँ?",
    "कीमत है...",
    "क्या आपको थैली चाहिए?",
    "नकद या कार्ड?",
    "कुल राशि है...",
    "यह लीजिए आपकी रसीद।",
    "आपका दिन शुभ रहे!",
    "कृपया एक पल रुकें।",
    "माफ़ करें, यह उपलब्ध नहीं है।",
    "क्या मैं कुछ और दिखा सकता हूँ?",
]


# ─── Quick test ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    fmt = SentenceFormatter()
    
    test_signs = ["HELP", "THANK_YOU", "HOW_MUCH", "YES", "WATER", "RECEIPT",
                  "LETTER_H", "LETTER_I"]
    
    print("=== Sentence Formatter Test ===\n")
    for sign in test_signs:
        result = fmt.format_sign(sign)
        print(f"  {sign:20} → EN: {result['en']}")
        print(f"  {'':20}   HI: {result['hi']}")
        print()
    
    print("=== Suggestions for HELP ===")
    suggestions = fmt.get_suggestions("HELP", "en")
    for s in suggestions:
        print(f"  • {s}")
