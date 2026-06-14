import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/constants.dart';
import 'api_service.dart';
import 'socket_service.dart';
import 'process_service.dart';
import 'camera_service.dart';

class AppState extends ChangeNotifier {
  // SETTINGS
  bool isOnline = false;
  String storeType = 'default';
  String windowMode = 'customer_A_input';
  bool isLoading = true;
  String errorMessage = '';

  // SESSION
  String sessionId = '';
  /// Device B sets this to Device A's session ID to receive their messages.
  String linkedSessionId = '';
  /// Returns linkedSessionId if set, otherwise own sessionId.
  String get activeSessionId => linkedSessionId.isNotEmpty ? linkedSessionId : sessionId;
  String greeting = 'Hi! Please sign or type what you would like to say.';

  // MESSAGES
  // Each entry: {'sender': 'A'/'B', 'text': '...', 'originalText': '...'}
  List<Map<String, String>> messages = [];

  // LANGUAGE
  String currentLanguage = 'en';

  // TRANSLATION CACHE (per-device, not shared)
  // Maps originalText -> translatedText for the current language.
  // Cleared whenever the language changes.
  final Map<String, String> _translationCache = {};

  // SUGGESTIONS
  List<String> currentSuggestions = [];
  List<String> followupSuggestions = [];
  bool loadingSuggestions = false;

  // CAMERA FRAME
  /// Latest camera frame from combined_asl_live.py as base64 JPEG (native only).
  String latestFrameBase64 = '';

  // SIGNING STATE (from BoundaryDetector on server)
  /// 'idle' | 'signing' | 'boundary' — used for UI animation
  String signingState = 'idle';
  /// Hand velocity 0.0–1.0 — drives the velocity bar animation
  double signingVelocity = 0.0;

  // ── FINGERSPELLING STATE ──────────────────────────────────────────────────────
  // Kept in AppState so it intercepts BOTH the web camera path
  // (_onWebFrame → _onSignReceived → handleIncomingSign) AND the native
  // WebSocket path (socketService → _onSignReceived → handleIncomingSign).
  bool spellingMode = false;
  final List<String> spellingBuffer = [];
  String get spellingWord => spellingBuffer.join();
  List<String> spellingSuggestions = [];
  String spellingCorrected = '';  // AI correction when model likely misread a letter
  bool spellingLoading = false;
  Timer? _spellingDebounceTimer;

  // SCREEN SWITCH
  /// Set by Python relay when the other device switches view.
  /// Values: '' | 'input' | 'output'
  String pendingScreenSwitch = '';

  // ML SOCKET (native only)
  final SocketService socketService = SocketService();

  // ASL ENGINE PROCESS (native) / Web camera (web)
  final ProcessService processService = ProcessService();
  bool get aslEngineRunning => kIsWeb ? _webCameraRunning : processService.isRunning;
  String get aslEngineStatus => kIsWeb ? _webCameraStatus : processService.statusMessage;

  // WEB CAMERA SERVICE
  final CameraService webCameraService = CameraService();
  bool   _webCameraRunning = false;
  String _webCameraStatus  = 'Camera not started';

  // Rolling 40-frame keypoint buffer for word detection (web only)
  final List<List<double>> _wordKpBuffer = [];
  static const int _wordBufferSize = 40;
  int _wordPredictCooldown = 0;
  static const int _wordPredictCooldownFrames = 20;

  // Guard: skip a new frame if the previous API call hasn't returned yet.
  // Prevents piling up requests when Render latency > capture interval.
  bool _frameInFlight = false;

  // Per-letter consecutive count for web debouncing (letter -> count)
  final Map<String, int> _webLetterCount = {};
  static const int _webLetterMinCount = 2; // require 2 consecutive frames

  // DEBOUNCE FILTER
  String? _pendingSign;
  int _pendingCount = 0;
  Timer? _debounceTimer;
  static const int _minSignCount = 2;

  // POLLING (Device B / cashier sync)
  Timer? _pollTimer;

  // CHAT WEBSOCKET
  WebSocketChannel? _chatChannel;
  StreamSubscription? _chatSubscription;
  Timer? _chatReconnectTimer;

  // ADMIN
  String adminToken = '';
  bool isAdminLoggedIn = false;

  // -----------------------------------------------------------------------
  // STARTUP
  // -----------------------------------------------------------------------

  Future<void> initialize() async {
    isLoading = true;
    errorMessage = '';
    notifyListeners();

    // 1. Start ASL engine
    //    Web:    use browser camera + REST API pipeline
    //    Native: launch combined_asl_live.py subprocess (Device A only)
    if (kIsWeb) {
      _webCameraStatus = 'Starting camera...';
      notifyListeners();
      webCameraService.onFrame = _onWebFrame;
      webCameraService.onError = (err) {
        _webCameraStatus  = err;
        _webCameraRunning = false;
        notifyListeners();
      };
      await webCameraService.start();
      _webCameraRunning = webCameraService.isRunning;
      _webCameraStatus  = _webCameraRunning ? 'ASL Engine Live' : 'Camera failed';
      notifyListeners();
    } else {
      if (windowMode == 'customer_A_input' || AppConstants.aslEngineHost == 'localhost') {
        processService.onStatusChange = notifyListeners;
        processService.startAslEngine();
      }
    }

    // 2. Fetch backend settings
    try {
      final settings = await ApiService.getPublicSettings();
      isOnline = settings['is_online'] ?? false;
      storeType = settings['store_type'] ?? 'default';
      windowMode = settings['window_mode'] ?? 'customer_A_input';
    } catch (e) {
      errorMessage = 'Could not reach server. Running in offline mode.';
      isOnline = false;
    }

    // 3. Start chat session
    try {
      final session = await ApiService.startSession();
      sessionId = session['session_id'] ?? '';
      greeting = session['greeting'] ?? greeting;
      _connectChatWebSocket(sessionId);
    } catch (e) {
      errorMessage = 'Could not start session. Please restart the app.';
    }

    // 4. Connect WebSocket (native only — Python WS server on port 8765)
    //    On web: no local Python, so skip the WebSocket entirely.
    if (!kIsWeb) {
      await Future.delayed(const Duration(seconds: 3));
      socketService.setHost(AppConstants.aslEngineHost);

      // Device B: auto-join Device A's session when Python relays it
      socketService.onSessionInfo = (String remoteSessionId) {
        if (linkedSessionId != remoteSessionId) {
          joinSession(remoteSessionId);
          print('[AppState] Auto-joined session from Device A: $remoteSessionId');
        }
      };

      // Camera frame relay: store latest base64 JPEG and notify UI
      socketService.onFrame = (String b64) {
        latestFrameBase64 = b64;
        notifyListeners();
      };

      // Screen switch relay: notify views to navigate
      socketService.onScreenSwitch = (String screen) {
        pendingScreenSwitch = screen;
        notifyListeners();
      };

      socketService.connect(
        (sign, confidence, source) => _onSignReceived(sign, confidence, source),
        mySessionId: sessionId,
      );
    }

    // 5. Start polling for new messages (Device B / cashier real-time sync)
    _startPolling();

    isLoading = false;
    notifyListeners();
  }

  /// Clear the pending screen switch after the view has handled it.
  void clearPendingScreenSwitch() {
    pendingScreenSwitch = '';
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _pollTimer?.cancel();
    _chatSubscription?.cancel();
    _chatReconnectTimer?.cancel();
    _chatChannel?.sink.close();
    socketService.disconnect();
    processService.stop();
    webCameraService.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // WEB CAMERA FRAME HANDLER
  // -----------------------------------------------------------------------

  /// Called by [CameraService] each time a new JPEG frame is ready.
  /// Guards against concurrent requests (Render latency can exceed 400ms capture interval).
  Future<void> _onWebFrame(Uint8List jpegBytes) async {
    // Skip if the previous request hasn't returned yet (avoid queue build-up)
    if (_frameInFlight) return;
    _frameInFlight = true;

    try {
      final result   = await ApiService.predictFrame(jpegBytes);
      final detected = result['detected'] as bool? ?? false;

      // ── Update signing state / velocity for UI animation ─────────────────
      final newState    = result['signing_state'] as String? ?? 'idle';
      final newVelocity = (result['velocity'] as num?)?.toDouble() ?? 0.0;
      if (newState != signingState || (newVelocity - signingVelocity).abs() > 0.005) {
        signingState    = newState;
        signingVelocity = newVelocity;
        notifyListeners();
      }

      // ── PRIMARY PATH: Server-side boundary detection ──────────────────────
      // When the backend's BoundaryDetector fires, boundary_detected=true and
      // word_from_boundary is populated. Use this immediately — no debouncing
      // needed since the server already confirmed a complete sign.
      final boundaryDetected = result['boundary_detected'] as bool? ?? false;
      if (boundaryDetected) {
        final word       = result['word_from_boundary'] as String? ?? '';
        final wordConf   = (result['word_confidence'] as num?)?.toDouble() ?? 0.0;
        if (word.isNotEmpty) {
          _webLetterCount.clear();
          _wordKpBuffer.clear();
          _onSignReceived(word, wordConf, 'word_model');
          return; // done — skip letter/buffer paths below
        }
      }

      // ── SECONDARY PATH: Letter debounce (visual feedback + fingerspelling) ─
      if (detected) {
        final letter     = result['letter']     as String? ?? '';
        // Threshold lowered to 0.55 (local backend is faster = less compression).
        final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;

        if (letter.isNotEmpty && confidence >= 0.55) {
          // Require _webLetterMinCount consecutive frames of the same letter
          _webLetterCount.updateAll((k, v) => k == letter ? v : 0);
          final count = (_webLetterCount[letter] ?? 0) + 1;
          _webLetterCount[letter] = count;

          if (count >= _webLetterMinCount) {
            _webLetterCount[letter] = 0; // reset after confirmation
            _onSignReceived(letter, confidence, 'alphabet_model');
          }
        } else {
          // Low confidence — decay all counts
          _webLetterCount.updateAll((k, v) => (v - 1).clamp(0, 99));
        }
      } else {
        // No hand detected — reset letter counts
        _webLetterCount.clear();
      }

      // ── TERTIARY PATH: Client-side 40-frame word buffer (fallback) ─────────
      // Only used if the server boundary detector didn't fire yet.
      final rawKp = result['keypoints'] as List? ?? [];
      if (rawKp.isNotEmpty) {
        final kp = rawKp.map((v) => (v as num).toDouble()).toList();
        _wordKpBuffer.add(kp);
        if (_wordKpBuffer.length > _wordBufferSize) _wordKpBuffer.removeAt(0);

        if (_wordPredictCooldown > 0) {
          _wordPredictCooldown--;
        } else if (_wordKpBuffer.length == _wordBufferSize) {
          _predictWordSequence();
          _wordPredictCooldown = _wordPredictCooldownFrames;
        }
      } else if (!detected) {
        if (_wordKpBuffer.length > _wordBufferSize ~/ 2) _wordKpBuffer.clear();
      }
    } catch (_) {
      // Silently ignore individual frame errors
    } finally {
      _frameInFlight = false;
    }
  }

  Future<void> _predictWordSequence() async {
    if (_wordKpBuffer.length < _wordBufferSize) return;
    final snapshot = List<List<double>>.from(_wordKpBuffer);
    try {
      final result   = await ApiService.predictWordSequence(snapshot);
      final detected = result['detected'] as bool? ?? false;
      if (detected) {
        final word       = result['word']       as String? ?? '';
        final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;
        if (word.isNotEmpty) {
          _onSignReceived(word, confidence, 'word_model');
          _wordKpBuffer.clear();
        }
      }
    } catch (_) {}
  }

  // -----------------------------------------------------------------------
  // DEBOUNCE FILTER
  // -----------------------------------------------------------------------

  void _onSignReceived(String sign, double confidence, String source) {
    final sender = windowMode == 'customer_A_input' ? 'A' : 'B';

    // Word model signs are already confirmed by consecutive-frame logic
    // (Python side on native, word buffer on web) -> pass through immediately.
    if (source == 'word_model') {
      _pendingSign = null;
      _pendingCount = 0;
      _debounceTimer?.cancel();
      handleIncomingSign(sign, sender);
      return;
    }

    // Alphabet model: require _minSignCount consecutive same letter.
    if (sign != _pendingSign) {
      _pendingSign = sign;
      _pendingCount = 1;
    } else {
      _pendingCount++;
      if (_pendingCount >= _minSignCount) {
        _pendingSign = null;
        _pendingCount = 0;
        handleIncomingSign(sign, sender);
      }
    }
  }

  // -----------------------------------------------------------------------
  // POLLING (keeps Device B/cashier in sync with Device A as fallback)
  // -----------------------------------------------------------------------

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      // If WebSocket is active, we don't need to poll
      if (_chatChannel != null && _chatSubscription != null) return;
      if (activeSessionId.isEmpty) return;
      try {
        final result = await ApiService.getMessages(activeSessionId);
        final rawList = result['messages'] as List? ?? [];
        await _updateMessagesFromHistory(rawList);
      } catch (_) {}
    });
  }

  Future<void> _updateMessagesFromHistory(List rawList) async {
    final remote = rawList.map((m) {
      final sender = (m['sender'] ?? m['role'] ?? 'A') as String;
      final text   = (m['text']   ?? m['content'] ?? '') as String;
      return <String, String>{'sender': sender, 'text': text, 'originalText': text};
    }).toList();

    if (remote.length != messages.length) {
      if (currentLanguage != 'en') {
        for (final msg in remote) {
          final orig = msg['originalText']!;
          if (_translationCache.containsKey(orig)) {
            msg['text'] = _translationCache[orig]!;
          } else {
            try {
              final res = await ApiService.translate(orig, currentLanguage);
              final translated = res['translated'] ?? orig;
              _translationCache[orig] = translated;
              msg['text'] = translated;
            } catch (_) {
              msg['text'] = orig;
            }
          }
        }
      }
      messages = remote;
      notifyListeners();
    }
  }

  // -----------------------------------------------------------------------
  // CHAT WEBSOCKET
  // -----------------------------------------------------------------------

  Future<void> _connectChatWebSocket(String targetSessionId) async {
    _chatSubscription?.cancel();
    _chatSubscription = null;
    _chatChannel?.sink.close();
    _chatChannel = null;
    _chatReconnectTimer?.cancel();

    if (targetSessionId.isEmpty) return;

    final baseWs = ApiService.wsBaseUrl;
    final wsUrl = '$baseWs/chat/ws/$targetSessionId';

    print('[AppState] Connecting to chat WebSocket: $wsUrl');
    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _chatChannel = channel;
      
      // Await ready in a try/catch to handle connection failure cleanly
      await channel.ready;
      
      // Guard: if session ID changed while connecting, abort
      if (activeSessionId != targetSessionId) {
        channel.sink.close();
        return;
      }
      
      print('[AppState] Chat WebSocket connected successfully');

      _chatSubscription = channel.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            if (data['type'] == 'history') {
              final rawList = data['history'] as List? ?? [];
              _updateMessagesFromHistory(rawList);
            }
          } catch (e) {
            print('[AppState] Error parsing chat WS message: $e');
          }
        },
        onError: (err) {
          print('[AppState] Chat WS stream error: $err');
          _scheduleChatWsReconnect(targetSessionId);
        },
        onDone: () {
          print('[AppState] Chat WS stream closed');
          _scheduleChatWsReconnect(targetSessionId);
        },
        cancelOnError: true,
      );
    } catch (e) {
      print('[AppState] Chat WS connection failed: $e');
      _scheduleChatWsReconnect(targetSessionId);
    }
  }

  void _scheduleChatWsReconnect(String targetSessionId) {
    _chatSubscription?.cancel();
    _chatSubscription = null;
    _chatChannel = null;
    _chatReconnectTimer?.cancel();

    if (targetSessionId.isEmpty) return;

    _chatReconnectTimer = Timer(const Duration(seconds: 3), () {
      if (activeSessionId == targetSessionId) {
        _connectChatWebSocket(targetSessionId);
      }
    });
  }

  // -----------------------------------------------------------------------
  // SESSION
  // -----------------------------------------------------------------------

  Future<void> resetConversation() async {
    if (sessionId.isNotEmpty) {
      await ApiService.clearSession(sessionId);
    }
    // Reset the server-side BoundaryDetector + SentenceFormatter state so
    // lingering velocity / sign-buffer from the previous session doesn't
    // contaminate the new conversation.
    await ApiService.resetPredictState();

    final session = await ApiService.startSession();
    sessionId = session['session_id'] ?? '';
    messages = [];
    currentSuggestions = [];
    followupSuggestions = [];
    currentLanguage = 'en';
    signingState    = 'idle';
    signingVelocity = 0.0;
    _webLetterCount.clear();
    _wordKpBuffer.clear();
    notifyListeners();
    _connectChatWebSocket(sessionId);

    // Register the new session ID with the Python server so Device B receives it
    if (!kIsWeb) {
      socketService.registerSession(sessionId);
    }
  }

  /// Device B calls this with Device A's session ID to sync messages.
  void joinSession(String remoteSessionId) {
    linkedSessionId = remoteSessionId.trim();
    messages = [];
    notifyListeners();
    print('[AppState] Joined session: $linkedSessionId');
    _connectChatWebSocket(activeSessionId);
  }

  // -----------------------------------------------------------------------
  // MESSAGES
  // -----------------------------------------------------------------------

  Future<void> addMessage(String sender, String text) async {
    final displayText = currentLanguage != 'en'
        ? (await ApiService.translate(text, currentLanguage))['translated'] ?? text
        : text;
    messages.add({'sender': sender, 'text': displayText, 'originalText': text});
    notifyListeners();

    final sid = activeSessionId;
    if (sid.isNotEmpty) {
      await ApiService.sendMessage(sid, sender, text);
    }
  }

  // Returns true if edit succeeded, false if blocked
  Future<bool> editMessage(int index, String newText, String sender) async {
    if (sessionId.isEmpty) return false;
    final result = await ApiService.editMessage(
      sessionId,
      index,
      newText,
      sender,
    );
    if (!result.containsKey('error')) {
      messages[index]['text'] = newText;
      messages[index]['originalText'] = newText;
      notifyListeners();
      return true;
    }
    return false;
  }

  // -----------------------------------------------------------------------
  // FINGERSPELLING METHODS (callable from UI)
  // -----------------------------------------------------------------------

  void toggleSpellingMode() {
    spellingMode = !spellingMode;
    if (!spellingMode) clearSpelling();
    notifyListeners();
  }

  void spellingBackspace() {
    if (spellingBuffer.isEmpty) return;
    spellingBuffer.removeLast();
    notifyListeners();
    _spellingDebounceTimer?.cancel();
    _spellingDebounceTimer = Timer(
      const Duration(milliseconds: 400),
      _fetchSpellingSuggestions,
    );
  }

  void clearSpelling() {
    spellingBuffer.clear();
    spellingSuggestions = [];
    spellingCorrected = '';
    spellingLoading = false;
    _spellingDebounceTimer?.cancel();
    notifyListeners();
  }

  /// Confirm the buffered word (or an override) and SEND IT TO CHAT.
  /// Works like onSuggestionTapped: the word goes directly into messages,
  /// then paraphrase + follow-up suggestions are fetched in the background.
  Future<void> confirmSpelledWord([String? override]) async {
    final word = override ?? spellingWord;
    if (word.isEmpty) return;
    clearSpelling();  // clear buffer first

    final sender = windowMode == 'customer_A_input'
        ? AppConstants.kSenderA
        : AppConstants.kSenderB;

    // 1. Add the spelled word directly to chat
    await addMessage(sender, word);
    currentSuggestions = [];
    notifyListeners();

    // 2. Get follow-up suggestions in the background (same as onSuggestionTapped)
    if (isOnline) {
      try {
        final followup = await ApiService.getFollowupSuggestions(
          word,
          _getRecentHistory(),
          storeType,
        );
        followupSuggestions = List<String>.from(followup['suggestions'] ?? []);
        if (currentLanguage != 'en' && followupSuggestions.isNotEmpty) {
          followupSuggestions = await _translateList(followupSuggestions, currentLanguage);
        }
        notifyListeners();
      } catch (_) {
        // non-critical — ignore
      }
    }
  }


  Future<void> _fetchSpellingSuggestions() async {
    if (spellingBuffer.isEmpty) return;
    spellingLoading = true;
    notifyListeners();
    try {
      final result = await ApiService.getSpellingSuggestions(spellingWord);
      spellingSuggestions = List<String>.from(result['suggestions'] as List? ?? []);
      spellingCorrected   = result['corrected'] as String? ?? '';
    } catch (_) {
      spellingSuggestions = [];
      spellingCorrected   = '';
    } finally {
      spellingLoading = false;
      notifyListeners();
    }
  }

  // -----------------------------------------------------------------------
  // SIGN HANDLING
  // -----------------------------------------------------------------------

  Future<void> handleIncomingSign(String sign, String screen) async {
    // ── SPELLING MODE: intercept single letters and buffer them ───────────────
    // A "letter" is a single uppercase A–Z character.
    // Words from the word model (multi-char) pass through normally.
    if (spellingMode && sign.length == 1 && sign == sign.toUpperCase() && RegExp(r'^[A-Z]$').hasMatch(sign)) {
      spellingBuffer.add(sign);
      notifyListeners();
      // Debounce AI suggestion fetch: wait 600ms after last letter
      _spellingDebounceTimer?.cancel();
      _spellingDebounceTimer = Timer(
        const Duration(milliseconds: 600),
        _fetchSpellingSuggestions,
      );
      return; // Do NOT process as a message
    }
    // Show instant fallback chips RIGHT NOW (no network wait)
    final capitalized = sign[0].toUpperCase() + sign.substring(1).toLowerCase();
    currentSuggestions = [
      'I need $capitalized',
      'Can I get $capitalized please?',
      capitalized,
    ];
    loadingSuggestions = true;
    followupSuggestions = [];
    notifyListeners();

    // Then enhance with backend paraphrase + template suggestions
    final recentHistory = _getRecentHistory();
    try {
      final results = await Future.wait([
        ApiService.paraphraseSign(sign, recentHistory, screen, storeType),
        isOnline
            ? ApiService.getTemplateSuggestions(sign, screen)
            : ApiService.getPredefinedSuggestions(storeType, screen),
      ]);

      final sentence = results[0]['paraphrased'] ?? 'I need ${sign.toLowerCase()}';
      final extraSuggestions = List<String>.from(results[1]['suggestions'] ?? []);

      currentSuggestions = List<String>.from([
        sentence,
        ...extraSuggestions.where((s) => s.trim().toLowerCase() != sentence.trim().toLowerCase()),
      ].take(5).toList());
    } catch (e) {
      // Keep the instant fallback chips already shown
    }

    if (currentLanguage != 'en') {
      currentSuggestions = await _translateList(currentSuggestions, currentLanguage);
    }

    loadingSuggestions = false;
    notifyListeners();
  }

  Future<void> onSuggestionTapped(String suggestion, String sender) async {
    await addMessage(sender, suggestion);
    currentSuggestions = [];
    notifyListeners();

    if (isOnline) {
      final followup = await ApiService.getFollowupSuggestions(
        suggestion,
        _getRecentHistory(),
        storeType,
      );
      followupSuggestions = List<String>.from(followup['suggestions'] ?? []);

      if (currentLanguage != 'en' && followupSuggestions.isNotEmpty) {
        followupSuggestions = await _translateList(followupSuggestions, currentLanguage);
      }
      notifyListeners();
    }
  }

  // -----------------------------------------------------------------------
  // LANGUAGE
  // -----------------------------------------------------------------------

  Future<void> switchLanguage(String langCode) async {
    if (langCode == currentLanguage) return;
    currentLanguage = langCode;
    _translationCache.clear();

    if (langCode == 'en') {
      for (var msg in messages) {
        msg['text'] = msg['originalText'] ?? msg['text']!;
      }
      currentSuggestions = List<String>.from(currentSuggestions);
      followupSuggestions = List<String>.from(followupSuggestions);
    } else {
      for (var msg in messages) {
        final orig = msg['originalText'] ?? msg['text']!;
        final result = await ApiService.translate(orig, langCode);
        final translated = result['translated'] ?? orig;
        _translationCache[orig] = translated;
        msg['text'] = translated;
      }
      if (currentSuggestions.isNotEmpty) {
        currentSuggestions = await _translateList(currentSuggestions, langCode);
      }
      if (followupSuggestions.isNotEmpty) {
        followupSuggestions = await _translateList(followupSuggestions, langCode);
      }
    }
    notifyListeners();
  }

  // -----------------------------------------------------------------------
  // ADMIN
  // -----------------------------------------------------------------------

  Future<bool> adminLogin(String password) async {
    final result = await ApiService.adminLogin(password);
    if (result['token'] == 'admin_authenticated') {
      adminToken = result['token'];
      isAdminLoggedIn = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> loadAdminSettings() async {
    return await ApiService.getAdminSettings(adminToken);
  }

  Future<void> saveAdminSettings(
    String password,
    Map<String, dynamic> updates,
  ) async {
    await ApiService.updateAdminSettings(password, updates);
    if (updates.containsKey('is_online')) isOnline = updates['is_online'];
    if (updates.containsKey('store_type')) storeType = updates['store_type'];
    if (updates.containsKey('window_mode')) windowMode = updates['window_mode'];
    notifyListeners();
  }

  // -----------------------------------------------------------------------
  // HELPERS
  // -----------------------------------------------------------------------

  List<Map<String, String>> _getRecentHistory() {
    final recent = messages.length > 4
        ? messages.sublist(messages.length - 4)
        : messages;
    return recent
        .map(
          (m) => {
            'sender': m['sender']!,
            'text': m['originalText'] ?? m['text']!,
          },
        )
        .toList();
  }

  /// Translate a list of strings to [langCode].
  /// Populates [_translationCache]. Falls back to originals on error.
  Future<List<String>> _translateList(List<String> items, String langCode) async {
    final translated = <String>[];
    for (final item in items) {
      if (_translationCache.containsKey(item)) {
        translated.add(_translationCache[item]!);
        continue;
      }
      try {
        final res = await ApiService.translate(item, langCode);
        final t = res['translated'] ?? item;
        _translationCache[item] = t;
        translated.add(t);
      } catch (_) {
        translated.add(item);
      }
    }
    return translated;
  }
}