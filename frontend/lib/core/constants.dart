class AppConstants {
  // ── Remote Render backend (comment out when running locally) ──────────────
  // static const String localApiBaseUrl = 'https://asl-retail-backend.onrender.com';

  // ── Local backend — runs on the same machine as the Flutter app ───────────
  // Device A: keep as localhost. Device B cashier: change to Device A's LAN IP
  //   e.g. 'http://192.168.1.42:8000'
  static const String localApiBaseUrl = 'http://localhost:8000';

  /// IP of the machine running combined_asl_live.py.
  /// Device A (customer/camera machine): keep as 'localhost'
  /// Device B (cashier): change to Device A's LAN IP, e.g. '192.168.1.42'
  static const String aslEngineHost = 'localhost';

  static const String kSenderA = 'A';
  static const String kSenderB = 'B';
  static const String kScreenA = 'A';
  static const String kScreenB = 'B';
  static const String kLangEnglish = 'en';
  static const String kLangHindi = 'hi';

  // ---------------------------------------------------------
  // 2. UI STRINGS
  // ---------------------------------------------------------
  static const String cameraPlaceholder = "Camera Feed\n(MediaPipe Integration Pending)";

  // ---------------------------------------------------------
  // 3. SMART SUGGESTIONS (Dynamic Roles)
  // ---------------------------------------------------------
  // Suggestions for whoever is acting as the Customer
  static const List<String> customerSuggestions = [
    "I need help.",
    "can i get a coffee?",
    "Do you have this in stock?",
    "What is the price?",
  ];

  // Suggestions for whoever is acting as the Admin (Cashier)
  static const List<String> adminSuggestions = [
    "How can I help you?",
    "Let me check the stock for you.",
    "That will be...",
    "Here is your receipt.",
  ];
}