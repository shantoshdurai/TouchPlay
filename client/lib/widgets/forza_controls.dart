import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../services/websocket_service.dart';

// ── Shared theme tokens (match the monochrome "Claude" controller design) ──────
// Quiet at rest (so they don't pull the eye off the game), cyan on press.
const _kAccent  = Color(0xFF00D4FF);
const _kRest    = Color(0x66FFFFFF); // neutral border at rest
const _kRestDim = Color(0x33FFFFFF); // even quieter (secondary controls)
const _kFill    = Color(0x2200D4FF); // cyan glow fill on press

bool get _vib => WebSocketService.instance.sensitivity.vibration;

/// Steering value applies the same sensitivity + dead-zone as the analog sticks,
/// so the in-app "Steering" sliders behave identically across wheel and pads.
double _steerCurve(double raw) {
  final s    = WebSocketService.instance.sensitivity;
  final mag  = raw.abs();
  if (mag < s.deadZone) return 0.0;
  return (raw * s.stickSensitivity).clamp(-1.0, 1.0);
}

void _sendSteer(double x) => WebSocketService.instance.send({
      'type': 'left_stick',
      'x': double.parse(x.toStringAsFixed(3)),
      'y': 0.0,
    });

// ════════════════════════════════════════════════════════════════════════════
//  STEERING — WHEEL (drag left / right, analog)
// ════════════════════════════════════════════════════════════════════════════

/// Fills its parent box and paints a steering wheel anchored bottom-left.
/// Grab anywhere in the zone and drag horizontally — the wheel rotates and the
/// left stick follows. Release to straighten. Uses a single captured pointer so
/// it coexists with the pedals / buttons (independent fingers).
class SteeringWheel extends StatefulWidget {
  const SteeringWheel({super.key, required this.diameter});
  final double diameter;

  @override
  State<SteeringWheel> createState() => _SteeringWheelState();
}

class _SteeringWheelState extends State<SteeringWheel> {
  int?    _ptr;
  double  _startX = 0;
  double  _value  = 0; // post-curve, sent to the stick
  double  _angle  = 0; // visual rotation (radians)

  double get _range => widget.diameter * 0.55; // px of drag for full lock

  void _down(PointerDownEvent e) {
    if (_ptr != null) return;
    _ptr = e.pointer;
    _startX = e.localPosition.dx;
    if (_vib) HapticFeedback.selectionClick();
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _ptr) return;
    final raw = ((e.localPosition.dx - _startX) / _range).clamp(-1.0, 1.0);
    setState(() {
      _value = _steerCurve(raw);
      _angle = raw * (pi * 0.55); // up to ~100° of visual turn
    });
    _sendSteer(_value);
  }

  void _up(PointerEvent e) {
    if (e.pointer != _ptr) return;
    _ptr = null;
    setState(() { _value = 0; _angle = 0; });
    _sendSteer(0.0);
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: CustomPaint(
          painter: _WheelPainter(
            diameter: widget.diameter,
            angle: _angle,
            value: _value,
          ),
          child: const SizedBox.expand(),
        ),
      );
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter({required this.diameter, required this.angle, required this.value});
  final double diameter, angle, value;

  @override
  void paint(Canvas canvas, Size size) {
    final r = diameter / 2;
    // Anchor the wheel bottom-left of the zone.
    final c = Offset(r + diameter * 0.08, size.height - r - diameter * 0.06);
    final accent = Color.lerp(_kRest, _kAccent, value.abs())!;

    // Outer rim
    canvas.drawCircle(c, r, Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.10);

    // Faint inner guide ring
    canvas.drawCircle(c, r * 0.62, Paint()
      ..color = _kRestDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0);

    // Rotating spokes + hub + top marker
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final spoke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.06
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(-r * 0.55, 0), Offset(r * 0.55, 0), spoke);   // L–R
    canvas.drawLine(const Offset(0, 0), Offset(0, r * 0.55), spoke);     // bottom
    canvas.drawCircle(Offset.zero, r * 0.16, Paint()..color = accent);   // hub
    // 12 o'clock marker so the turn is readable
    canvas.drawLine(Offset(0, -r * 0.55), Offset(0, -r * 0.86), Paint()
      ..color = _kAccent.withOpacity(0.35 + 0.65 * value.abs())
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.07
      ..strokeCap = StrokeCap.round);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WheelPainter o) =>
      o.angle != angle || o.value != value || o.diameter != diameter;
}

// ════════════════════════════════════════════════════════════════════════════
//  STEERING — L / R PADS (digital full-lock)
// ════════════════════════════════════════════════════════════════════════════

class SteeringPad extends StatefulWidget {
  const SteeringPad({super.key, required this.left, this.size = 96});
  final bool left;
  final double size;

  @override
  State<SteeringPad> createState() => _SteeringPadState();
}

class _SteeringPadState extends State<SteeringPad> {
  int? _ptr;
  bool get _down => _ptr != null;

  void _press(PointerDownEvent e) {
    if (_ptr != null) return;
    setState(() => _ptr = e.pointer);
    _sendSteer(_steerCurve(widget.left ? -1.0 : 1.0));
    if (_vib) HapticFeedback.mediumImpact();
  }

  void _release(PointerEvent e) {
    if (e.pointer != _ptr) return;
    setState(() => _ptr = null);
    _sendSteer(0.0);
    if (_vib) HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _press,
        onPointerUp: _release,
        onPointerCancel: _release,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _down ? _kFill : Colors.transparent,
            border: Border.all(color: _down ? _kAccent : _kRest, width: 2),
          ),
          child: Icon(
            widget.left ? Icons.chevron_left : Icons.chevron_right,
            color: Colors.white,
            size: widget.size * 0.66,
          ),
        ),
      );
}

// ════════════════════════════════════════════════════════════════════════════
//  PEDALS — hold = full (gas → RT, brake → LT)
// ════════════════════════════════════════════════════════════════════════════

class RacePedal extends StatefulWidget {
  const RacePedal({
    super.key,
    required this.gas,
    required this.label,
    required this.icon,
    required this.width,
    required this.height,
  });

  final bool gas; // true → right_trigger (RT), false → left_trigger (LT)
  final String label;
  final IconData icon;
  final double width, height;

  @override
  State<RacePedal> createState() => _RacePedalState();
}

class _RacePedalState extends State<RacePedal> {
  int? _ptr;
  bool get _down => _ptr != null;
  String get _msg => widget.gas ? 'right_trigger' : 'left_trigger';

  void _press(PointerDownEvent e) {
    if (_ptr != null) return;
    setState(() => _ptr = e.pointer);
    WebSocketService.instance.send({'type': _msg, 'value': 1.0});
    if (_vib) HapticFeedback.heavyImpact();
  }

  void _release(PointerEvent e) {
    if (e.pointer != _ptr) return;
    setState(() => _ptr = null);
    WebSocketService.instance.send({'type': _msg, 'value': 0.0});
    if (_vib) HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.width * 0.28);
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _press,
      onPointerUp: _release,
      onPointerCancel: _release,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: _down ? _kAccent : _kRest, width: 2),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Fill rises from the bottom on press.
              AnimatedAlign(
                duration: const Duration(milliseconds: 90),
                alignment: Alignment.bottomCenter,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 90),
                  height: _down ? widget.height : 0,
                  color: _kFill,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, color: Colors.white, size: widget.width * 0.34),
                  const SizedBox(height: 8),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.width * 0.16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  RACE BUTTON — momentary gamepad button with icon (+ optional label)
// ════════════════════════════════════════════════════════════════════════════

class RaceButton extends StatefulWidget {
  const RaceButton({
    super.key,
    required this.button,
    required this.label,
    required this.icon,
    this.size = 64,
    this.showLabel = true,
  });

  final String button; // gamepad button name (A, B, RB, Y, RS, LB, DPAD_*, START, BACK)
  final String label;
  final IconData icon;
  final double size;
  final bool showLabel;

  @override
  State<RaceButton> createState() => _RaceButtonState();
}

class _RaceButtonState extends State<RaceButton> {
  int? _ptr;
  bool get _down => _ptr != null;

  void _press(PointerDownEvent e) {
    if (_ptr != null) return;
    setState(() => _ptr = e.pointer);
    WebSocketService.instance.send({'type': 'button_press', 'button': widget.button});
    if (_vib) HapticFeedback.mediumImpact();
  }

  void _release(PointerEvent e) {
    if (e.pointer != _ptr) return;
    setState(() => _ptr = null);
    WebSocketService.instance.send({'type': 'button_release', 'button': widget.button});
    if (_vib) HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final circle = AnimatedContainer(
      duration: const Duration(milliseconds: 60),
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _down ? _kFill : Colors.transparent,
        border: Border.all(
          color: _down ? _kAccent : (widget.showLabel ? _kRest : _kRestDim),
          width: 1.5,
        ),
      ),
      child: Icon(widget.icon, color: Colors.white, size: widget.size * 0.46),
    );

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _press,
      onPointerUp: _release,
      onPointerCancel: _release,
      child: widget.showLabel
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                circle,
                const SizedBox(height: 5),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: _down ? _kAccent : Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            )
          : circle,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  STEERING — SLIDER (center knob, drag left / right, springs back to center)
// ════════════════════════════════════════════════════════════════════════════

/// A horizontal track with a knob. Rest your thumb on it and slide left/right —
/// analog and continuous, hands stay put. Releases back to center so the car
/// straightens. The whole zone is the touch area so your thumb can roam.
class SteeringSlider extends StatefulWidget {
  const SteeringSlider({super.key, required this.width});
  final double width; // track length
  @override
  State<SteeringSlider> createState() => _SteeringSliderState();
}

class _SteeringSliderState extends State<SteeringSlider> {
  int?   _ptr;
  double _raw = 0;     // -1..1 visual knob position
  double _value = 0;   // -1..1 sent to the stick
  double _zoneW = 0;

  double get _half => widget.width / 2;

  void _update(double localX) {
    final raw = ((localX - _zoneW / 2) / _half).clamp(-1.0, 1.0);
    // Muscle-memory tick when the knob passes dead-center (strong + felt).
    if (_vib && _raw.abs() > 0.07 && raw.abs() <= 0.07) HapticFeedback.mediumImpact();
    setState(() { _raw = raw; _value = _steerCurve(raw); });
    _sendSteer(_value);
  }

  void _down(PointerDownEvent e) {
    if (_ptr != null) return;
    _ptr = e.pointer;
    _update(e.localPosition.dx);
    if (_vib) HapticFeedback.selectionClick();
  }

  void _move(PointerMoveEvent e) { if (e.pointer == _ptr) _update(e.localPosition.dx); }

  void _up(PointerEvent e) {
    if (e.pointer != _ptr) return;
    _ptr = null;
    if (_vib && _raw.abs() > 0.07) HapticFeedback.mediumImpact(); // tick as it re-centers
    setState(() { _raw = 0; _value = 0; });
    _sendSteer(0.0);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) {
        _zoneW = c.maxWidth;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          child: CustomPaint(
            painter: _SliderPainter(width: widget.width, raw: _raw, value: _value),
            child: const SizedBox.expand(),
          ),
        );
      });
}

class _SliderPainter extends CustomPainter {
  const _SliderPainter({required this.width, required this.raw, required this.value});
  final double width, raw, value;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.6;
    final half = width / 2;
    final accent = Color.lerp(_kRest, _kAccent, value.abs())!;
    const trackH = 10.0;

    final track = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: width, height: trackH),
      const Radius.circular(trackH / 2));
    canvas.drawRRect(track, Paint()..color = _kFill);
    canvas.drawRRect(track, Paint()
      ..color = _kRest..style = PaintingStyle.stroke..strokeWidth = 1.5);
    // center detent
    canvas.drawLine(Offset(cx, cy - trackH), Offset(cx, cy + trackH),
        Paint()..color = _kRestDim..strokeWidth = 2);

    // knob
    final kx = cx + raw * half;
    const kr = 26.0;
    canvas.drawCircle(Offset(kx, cy), kr, Paint()..color = const Color(0xFF15151F));
    canvas.drawCircle(Offset(kx, cy), kr, Paint()
      ..color = accent..style = PaintingStyle.stroke..strokeWidth = 2.5);
    final ic = Paint()
      ..color = Colors.white70..strokeWidth = 2
      ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(kx - 7, cy - 6), Offset(kx - 12, cy), ic);
    canvas.drawLine(Offset(kx - 12, cy), Offset(kx - 7, cy + 6), ic);
    canvas.drawLine(Offset(kx + 7, cy - 6), Offset(kx + 12, cy), ic);
    canvas.drawLine(Offset(kx + 12, cy), Offset(kx + 7, cy + 6), ic);
  }

  @override
  bool shouldRepaint(_SliderPainter o) => o.raw != raw || o.value != value || o.width != width;
}

// ════════════════════════════════════════════════════════════════════════════
//  STEERING — TILT (phone accelerometer)
// ════════════════════════════════════════════════════════════════════════════

/// Tilt the phone like a wheel to steer. Reads the accelerometer, subtracts a
/// recenter baseline, applies sensitivity + dead-zone. Always active while in
/// tilt mode. Shows a level bar + a Recenter button. If the axis/sign ever feels
/// wrong on a given phone, flip [_axis]/[_sign] — that's the only tuning knob.
class SteeringTilt extends StatefulWidget {
  const SteeringTilt({super.key, this.width = 240});
  final double width; // level-bar width (resizable when placed in a custom layout)
  @override
  State<SteeringTilt> createState() => _SteeringTiltState();
}

class _SteeringTiltState extends State<SteeringTilt> {
  StreamSubscription<AccelerometerEvent>? _sub;
  double _baseline = 0;  // captured "straight" reading
  double _reading  = 0;  // latest raw axis value
  double _value    = 0;  // steering sent

  static const double _gain = 0.9; // higher = more steering per degree of tilt
  static const double _sign = 1.0; // flip to -1.0 if reversed

  double _axisOf(AccelerometerEvent e) => e.y; // landscape roll ≈ Y on most phones

  @override
  void initState() {
    super.initState();
    _sub = accelerometerEventStream().listen((e) {
      _reading = _axisOf(e);
      final s = WebSocketService.instance.sensitivity;
      final norm = ((_reading - _baseline) / 9.8) * _gain * _sign * s.stickSensitivity;
      final v = norm.abs() < s.deadZone ? 0.0 : norm.clamp(-1.0, 1.0);
      if ((v - _value).abs() > 0.008) {
        _value = v;
        _sendSteer(v);
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() { _sub?.cancel(); _sendSteer(0.0); super.dispose(); }

  void _recenter() {
    _baseline = _reading;
    _value = 0;
    _sendSteer(0.0);
    if (_vib) HapticFeedback.mediumImpact();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: widget.width, height: 30,
          child: CustomPaint(painter: _TiltLevel(_value)),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _recenter,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kRest, width: 1.5),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.center_focus_strong, color: Colors.white, size: 14),
              SizedBox(width: 6),
              Text('RECENTER', style: TextStyle(
                color: Colors.white, fontSize: 9,
                fontWeight: FontWeight.bold, letterSpacing: 1.4)),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        const Text('TILT TO STEER', style: TextStyle(
          color: Colors.white30, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1.6)),
      ]);
}

class _TiltLevel extends CustomPainter {
  const _TiltLevel(this.value);
  final double value; // -1..1
  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final accent = Color.lerp(_kRest, _kAccent, value.abs())!;
    final track = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(size.width / 2, cy), width: size.width, height: 6),
      const Radius.circular(3));
    canvas.drawRRect(track, Paint()..color = _kRestDim);
    canvas.drawLine(Offset(size.width / 2, cy - 8), Offset(size.width / 2, cy + 8),
        Paint()..color = _kRestDim..strokeWidth = 2);
    final mx = size.width / 2 + value * (size.width / 2 - 8);
    canvas.drawCircle(Offset(mx, cy), 8, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_TiltLevel o) => o.value != value;
}
