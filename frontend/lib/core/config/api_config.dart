/// Where the app finds the JanYukti AI backend.
///
/// Override per build:
///
///   flutter run --dart-define=AI_API_URL=http://192.168.1.6:8000
///
/// The default reaches a backend running on the development machine from the
/// Android emulator, which maps 10.0.2.2 to the host's localhost. A physical
/// phone needs the machine's LAN address instead.
class ApiConfig {
  const ApiConfig._();

  static const String aiBaseUrl = String.fromEnvironment(
    'AI_API_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Duplicate previews and status checks should feel instant or be skipped.
  static const Duration quickTimeout = Duration(seconds: 15);

  /// Full analysis and ranking embed text on the server; allow for a slow
  /// laptop running the model on CPU.
  static const Duration analyzeTimeout = Duration(seconds: 45);
}
