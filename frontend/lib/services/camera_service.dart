// camera_service.dart
// Conditional import router — same pattern as process_service.dart.
//  • Flutter web  → camera_service_web.dart  (getUserMedia)
//  • Native       → camera_service_stub.dart (no-op)

export 'camera_service_stub.dart'
    if (dart.library.html) 'camera_service_web.dart';
