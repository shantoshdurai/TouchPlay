import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/websocket_service.dart';

// Xbox face button colors
const _faceColors = {
  'A': Color(0xFF1DB954),
  'B': Color(0xFFE53935),
  'X': Color(0xFF1565C0),
  'Y': Color(0xFFF9A825),
};

const _neutralColor = Color(0xFF3A3A55);

class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key,
    required this.button,
    this.size = 50.0,
    this.label,
    this.color,
    this.icon,
  });

  final String button;
  final double size;
  final String? label;
  final Color? color;
  final IconData? icon;

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late AnimationController _scale;

  Color get _base => widget.color ?? _faceColors[widget.button] ?? _neutralColor;

  @override
  void initState() {
    super.initState();
    _scale = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 60),
        lowerBound: 0.85,
        upperBound: 1.0)
      ..value = 1.0;
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  void _down() {
    if (_pressed) return;
    setState(() => _pressed = true);
    _scale.reverse();
    WebSocketService.instance.send({'type': 'button_press', 'button': widget.button});
    HapticFeedback.lightImpact();
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    _scale.forward();
    WebSocketService.instance.send({'type': 'button_release', 'button': widget.button});
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      onPanDown: (_) => _down(),
      onPanEnd: (_) => _up(),
      onPanCancel: _up,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _pressed ? _base : _base.withOpacity(0.28),
            border: Border.all(color: _base, width: 2),
            boxShadow: _pressed
                ? [BoxShadow(color: _base.withOpacity(0.55), blurRadius: 14, spreadRadius: 2)]
                : [],
          ),
          child: Center(
            child: widget.icon != null
                ? Icon(widget.icon, color: Colors.white, size: widget.size * 0.42)
                : Text(
                    widget.label ?? widget.button,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.size * 0.3,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Bumper button (LB / RB) — rounded pill shape
class BumperButton extends StatefulWidget {
  const BumperButton({
    super.key,
    required this.button,
    required this.label,
    this.width = 80.0,
    this.height = 32.0,
  });

  final String button;
  final String label;
  final double width;
  final double height;

  @override
  State<BumperButton> createState() => _BumperButtonState();
}

class _BumperButtonState extends State<BumperButton> {
  bool _pressed = false;

  void _down() {
    if (_pressed) return;
    setState(() => _pressed = true);
    WebSocketService.instance.send({'type': 'button_press', 'button': widget.button});
    HapticFeedback.lightImpact();
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    WebSocketService.instance.send({'type': 'button_release', 'button': widget.button});
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      onPanDown: (_) => _down(),
      onPanEnd: (_) => _up(),
      onPanCancel: _up,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.height / 2),
          color: _pressed ? const Color(0xFF00D4FF) : const Color(0xFF252538),
          border: Border.all(
            color: _pressed ? const Color(0xFF00D4FF) : const Color(0xFF4A4A6A),
            width: 1.5,
          ),
          boxShadow: _pressed
              ? [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.45), blurRadius: 10)]
              : [],
        ),
        child: Center(
          child: Text(
            widget.label,
            style: TextStyle(
              color: _pressed ? Colors.black : Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// D-Pad — cross shape with 8-directional support via diagonal detection
class DPad extends StatefulWidget {
  const DPad({super.key, this.size = 108.0});
  final double size;

  @override
  State<DPad> createState() => _DPadState();
}

class _DPadState extends State<DPad> {
  final Set<String> _active = {};

  void _press(String btn) {
    if (_active.contains(btn)) return;
    _active.add(btn);
    WebSocketService.instance.send({'type': 'button_press', 'button': btn});
    HapticFeedback.lightImpact();
  }

  void _release(String btn) {
    if (!_active.remove(btn)) return;
    WebSocketService.instance.send({'type': 'button_release', 'button': btn});
  }

  void _releaseAll() {
    for (final b in List.of(_active)) {
      _release(b);
    }
  }

  String? _hitZone(Offset local) {
    final arm = widget.size / 3;
    final cx = widget.size / 2, cy = widget.size / 2;
    final dx = local.dx - cx, dy = local.dy - cy;
    final adx = dx.abs(), ady = dy.abs();

    if (adx < arm / 2 && ady < arm / 2) return null; // center

    if (adx > ady * 1.8) return dx > 0 ? 'DPAD_RIGHT' : 'DPAD_LEFT';
    if (ady > adx * 1.8) return dy > 0 ? 'DPAD_DOWN' : 'DPAD_UP';

    // diagonal — press both
    return null;
  }

  List<String> _hitZones(Offset local) {
    final arm = widget.size / 3;
    final cx = widget.size / 2, cy = widget.size / 2;
    final dx = local.dx - cx, dy = local.dy - cy;
    final adx = dx.abs(), ady = dy.abs();

    if (adx < arm * 0.3 && ady < arm * 0.3) return [];
    if (adx > ady * 1.5 && ady < arm) return [dx > 0 ? 'DPAD_RIGHT' : 'DPAD_LEFT'];
    if (ady > adx * 1.5 && adx < arm) return [dy > 0 ? 'DPAD_DOWN' : 'DPAD_UP'];

    // diagonal
    return [
      dx > 0 ? 'DPAD_RIGHT' : 'DPAD_LEFT',
      dy > 0 ? 'DPAD_DOWN' : 'DPAD_UP',
    ];
  }

  void _handlePan(Offset local) {
    final wanted = _hitZones(local).toSet();
    final current = Set.of(_active);
    for (final b in current.difference(wanted)) _release(b);
    for (final b in wanted.difference(current)) _press(b);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final arm = s / 3;
    return GestureDetector(
      onPanDown: (d) => _handlePan(d.localPosition),
      onPanUpdate: (d) => _handlePan(d.localPosition),
      onPanEnd: (_) => _releaseAll(),
      onPanCancel: _releaseAll,
      child: SizedBox(
        width: s,
        height: s,
        child: CustomPaint(
          painter: _DPadPainter(active: Set.of(_active), arm: arm),
        ),
      ),
    );
  }
}

class _DPadPainter extends CustomPainter {
  const _DPadPainter({required this.active, required this.arm});
  final Set<String> active;
  final double arm;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF4A4A6A);

    void drawArm(Rect r, String btn) {
      fill.color = active.contains(btn)
          ? const Color(0xFF4A4AFF).withOpacity(0.85)
          : const Color(0xFF252538);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), fill);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), stroke);
    }

    // Up
    drawArm(Rect.fromLTWH(cx - arm / 2, cy - arm * 1.5, arm, arm), 'DPAD_UP');
    // Down
    drawArm(Rect.fromLTWH(cx - arm / 2, cy + arm / 2, arm, arm), 'DPAD_DOWN');
    // Left
    drawArm(Rect.fromLTWH(cx - arm * 1.5, cy - arm / 2, arm, arm), 'DPAD_LEFT');
    // Right
    drawArm(Rect.fromLTWH(cx + arm / 2, cy - arm / 2, arm, arm), 'DPAD_RIGHT');
    // Center cap
    fill.color = const Color(0xFF1A1A2A);
    canvas.drawCircle(Offset(cx, cy), arm * 0.38, fill);

    // Arrow icons
    _drawArrow(canvas, Offset(cx, cy - arm), 0, active.contains('DPAD_UP'));
    _drawArrow(canvas, Offset(cx, cy + arm), pi, active.contains('DPAD_DOWN'));
    _drawArrow(canvas, Offset(cx - arm, cy), -pi / 2, active.contains('DPAD_LEFT'));
    _drawArrow(canvas, Offset(cx + arm, cy), pi / 2, active.contains('DPAD_RIGHT'));
  }

  void _drawArrow(Canvas canvas, Offset center, double rotation, bool active) {
    final paint = Paint()
      ..color = active ? Colors.white : Colors.white30
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, -arm * 0.22)
      ..lineTo(arm * 0.18, arm * 0.12)
      ..lineTo(-arm * 0.18, arm * 0.12)
      ..close();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DPadPainter old) => old.active != active;
}

// Needed for rotation math
const pi = 3.14159265358979;

/// Small center buttons (View/Back, Menu/Start)
class CenterButton extends StatefulWidget {
  const CenterButton({
    super.key,
    required this.button,
    this.icon,
    this.label,
    this.size = 34.0,
  });
  final String button;
  final IconData? icon;
  final String? label;
  final double size;

  @override
  State<CenterButton> createState() => _CenterButtonState();
}

class _CenterButtonState extends State<CenterButton> {
  bool _pressed = false;

  void _down() {
    if (_pressed) return;
    setState(() => _pressed = true);
    WebSocketService.instance.send({'type': 'button_press', 'button': widget.button});
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    WebSocketService.instance.send({'type': 'button_release', 'button': widget.button});
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _pressed ? const Color(0xFF3A3A58) : const Color(0xFF1E1E30),
          border: Border.all(
            color: _pressed ? const Color(0xFF8888BB) : const Color(0xFF3A3A55),
            width: 1.5,
          ),
        ),
        child: Center(
          child: widget.icon != null
              ? Icon(widget.icon, color: Colors.white60, size: widget.size * 0.44)
              : Text(
                  widget.label ?? '',
                  style: TextStyle(color: Colors.white60, fontSize: widget.size * 0.32),
                ),
        ),
      ),
    );
  }
}

/// Xbox guide / home button
class GuideButton extends StatefulWidget {
  const GuideButton({super.key, this.size = 44.0});
  final double size;

  @override
  State<GuideButton> createState() => _GuideButtonState();
}

class _GuideButtonState extends State<GuideButton> {
  bool _pressed = false;

  void _down() {
    if (_pressed) return;
    setState(() => _pressed = true);
    WebSocketService.instance.send({'type': 'button_press', 'button': 'GUIDE'});
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    WebSocketService.instance.send({'type': 'button_release', 'button': 'GUIDE'});
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: _pressed
                ? [const Color(0xFFFFFFFF), const Color(0xFF8888CC)]
                : [const Color(0xFF6A6A9A), const Color(0xFF2A2A40)],
          ),
          boxShadow: _pressed
              ? [BoxShadow(color: Colors.white.withOpacity(0.5), blurRadius: 16)]
              : [],
        ),
        child: Center(
          child: Icon(
            Icons.sports_esports,
            color: _pressed ? const Color(0xFF1A1A30) : const Color(0xFFCCCCFF),
            size: widget.size * 0.50,
          ),
        ),
      ),
    );
  }
}
