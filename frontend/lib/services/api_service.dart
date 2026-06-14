import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class ApiService {
  static const String baseUrl = AppConstants.localApiBaseUrl;

  /// Dynamic helper to construct wss:// or ws:// base URL from the HTTP baseUrl
  static String get wsBaseUrl {
    if (baseUrl.startsWith('https://')) {
      return baseUrl.replaceFirst('https://', 'wss://');
    } else if (baseUrl.startsWith('http://')) {
      return baseUrl.replaceFirst('http://', 'ws://');
    }
    return 'ws://localhost:8000'; // default fallback
  }

  // ── WEB CAMERA / PREDICTION ──────────────────────────────────────────

  // Auto-detected at runtime: true = /predict/frame works (new backend),
  // false = fall back to /predict (old backend, letter-only, no keypoints).
  static bool _useExtendedEndpoint = true;

  /// Send a single JPEG frame to the backend.
  /// Tries /predict/frame first (returns letter + keypoints for word detection).
  /// Falls back permanently to /predict if the extended endpoint is unavailable.
  static Future<Map<String, dynamic>> predictFrame(Uint8List jpegBytes) async {
    try {
      if (_useExtendedEndpoint) {
        // ── Try extended endpoint (/predict/frame) ────────────────────────
        final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/predict/frame'));
        req.files.add(http.MultipartFile.fromBytes('file', jpegBytes, filename: 'frame.jpg'));
        final streamed = await req.send().timeout(const Duration(seconds: 6));
        final res = await http.Response.fromStream(streamed);

        if (res.statusCode == 200) {
          return jsonDecode(res.body) as Map<String, dynamic>;
        }
        // Extended endpoint not available — downgrade permanently
        _useExtendedEndpoint = false;
      }

      // ── Fallback: basic /predict (works on old deployed backend) ─────────
      final req2 = http.MultipartRequest('POST', Uri.parse('$baseUrl/predict'));
      req2.files.add(http.MultipartFile.fromBytes('file', jpegBytes, filename: 'frame.jpg'));
      final streamed2 = await req2.send().timeout(const Duration(seconds: 6));
      final res2 = await http.Response.fromStream(streamed2);

      if (res2.statusCode == 200) {
        final body = jsonDecode(res2.body) as Map<String, dynamic>;
        // Normalise: add empty keypoints so callers don't need to branch
        return {...body, 'keypoints': <double>[]};
      }
    } catch (_) {}
    return {'letter': '', 'confidence': 0.0, 'detected': false, 'keypoints': <double>[]};
  }

  /// Send a 40-frame keypoint sequence for word detection.
  /// Only called when /predict/frame is available (new backend).
  static Future<Map<String, dynamic>> predictWordSequence(
    List<List<double>> sequence,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/predict/word'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'sequence': sequence}),
          )
          .timeout(const Duration(seconds: 8));
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'word': '', 'confidence': 0.0, 'detected': false};
    }
  }

  /// Reset the server-side BoundaryDetector and SentenceFormatter state.
  /// Call at the start of a new conversation to avoid stale signing state.
  static Future<void> resetPredictState() async {
    try {
      await http
          .post(Uri.parse('$baseUrl/predict/reset'))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Non-critical — ignore errors silently
    }
  }

  /// AI-powered fingerspelling autocomplete.
  /// [partialWord] is the letters signed so far (e.g. "HEL").
  /// Returns {suggestions: ["HELLO","HELP",...], corrected: "HELP"}.
  static Future<Map<String, dynamic>> getSpellingSuggestions(
    String partialWord, {
    String context = 'retail',
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/predict/spelling/suggest'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'partial_word': partialWord,
              'context': context,
              'max_suggestions': 5,
            }),
          )
          .timeout(const Duration(seconds: 4));
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return {'suggestions': <String>[], 'corrected': ''};
    }
  }

  // ── SETTINGS ─────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getPublicSettings() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/admin/settings/public'))
          .timeout(const Duration(seconds: 60));
      return jsonDecode(res.body);
    } catch (e) {
      print('getPublicSettings error: $e');
      return {
        'is_online': false,
        'store_type': 'default',
        'window_mode': 'customer_A_input',
      };
    }
  }

  // ── SESSION ──────────────────────────────────────────────────

  static Future<Map<String, dynamic>> startSession() async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/chat/session/start'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 60));
      return jsonDecode(res.body);
    } catch (e) {
      print('startSession error: $e');
      return {
        'session_id': '',
        'greeting': 'Hi! Please sign or type what you would like to say.',
      };
    }
  }

  static Future<Map<String, dynamic>> sendMessage(
    String sessionId,
    String sender,
    String text,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/chat/session/message'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'sender': sender,
              'text': text,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      print('sendMessage error: $e');
      return {'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getHistory(String sessionId) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/chat/session/$sessionId/history'))
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      print('getHistory error: $e');
      return {'history': []};
    }
  }

  /// Polls the shared backend for all messages in a session.
  /// Used by Device B (cashier) to stay in sync with Device A (customer).
  static Future<Map<String, dynamic>> getMessages(String sessionId) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/chat/session/$sessionId/history'))
          .timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      // Backend returns 'history'; normalise to 'messages' key
      return {
        'messages': data['history'] ?? data['messages'] ?? [],
      };
    } catch (e) {
      return {'messages': []};
    }
  }

  static Future<void> clearSession(String sessionId) async {
    try {
      await http
          .post(
            Uri.parse('$baseUrl/chat/session/clear'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'session_id': sessionId}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      print('clearSession error: $e');
    }
  }

  static Future<Map<String, dynamic>> editMessage(
    String sessionId,
    int index,
    String newText,
    String sender,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/chat/session/message/edit'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'message_index': index,
              'new_text': newText,
              'sender': sender,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      print('editMessage error: $e');
      return {'error': e.toString()};
    }
  }

  // ── SUGGESTIONS ──────────────────────────────────────────────

  static Future<Map<String, dynamic>> getTemplateSuggestions(
    String sign,
    String screen,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/suggestions/template'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'detected_sign': sign, 'screen': screen}),
          )
          .timeout(const Duration(seconds: 8));
      return jsonDecode(res.body);
    } catch (e) {
      print('getTemplateSuggestions error: $e');
      return {'matched': false, 'suggestions': []};
    }
  }

  static Future<Map<String, dynamic>> getSmartSuggestions(
    String sign,
    List history,
    String screen,
    String storeType,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/suggestions/smart'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'detected_sign': sign,
              'conversation_history': history,
              'screen': screen,
              'store_type': storeType,
            }),
          )
          .timeout(const Duration(seconds: 8));
      return jsonDecode(res.body);
    } catch (e) {
      print('getSmartSuggestions error: $e');
      return {'suggestions': []};
    }
  }

  static Future<Map<String, dynamic>> getPredefinedSuggestions(
    String storeType,
    String screen,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/suggestions/predefined'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'store_type': storeType, 'screen': screen}),
          )
          .timeout(const Duration(seconds: 8));
      return jsonDecode(res.body);
    } catch (e) {
      print('getPredefinedSuggestions error: $e');
      return {'suggestions': []};
    }
  }

  static Future<Map<String, dynamic>> getFollowupSuggestions(
    String chosen,
    List history,
    String storeType,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/suggestions/followup'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chosen_suggestion': chosen,
              'conversation_history': history,
              'store_type': storeType,
            }),
          )
          .timeout(const Duration(seconds: 8));
      return jsonDecode(res.body);
    } catch (e) {
      print('getFollowupSuggestions error: $e');
      return {'suggestions': []};
    }
  }

  static Future<Map<String, dynamic>> paraphraseSign(
    String sign,
    List history,
    String screen,
    String storeType,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/suggestions/paraphrase'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'raw_sign': sign,
              'conversation_history': history,
              'screen': screen,
              'store_type': storeType,
            }),
          )
          .timeout(const Duration(seconds: 8));
      return jsonDecode(res.body);
    } catch (e) {
      print('paraphraseSign error: $e');
      return {'paraphrased': 'I need ${sign.toLowerCase()}', 'raw': sign};
    }
  }

  // ── TRANSLATION ───────────────────────────────────────────────

  static Future<Map<String, dynamic>> translate(
    String text,
    String targetLang,
  ) async {
    if (text.trim().isEmpty || targetLang == 'en') {
      return {'translated': text};
    }

    // 1. Try primary Render backend (/chat/translate via deep-translator)
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/chat/translate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text, 'target_language': targetLang}),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final translated = (body['translated'] as String?) ?? '';
        // Only use if it's actually different (backend sometimes echoes original)
        if (translated.isNotEmpty && translated != text) {
          return {'translated': translated};
        }
      }
    } catch (_) {}

    // 2. Fallback: MyMemory free translation API — works directly from browser,
    //    no API key, no rate-limit for short texts, good Hindi support.
    try {
      final encoded = Uri.encodeComponent(text);
      final url =
          'https://api.mymemory.translated.net/get?q=$encoded&langpair=en|$targetLang';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final translated =
            (body['responseData']?['translatedText'] as String?) ?? '';
        if (translated.isNotEmpty && translated != text) {
          return {'translated': translated};
        }
      }
    } catch (_) {}

    return {'translated': text};
  }


  // ── SPEECH ────────────────────────────────────────────────────

  static Future<Uint8List> textToSpeech(String text) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/speech/speak'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 15));
      return res.bodyBytes;
    } catch (e) {
      print('textToSpeech error: $e');
      return Uint8List(0);
    }
  }

  static Future<Map<String, dynamic>> transcribeAudio(
    List<int> audioBytes,
    String filename,
  ) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/speech/transcribe'),
      );
      request.files.add(
        http.MultipartFile.fromBytes('audio', audioBytes, filename: filename),
      );
      final streamed = await request.send().timeout(
        const Duration(seconds: 20),
      );
      final res = await http.Response.fromStream(streamed);
      return jsonDecode(res.body);
    } catch (e) {
      print('transcribeAudio error: $e');
      return {'text': ''};
    }
  }

  // ── ADMIN ─────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> adminLogin(String password) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/admin/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'password': password}),
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      print('adminLogin error: $e');
      return {'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getAdminSettings(String token) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/admin/settings?token=$token'))
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      print('getAdminSettings error: $e');
      return {'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> updateAdminSettings(
    String password,
    Map<String, dynamic> updates,
  ) async {
    try {
      final body = {'password': password, ...updates};
      final res = await http
          .post(
            Uri.parse('$baseUrl/admin/settings/update'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      print('updateAdminSettings error: $e');
      return {'error': e.toString()};
    }
  }
}
