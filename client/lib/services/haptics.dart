import 'package:vibration/vibration.dart';
import 'websocket_service.dart';

/// Central haptics. We drive the device vibrator **directly** (duration +
/// amplitude) instead of Flutter's `HapticFeedback`, which on most Android
/// phones is routed through the system "touch feedback" toggle and is either
/// silent or barely perceptible — that's why vibration felt dead before.
///
/// Strength is user-controlled: `sensitivity.vibrationStrength` (0..1) scales
/// the motor amplitude, and 0 (or the master `vibration` flag off) means silent.
class Haptics {
  Haptics._();
  static final Haptics instance = Haptics._();

  bool _hasVibrator  = false;
  bool _hasAmplitude = false;

  Future<void> init() async {
    try {
      _hasVibrator  = (await Vibration.hasVibrator()) == true;
      _hasAmplitude = (await Vibration.hasAmplitudeControl()) == true;
    } catch (_) {
      _hasVibrator = false;
    }
  }

  double get _strength {
    final s = WebSocketService.instance.sensitivity;
    if (!s.vibration) return 0.0;
    return s.vibrationStrength.clamp(0.0, 1.0);
  }

  /// One short pulse. [ms] = base duration, [amp] = base amplitude (1..255),
  /// both scaled by the user's strength setting.
  void _buzz(int ms, int amp) {
    if (!_hasVibrator) return;
    final st = _strength;
    if (st <= 0.0) return;
    final amplitude = (amp * st).round().clamp(1, 255);
    // Stronger setting also feels a touch longer — adds "weight" to a press.
    final duration = (ms * (0.7 + 0.3 * st)).round().clamp(1, 200);
    try {
      if (_hasAmplitude) {
        Vibration.vibrate(duration: duration, amplitude: amplitude);
      } else {
        // No amplitude control: gate purely on strength, vary only duration.
        Vibration.vibrate(duration: duration);
      }
    } catch (_) {}
  }

  // Semantic levels — these replace HapticFeedback.* across the app.
  void tick()   => _buzz(12, 70);    // selectionClick — light release/detent
  void light()  => _buzz(16, 110);   // lightImpact
  void medium() => _buzz(26, 170);   // mediumImpact
  void heavy()  => _buzz(45, 255);   // heavyImpact — button / pedal press

  /// Handles continuous rumble from the server.
  /// [largeMotor] and [smallMotor] are 0-255.
  void rumble(int largeMotor, int smallMotor) {
    if (!_hasVibrator) return;
    final st = _strength;
    if (st <= 0.0) return;
    
    final maxAmp = largeMotor > smallMotor ? largeMotor : smallMotor;
    if (maxAmp == 0) {
      Vibration.cancel();
      return;
    }
    
    final amplitude = (maxAmp * st).round().clamp(1, 255);
    // Rumble packets come frequently; 100ms is a good continuous buffer.
    final duration = 100;
    try {
      if (_hasAmplitude) {
        Vibration.vibrate(duration: duration, amplitude: amplitude);
      } else {
        Vibration.vibrate(duration: duration);
      }
    } catch (_) {}
  }

  /// A clearly-felt pulse used to preview the current strength while the user
  /// drags the Vibration slider in Settings.
  void preview() => _buzz(45, 255);
}
