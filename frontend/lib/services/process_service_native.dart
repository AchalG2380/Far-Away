import 'dart:io';
import 'dart:convert';

/// Native ProcessService — used on Windows desktop (Device A).
class ProcessService {
  Process? _process;
  bool _intentionallyStopped = false;

  bool isRunning = false;
  String statusMessage = 'Not started';
  int? processPid;

  void Function()? onStatusChange;

  static String get _projectRoot {
    final cwdParent = Directory.current.parent;
    if (File('${cwdParent.path}\\combined_asl_live.py').existsSync()) {
      return cwdParent.path;
    }
    if (File('${Directory.current.path}\\combined_asl_live.py').existsSync()) {
      return Directory.current.path;
    }
    Directory dir = File(Platform.resolvedExecutable).parent;
    for (int i = 0; i < 8; i++) {
      if (File('${dir.path}\\combined_asl_live.py').existsSync()) return dir.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return r'e:\Acro\Git\Real-Time-ASL-to-Text';
  }

  Future<bool> startAslEngine() async {
    if (_process != null) return true;
    _intentionallyStopped = false;

    final root = _projectRoot;
    final pythonExe = '$root\\.venv\\Scripts\\python.exe';
    final script = '$root\\combined_asl_live.py';

    if (!File(pythonExe).existsSync()) {
      _setStatus(false, 'Python venv not found');
      return false;
    }

    print('[ProcessService] Starting: $pythonExe $script');
    _setStatus(false, 'Starting engine...');

    try {
      _process = await Process.start(
        pythonExe, [script],
        workingDirectory: root,
        environment: {
          ...Platform.environment,
          'TF_CPP_MIN_LOG_LEVEL': '3',
          'TF_ENABLE_ONEDNN_OPTS': '0',
        },
      );

      processPid = _process!.pid;
      _setStatus(true, 'ASL engine running (pid=$processPid)');

      _process!.stdout.transform(utf8.decoder).transform(const LineSplitter())
          .listen((line) => print('[ASL] $line'));
      _process!.stderr.transform(utf8.decoder).transform(const LineSplitter())
          .listen((line) => print('[ASL ERR] $line'));

      _process!.exitCode.then((code) {
        _process = null;
        processPid = null;
        _setStatus(false, _intentionallyStopped ? 'Engine stopped' : 'Engine stopped (exit $code)');
      });

      return true;
    } catch (e) {
      _process = null;
      _setStatus(false, 'Failed to start: $e');
      return false;
    }
  }

  void stop() {
    _intentionallyStopped = true;
    _process?.kill();
    _process = null;
    processPid = null;
    _setStatus(false, 'Engine stopped');
  }

  void _setStatus(bool running, String msg) {
    isRunning = running;
    statusMessage = msg;
    onStatusChange?.call();
  }
}
