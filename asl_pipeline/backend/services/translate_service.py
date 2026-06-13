from deep_translator import GoogleTranslator

# Supported language codes: "hi" = Hindi, "en" = English, "ta" = Tamil, etc.

async def translate_text(text: str, target_lang: str) -> str:
    try:
        if target_lang == "en":
            return text  # Already English, skip API call
        
        translated = GoogleTranslator(source="auto", target=target_lang).translate(text)
        return translated
    except Exception as e:
        print(f"Translation error: {e}")
        return text  # Return original if translation fails