import 'dart:async';
import 'package:flutter/services.dart';

/// Polls native Android for battery temperature (heat) and battery level.
class DeviceStats {
  DeviceStats._();
  static final DeviceStats instance = DeviceStats._();

  static const _channel = MethodChannel('touchplay/device');

  final _ctrl = StreamController<DeviceReading>.broadcast();
  Stream<DeviceReading> get stream => _ctrl.stream;
  DeviceReading? _last;
  DeviceReading? get last => _last;

  Timer? _timer;

  void start() {
    if (_timer != null) return;
    _poll();                                   // immediate first reading
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('stats');
      if (res == null) return;
      final temp = (res['tempC'] as num?)?.toDouble() ?? -1;
      final batt = (res['battery'] as num?)?.toInt() ?? -1;
      _last = DeviceReading(tempC: temp, battery: batt);
      _ctrl.add(_last!);
    } catch (_) {
      // platform not available (e.g. desktop) — ignore
    }
  }
}

class DeviceReading {
  const DeviceReading({required this.tempC, required this.battery});
  final double tempC;   // -1 if unavailable
  final int    battery; // -1 if unavailable

  bool get hasTemp    => tempC > 0;
  bool get hasBattery => battery >= 0;
}
