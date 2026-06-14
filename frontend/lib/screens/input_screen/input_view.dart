import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/app_state.dart';
import '../../services/api_service.dart';
import '../../services/camera_service.dart';
import 'widgets/glass_container.dart';
import '../output_screen/output_view.dart';
import 'widgets/inventory_panel.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

class InputView extends StatefulWidget {
  final bool isAdmin;
  const InputView({Key? key, required this.isAdmin}) : super(key: key);

  @override
  State<InputView> createState() => _InputViewState();
}

class _InputViewState extends State<InputView> {
  final List<String> _suggestions = [
    "Hello", "Yes", "No", "Thanks", "Help", "Price", "Card", "Cash"
  ];

  final List<Map<String, dynamic>> _messages = [
    {"text": "Hi! Please sign or type what you'd like to say.", "isMe": false},
  ];

  late stt.SpeechToText _speech;
  final FlutterTts _flutterTts = FlutterTts();
  bool _isListening = false;
  final TextEditingController _chatController = TextEditingController();

  bool _isOnlineMode = false;
  String _storeType = "Retail";

  final List<String> _customSuggestions = [];
  final TextEditingController _customSuggestionController =
      TextEditingController();

  final TextEditingController _sessionLinkController = TextEditingController();
  Timer? _sessionPromptTimer;


  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = context.read<AppState>();
      if (appState.messages.isEmpty && appState.greeting.isNotEmpty) {
        appState.addMessage('system', appState.greeting);
      }
      // Device B: if WebSocket auto-link doesn't happen in 6s, prompt manually
      final isDeviceB = AppConstants.aslEngineHost != 'localhost';
      if (isDeviceB) {
        _sessionPromptTimer = Timer(const Duration(seconds: 6), () {
          if (!mounted) return;
          final state = context.read<AppState>();
          if (state.linkedSessionId.isEmpty) {
            _showSessionConnectDialog();
          }
        });
      }
    });
  }

  // Listen for remote screen switch commands from the other device
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.watch<AppState>();
    if (appState.pendingScreenSwitch == 'output' && mounted) {
      // Use addPostFrameCallback to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AppState>().clearPendingScreenSwitch();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const OutputView(isAdmin: true),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _chatController.dispose();
    _customSuggestionController.dispose();
    _sessionLinkController.dispose();
    _sessionPromptTimer?.cancel();
    // spelling timer managed by AppState
    _flutterTts.stop();
    super.dispose();
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    final appState = context.read<AppState>();
    // Use correct sender based on which device/mode this is
    final sender = appState.windowMode == 'customer_A_input'
        ? AppConstants.kSenderA
        : AppConstants.kSenderB;
    appState.addMessage(sender, text.trim());
    _chatController.clear();
  }

  /// Session connect dialog — works for BOTH devices:
  /// - Device A: shows its session ID to share
  /// - Device B: lets user paste Device A's session ID and connect
  void _showSessionConnectDialog() {
    final appState = context.read<AppState>();
    _sessionLinkController.text = appState.linkedSessionId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final linked = appState.linkedSessionId.isNotEmpty;
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1D21),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.blueAccent.withOpacity(0.3)),
            ),
            title: Row(
              children: [
                Icon(
                  linked ? Icons.link : Icons.link_off,
                  color: linked ? Colors.greenAccent : Colors.orangeAccent,
                ),
                const SizedBox(width: 10),
                Text(
                  linked ? 'Session Linked ✓' : 'Connect to Session',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Device A: share this session ID ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '📱 Device A — Your Session ID (share this):',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          appState.sessionId.isEmpty ? 'Loading...' : appState.sessionId,
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 13,
                            fontFamily: 'monospace',
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Device B: enter Device A's session ID ──
                  const Text(
                    '💻 Device B — Enter Device A\'s Session ID:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _sessionLinkController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Paste session ID here...',
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.06),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: _sessionLinkController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white30, size: 18),
                              onPressed: () {
                                _sessionLinkController.clear();
                                setDialogState(() {});
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),

                  // Status
                  if (linked) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Linked: ${appState.linkedSessionId}',
                              style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (linked)
                TextButton(
                  onPressed: () {
                    context.read<AppState>().joinSession('');
                    setDialogState(() {});
                  },
                  child: const Text('Unlink', style: TextStyle(color: Colors.redAccent)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Connect'),
                onPressed: () {
                  final id = _sessionLinkController.text.trim();
                  if (id.isNotEmpty) {
                    context.read<AppState>().joinSession(id);
                    setDialogState(() {});
                    Future.delayed(const Duration(milliseconds: 800), () {
                      if (mounted) Navigator.pop(ctx);
                    });
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void onSignReceived(String sign) {
    final appState = context.read<AppState>();
    appState.handleIncomingSign(sign, AppConstants.kScreenA);
  }


  Future<void> _speakText(String text) async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.speak(text);
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(onResult: (val) {
          setState(() {
            _chatController.text = val.recognizedWords;
          });
        });
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _showInventory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => InventoryPanel(
        onItemSelected: (message) {
          _sendMessage(message);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Scaffold(
      // ── Permanent session link button — visible on ALL devices ──
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Consumer<AppState>(
          builder: (ctx, state, _) {
            final linked = state.linkedSessionId.isNotEmpty;
            return FloatingActionButton.small(
              heroTag: 'session_link_fab',
              backgroundColor: linked
                  ? Colors.greenAccent.withOpacity(0.85)
                  : Colors.orangeAccent.withOpacity(0.85),
              tooltip: linked ? 'Session Linked — tap to manage' : 'Connect to Session',
              onPressed: _showSessionConnectDialog,
              child: Icon(
                linked ? Icons.link : Icons.link_off,
                color: Colors.black87,
                size: 20,
              ),
            );
          },
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // ── Session sync status banner (Device B live link indicator) ──
              Consumer<AppState>(
                builder: (context, state, _) {
                  final linked = state.linkedSessionId.isNotEmpty;
                  if (!linked) return const SizedBox.shrink();
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Live — Synced with Customer Device',
                          style: TextStyle(color: Colors.greenAccent, fontSize: 12),
                        ),
                        const Spacer(),
                        Text(
                          'Polling every 3s',
                          style: TextStyle(color: Colors.white24, fontSize: 10),
                        ),
                      ],
                    ),
                  );
                },
              ),
              // ── Main content row (left: camera, right: chat) ──
              Expanded(
                child: Row(
                  children: [
                    // ── LEFT: Camera + Suggestions ─────────────────────────
                    Expanded(
                      flex: 4,
                      child: Column(
                        children: [
                          // Camera acrylic frame
                          Expanded(
                            flex: 5,
                            child: _buildAcrylicCameraFrame(appState),
                          ),
                          const SizedBox(height: 16),
                          // Suggestion chips
                          GlassContainer(
                            child: Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  ...appState.currentSuggestions
                                      .map((t) => _buildChip(t, isAI: true)),
                                  ...appState.followupSuggestions
                                      .map((t) => _buildChip(t, isFollowup: true)),
                                  ..._suggestions.map((t) => _buildChip(t)),
                                  ..._customSuggestions.map((t) => _buildChip(t)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),

                    // ── RIGHT: Chat + Input ────────────────────────────────
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          Expanded(
                            flex: 5,
                            child: GlassContainer(
                              child: Column(
                                children: [
                                  // Header
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: AppTheme.accentGreen,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'Live Translation',
                                          style: GoogleFonts.outfit(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textPrimary,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Divider(
                                    color: AppTheme.borderDefault.withOpacity(0.6),
                                    height: 1,
                                    thickness: 1,
                                  ),
                                  // Messages
                                  Expanded(
                                    child: ListView.builder(
                                      padding: const EdgeInsets.all(16),
                                      itemCount: appState.messages.length,
                                      itemBuilder: (context, index) {
                                        final msg = appState.messages[index];
                                        final isMe =
                                            msg['sender'] == AppConstants.kSenderA;
                                        return _buildChatBubble(
                                          msg['text'] ?? '',
                                          isMe,
                                          index,
                                          msg['sender'] ?? 'A',
                                        );
                                      },
                                    ),
                                  ),
                                  // Text input
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: AppTheme.bgSurface,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                            color: AppTheme.borderAmber, width: 1.5),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.2),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: TextField(
                                        controller: _chatController,
                                        style: GoogleFonts.outfit(
                                            color: AppTheme.textPrimary,
                                            fontWeight: FontWeight.w500),
                                        decoration: InputDecoration(
                                          hintText: 'Type or speak...',
                                          hintStyle: GoogleFonts.outfit(
                                              color: AppTheme.textMuted,
                                          ),
                                          fillColor: Colors.transparent,
                                          filled: true,
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            borderSide: BorderSide.none,
                                          ),
                                          prefixIcon: IconButton(
                                            icon: Icon(
                                              _isListening
                                                  ? Icons.mic
                                                  : Icons.mic_none,
                                              color: _isListening
                                                  ? AppTheme.accentGreen
                                                  : AppTheme.textMuted,
                                            ),
                                            onPressed: _listen,
                                          ),
                                          suffixIcon: IconButton(
                                            icon: const Icon(Icons.send,
                                                color: AppTheme.amber),
                                            onPressed: () =>
                                                _sendMessage(_chatController.text),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (!widget.isAdmin)
                            _buildGuestBottomBar()
                          else
                            _buildAdminSettingsRow(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Acrylic Camera Frame ────────────────────────────────────────
  Widget _buildAcrylicCameraFrame(AppState state) {
    final appState = state; // alias so spelling overlays can use appState.*
    final running = state.aslEngineRunning;
    final status = state.aslEngineStatus;
    final starting =
        status.contains('Starting') || status.contains('loading');
    final lastAsl =
        state.messages.isNotEmpty ? state.messages.last : null;
    final hasSign = lastAsl != null && lastAsl['sender'] == 'A';
    final hasFrame = state.latestFrameBase64.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgSurface.withOpacity(0.55),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: AppTheme.borderDefault.withOpacity(0.9),
          width: 6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 32,
            offset: const Offset(0, 10),
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Live camera frame ─────────────────────────────────
            // Web:    HtmlElementView shows the live <video> element
            // Native: base64 JPEG streamed from Python via WebSocket
            if (kIsWeb && state.aslEngineRunning)
              HtmlElementView(
                viewType: CameraService.videoViewId,
              )
            else if (!kIsWeb && hasFrame)
              Image.memory(
                base64Decode(state.latestFrameBase64),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.bgCard.withOpacity(0.4),
                      AppTheme.bgSurface.withOpacity(0.25),
                    ],
                  ),
                ),
              ),

            // ── Overlay: status + sign label ─────────────────────
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(hasFrame ? 0.55 : 0.0),
                    Colors.black.withOpacity(hasFrame ? 0.75 : 0.0),
                  ],
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (starting)
                        const SizedBox(
                          width: 8,
                          height: 8,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppTheme.accentAmber,
                          ),
                        )
                      else
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: running
                                ? AppTheme.accentGreen
                                : Colors.redAccent.shade100,
                            boxShadow: running
                                ? [
                                    BoxShadow(
                                      color: AppTheme.accentGreen
                                          .withOpacity(0.6),
                                      blurRadius: 8,
                                    )
                                  ]
                                : null,
                          ),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        running
                            ? 'ASL Engine Live'
                            : starting
                                ? 'ASL Engine Starting...'
                                : 'ASL Engine Offline',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: running
                              ? AppTheme.accentGreen
                              : starting
                                  ? AppTheme.accentAmber
                                  : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                  if (!hasFrame) ...[
                    const SizedBox(height: 24),
                    Icon(
                      Icons.back_hand_outlined,
                      size: 56,
                      color: running
                          ? AppTheme.textPrimary.withOpacity(0.2)
                          : AppTheme.textPrimary.withOpacity(0.08),
                    ),
                    const SizedBox(height: 20),
                    if (hasSign)
                      Text(
                        lastAsl['text'] ?? '',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.archivoBlack(
                          color: AppTheme.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w400,
                          letterSpacing: -0.5,
                        ),
                      )
                    else
                      Text(
                        running
                            ? 'Show your hand to the camera...'
                            : starting
                                ? 'Loading models, please wait...'
                                : 'Camera not running',
                        style: GoogleFonts.outfit(
                          color: running
                              ? AppTheme.textMuted
                              : AppTheme.textMuted.withOpacity(0.5),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    if (!running && !starting) ...[
                      const SizedBox(height: 8),
                      Text(
                        status,
                        style: TextStyle(
                            color: AppTheme.textMuted.withOpacity(0.4),
                            fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ] else if (hasSign) ...[
                    // When live frame is shown, display sign label at bottom
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        lastAsl['text'] ?? '',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.archivoBlack(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Spelling mode: bottom overlay ─────────────────────────────
            if (appState.spellingMode)
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // AI suggestions row
                    if (appState.spellingSuggestions.isNotEmpty || appState.spellingLoading)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.70),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: appState.spellingLoading && appState.spellingSuggestions.isEmpty
                            ? const Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: AppTheme.accentAmber,
                                  ),
                                ),
                              )
                            : Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: appState.spellingSuggestions.map((w) {
                                  return GestureDetector(
                                    onTap: () => appState.confirmSpelledWord(w),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: AppTheme.accentAmber
                                            .withOpacity(0.18),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        border: Border.all(
                                            color: AppTheme.accentAmber
                                                .withOpacity(0.6)),
                                      ),
                                      child: Text(
                                        w,
                                        style: const TextStyle(
                                          color: AppTheme.accentAmber,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),

                    // AI correction banner
                    if (appState.spellingCorrected.isNotEmpty)
                      GestureDetector(
                        onTap: () => appState.confirmSpelledWord(appState.spellingCorrected),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.withOpacity(0.20),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    Colors.deepOrange.withOpacity(0.6)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.auto_fix_high,
                                  color: Colors.deepOrange, size: 13),
                              const SizedBox(width: 6),
                              Text(
                                'Did you mean: $appState.spellingCorrected?  Tap to use',
                                style: const TextStyle(
                                  color: Colors.deepOrange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Letters being built + controls
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.78),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.accentAmber.withOpacity(0.7),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.spellcheck,
                                  color: AppTheme.accentAmber, size: 13),
                              const SizedBox(width: 6),
                              const Text(
                                'Fingerspelling',
                                style: TextStyle(
                                    color: AppTheme.accentAmber,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => context.read<AppState>().spellingBackspace(),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.backspace_outlined,
                                      color: Colors.white54, size: 16),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => context.read<AppState>().clearSpelling(),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.clear,
                                      color: Colors.white54, size: 16),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  appState.spellingWord.isEmpty
                                      ? 'Sign letters...'
                                      : appState.spellingWord,
                                  style: GoogleFonts.archivoBlack(
                                    color: appState.spellingWord.isEmpty
                                        ? Colors.white30
                                        : Colors.white,
                                    fontSize: appState.spellingWord.isEmpty ? 13 : 24,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: 3,
                                  ),
                                ),
                              ),
                              if (appState.spellingWord.isNotEmpty)
                                GestureDetector(
                                  onTap: () => appState.confirmSpelledWord(),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accentAmber
                                          .withOpacity(0.2),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      border: Border.all(
                                          color: AppTheme.accentAmber,
                                          width: 1),
                                    ),
                                    child: const Text(
                                      'Send ✓',
                                      style: TextStyle(
                                        color: AppTheme.accentAmber,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // ── Spell toggle button (top-left of camera) ─────────────────
            Positioned(
              top: 10,
              left: 10,
              child: GestureDetector(
                onTap: () => context.read<AppState>().toggleSpellingMode(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: appState.spellingMode
                        ? AppTheme.accentAmber.withOpacity(0.25)
                        : Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: appState.spellingMode
                          ? AppTheme.accentAmber
                          : Colors.white24,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        appState.spellingMode ? Icons.spellcheck : Icons.abc,
                        color: appState.spellingMode
                            ? AppTheme.accentAmber
                            : Colors.white54,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        appState.spellingMode ? 'Spell ON' : 'Spell',
                        style: TextStyle(
                          color: appState.spellingMode
                              ? AppTheme.accentAmber
                              : Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Chips ───────────────────────────────────────────────────────
  Widget _buildChip(String text,
      {bool isAI = false, bool isFollowup = false}) {
    final appState = context.read<AppState>();
    return GestureDetector(
      onTap: () {
        if (isAI || isFollowup) {
          appState.onSuggestionTapped(text, AppConstants.kSenderA);
        } else {
          _sendMessage(text);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isAI
              ? AppTheme.accentGreen.withOpacity(0.1)
              : isFollowup
                  ? AppTheme.accentAmber.withOpacity(0.1)
                  : AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isAI
                ? AppTheme.accentGreen.withOpacity(0.5)
                : isFollowup
                    ? AppTheme.accentAmber.withOpacity(0.4)
                    : AppTheme.borderAmber,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          text,
          style: GoogleFonts.outfit(
            color: isAI
                ? AppTheme.accentGreen
                : isFollowup
                    ? AppTheme.accentAmber
                    : AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ── Chat Bubble ─────────────────────────────────────────────────
  Widget _buildChatBubble(
      String text, bool isMe, int index, String sender) {
    return GestureDetector(
      onLongPress: () async {
        final controller = TextEditingController(text: text);
        await showDialog(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: AppTheme.bgCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppTheme.borderAmber, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Edit message',
                    style: GoogleFonts.archivoBlack(
                      fontWeight: FontWeight.w400,
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    style: GoogleFonts.outfit(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppTheme.bgSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppTheme.borderAmber),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancel',
                            style: TextStyle(color: AppTheme.textMuted)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          final appState = context.read<AppState>();
                          final success = await appState.editMessage(
                              index, controller.text, sender);
                          if (!success && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Cannot edit — a newer message exists')),
                            );
                          }
                        },
                        child: Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: isMe
                ? AppTheme.bgCard
                : AppTheme.bgSurface.withOpacity(0.6),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
            border: Border.all(
              color: isMe ? AppTheme.borderAmber : AppTheme.borderDefault,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: GoogleFonts.outfit(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => _speakText(text),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.volume_up,
                        size: 11, color: AppTheme.textMuted),
                    SizedBox(width: 4),
                    Text('Listen',
                        style: GoogleFonts.outfit(
                            color: AppTheme.textMuted,
                            fontSize: 10,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Guest bottom bar ────────────────────────────────────────────
  Widget _buildGuestBottomBar() {
    return SizedBox(
      height: 60,
      child: GestureDetector(
        onTap: _showInventory,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.borderAmber, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text(
               'View Available Items',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Admin settings row ───────────────────────────────────────────────
  Widget _buildAdminSettingsRow() {
    final appState = context.watch<AppState>();
    final isHindi = appState.currentLanguage == 'hi';
    return SizedBox(
      height: 60,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.borderAmber, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Settings
            IconButton(
              icon: const Icon(Icons.settings, color: AppTheme.textSecondary),
              onPressed: _showSettingsDialog,
            ),
            Container(width: 1, height: 28, color: AppTheme.borderDefault),
            GestureDetector(
              onTap: () => context.read<AppState>().switchLanguage(isHindi ? 'en' : 'hi'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isHindi ? Colors.deepOrange.withOpacity(0.15) : Colors.blueAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isHindi ? Colors.deepOrange.withOpacity(0.5) : Colors.blueAccent.withOpacity(0.4), width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('EN', style: TextStyle(color: isHindi ? Colors.white30 : Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.w700)),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 3), child: Text('/', style: TextStyle(color: Colors.white30, fontSize: 12))),
                    Text('HI', style: TextStyle(color: isHindi ? Colors.deepOrange : Colors.white30, fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            Container(width: 1, height: 28, color: AppTheme.borderDefault),
            IconButton(
              icon: const Icon(Icons.swap_horiz, color: AppTheme.textSecondary),
              onPressed: () {
                context.read<AppState>().socketService.sendScreenSwitch('output');
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const OutputView(isAdmin: true),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallChip(String text, {bool isAI = false, bool isFollowup = false}) {
    final appState = context.read<AppState>();
    final sender = appState.windowMode == 'customer_A_input'
        ? AppConstants.kSenderA
        : AppConstants.kSenderB;
    return GestureDetector(
      onTap: () {
        if (isAI || isFollowup) {
          appState.onSuggestionTapped(text, sender);
        } else {
          _sendMessage(text);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isAI
              ? Colors.blueAccent.withOpacity(0.15)
              : isFollowup
                  ? Colors.greenAccent.withOpacity(0.1)
                  : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: isAI
              ? Border.all(color: Colors.blueAccent.withOpacity(0.3))
              : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isAI ? Colors.blueAccent : Colors.white,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setPopupState) {
            return Dialog(
              backgroundColor: AppTheme.bgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: AppTheme.borderAmber, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Admin Settings',
                        style: GoogleFonts.archivoBlack(
                          fontWeight: FontWeight.w400,
                          fontSize: 20,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Portal switch
                      _settingsCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Current Portal',
                                      style: GoogleFonts.outfit(
                                          color: AppTheme.textMuted,
                                          fontSize: 12)),
                                  Text('Input Mode (Sign)',
                                      style: GoogleFonts.outfit(
                                        color: AppTheme.accentGreen,
                                        fontWeight: FontWeight.w700,
                                      )),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.swap_horiz,
                                  color: AppTheme.textSecondary),
                              onPressed: () {
                                context.read<AppState>().socketService.sendScreenSwitch('output');
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const OutputView(isAdmin: true),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Online Mode toggle
                      _settingsCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Online Mode',
                                      style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.textPrimary)),
                                  Text('Toggle online/offline mode',
                                      style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          color: AppTheme.textMuted)),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isOnlineMode,
                              activeColor: AppTheme.accentGreen,
                              onChanged: (val) {
                                setPopupState(() => _isOnlineMode = val);
                                setState(() => _isOnlineMode = val);
                                context
                                    .read<AppState>()
                                    .saveAdminSettings('', {'is_online': val});
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Store type
                      _settingsCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('Store Category',
                                  style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary)),
                            ),
                            DropdownButton<String>(
                              dropdownColor: AppTheme.bgCard,
                              value: _storeType,
                              style: GoogleFonts.outfit(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w600),
                              underline: const SizedBox(),
                              items: ['Retail', 'Bakery', 'Cafe']
                                  .map((v) => DropdownMenuItem(
                                      value: v, child: Text(v)))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setPopupState(() => _storeType = val);
                                  setState(() => _storeType = val);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Custom suggestions
                      Text(
                        'Custom Suggestions',
                        style: GoogleFonts.archivoBlack(
                          fontWeight: FontWeight.w400,
                          fontSize: 15,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add your own suggestion chips to the sign screen.',
                        style: GoogleFonts.outfit(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.bgSurface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppTheme.borderAmber, width: 1.5),
                              ),
                              child: TextField(
                                controller: _customSuggestionController,
                                style: GoogleFonts.outfit(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'e.g. Do you accept UPI?',
                                  hintStyle: GoogleFonts.outfit(
                                      color: AppTheme.textMuted,
                                      fontSize: 13),
                                  fillColor: Colors.transparent,
                                  filled: true,
                                  border: const OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(12)),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              final text =
                                  _customSuggestionController.text.trim();
                              if (text.isNotEmpty) {
                                setPopupState(() {
                                  _customSuggestions.add(text);
                                  _customSuggestionController.clear();
                                });
                                setState(() {});
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.bgSurface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppTheme.borderAmber, width: 1.5),
                              ),
                              child: const Icon(Icons.add,
                                  color: AppTheme.amber, size: 20),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (_customSuggestions.isNotEmpty)
                        ..._customSuggestions.asMap().entries.map((e) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.bgSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: AppTheme.borderDefault, width: 1.5),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(e.value,
                                      style: GoogleFonts.outfit(
                                          color: AppTheme.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    setPopupState(() =>
                                        _customSuggestions.removeAt(e.key));
                                    setState(() {});
                                  },
                                  child: const Icon(Icons.close,
                                      color: AppTheme.textMuted, size: 16),
                                ),
                              ],
                            ),
                          );
                        })
                      else
                        Text('No custom suggestions added yet.',
                            style: GoogleFonts.outfit(
                                color: AppTheme.textMuted,
                                fontSize: 12,
                            )),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _settingsCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderDefault, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}
