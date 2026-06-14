// camera_service_web.dart
//
// KEY FIX: registerViewFactory() MUST be called synchronously BEFORE
// HtmlElementView tries to use the view type. We do this in the
// CameraService constructor (which runs as a field initializer in AppState,
// before the first widget build). The factory returns a static <div>
// container. When the camera stream is ready we append the <video> into it.

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;

class CameraService {
  static const String videoViewId = 'asl-camera-preview';
  // Lowered from 400ms → 200ms: gives BoundaryDetector ~5 frames/second,
  // which is enough velocity samples to reliably detect sign boundaries.
  static const Duration captureInterval = Duration(milliseconds: 200);

  // ── Static container ────────────────────────────────────────────────────
  // Registered once per app lifetime. HtmlElementView always gets this div.
  // We add/remove the <video> element inside it at runtime.
  static final html.DivElement _container = html.DivElement()
    ..id = 'asl-cam-wrapper'
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.overflow = 'hidden'
    ..style.background = '#000'
    ..style.display = 'flex'
    ..style.alignItems = 'center'
    ..style.justifyContent = 'center'
    ..style.position = 'relative'; // needed for Stack overlays to work correctly

  static bool _factoryRegistered = false;

  // ── Instance state ──────────────────────────────────────────────────────
  html.VideoElement? _video;
  html.CanvasElement? _canvas;
  html.MediaStream? _stream;
  Timer? _timer;

  bool get isRunning => _stream != null;

  void Function(Uint8List jpeg)? onFrame;
  void Function(String error)? onError;

  // ── Constructor: register factory SYNCHRONOUSLY ─────────────────────────
  CameraService() {
    if (!_factoryRegistered) {
      ui_web.platformViewRegistry.registerViewFactory(
        videoViewId,
        (int viewId) => _container,
      );
      _factoryRegistered = true;
    }
  }

  // ── Start camera ────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_stream != null) return;

    try {
      _stream = await html.window.navigator.mediaDevices!.getUserMedia({
        'video': {
          // Request 720p for better hand visibility on modern webcams
          'width':  {'ideal': 1280, 'min': 640},
          'height': {'ideal': 720,  'min': 480},
          'facingMode': 'user',
          // Prefer 30fps for smooth motion
          'frameRate': {'ideal': 30, 'min': 15},
        },
        'audio': false,
      });

      _video = html.VideoElement()
        ..srcObject = _stream
        ..autoplay = true
        ..muted = true
        // Fill the entire container — cover crops edges rather than letterboxing
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.transform = 'scaleX(-1)' // mirror for selfie feel
        ..style.display = 'block'        // remove inline gap under video
        ..style.position = 'absolute'    // fill parent absolutely
        ..style.top = '0'
        ..style.left = '0'
        ..setAttribute('playsinline', 'true');

      // Inject video into the already-registered container
      _container.children.clear();
      _container.append(_video!);

      // Off-screen canvas for JPEG export
      _canvas = html.CanvasElement(width: 640, height: 480);

      await _video!.play();

      _timer = Timer.periodic(captureInterval, (_) => _captureFrame());
    } catch (e) {
      onError?.call('Camera error: $e');
    }
  }

  // ── Frame capture ───────────────────────────────────────────────────────

  void _captureFrame() {
    final video = _video;
    final canvas = _canvas;
    if (video == null || canvas == null || video.readyState < 2) return;
    if (video.videoWidth == 0 || video.videoHeight == 0) return;

    // Keep canvas in sync with actual video dimensions
    if (canvas.width != video.videoWidth) canvas.width = video.videoWidth;
    if (canvas.height != video.videoHeight) canvas.height = video.videoHeight;

    final w = (canvas.width ?? 640).toDouble();
    final ctx = canvas.context2D;

    // Un-mirror the frame before sending to server
    // (the CSS transform is cosmetic only)
    ctx.save();
    ctx.translate(w, 0);
    ctx.scale(-1, 1);
    ctx.drawImage(video, 0, 0);
    ctx.restore();

    canvas.toBlob('image/jpeg', 0.75).then((blob) {
      final reader = html.FileReader();
      reader.readAsArrayBuffer(blob);
      reader.onLoad.listen((_) {
        final result = reader.result;
        if (result is Uint8List) {
          onFrame?.call(result);
        }
      });
    });
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  void stop() {
    _timer?.cancel();
    _timer = null;
    _stream?.getTracks().forEach((t) => t.stop());
    _stream = null;
    _video?.srcObject = null;
    _container.children.clear();
    _video = null;
  }

  void dispose() => stop();
}
