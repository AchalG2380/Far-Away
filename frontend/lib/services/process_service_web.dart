/// Web-safe ProcessService stub — used when running on Edge/Chrome (Device B).
/// Python ASL engine runs on Device A; Device B is browser-only.
class ProcessService {
  bool isRunning = false;
  String statusMessage = 'Web mode — ASL engine on Device A';
  int? processPid;

  void Function()? onStatusChange;

  Future<bool> startAslEngine() async {
    // No-op on web — Device B doesn't run Python
    return false;
  }

  void stop() {}
}
