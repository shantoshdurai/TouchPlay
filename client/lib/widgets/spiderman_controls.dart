import 'package:flutter/material.dart';
import '../services/websocket_service.dart';
import '../services/haptics.dart';

const _kRed  = Color(0xFFE5484D);
const _kRest = Color(0x66FFFFFF);

/// SWING â€” the hero control for Spider-Man 2.
///
/// Touch + hold  â†’ RT pressed (web-swing fires).
/// Drag while held â†’ right-stick X/Y (look around while swinging).
/// Release        â†’ RT off, right-stick zeroed.
///
/// The floating right-stick region is still active everywhere OUTSIDE
/// this button, so free camera works normally when not swinging.
class SwingButton extends StatefulWidget {
  const SwingButton({super.key, required this.size});
  final double size;

  @override
  State<SwingButton> createState() => _SwingButtonState();
}

class _SwingButtonState extends State<SwingButton> {
  int?   _ptr;
  Offset _origin = Offset.zero;
  double _nx = 0, _ny = 0;

  bool   get _held => _ptr != null;
  double get _r    => widget.size / 2;

  void _down(PointerDownEvent e) {
    if (_ptr != null) return;
    _ptr    = e.pointer;
    _origin = e.localPosition;
    setState(() { _nx = 0; _ny = 0; });
    WebSocketService.instance.send({'type': 'right_trigger', 'value': 1.0});
    Haptics.instance.heavy();
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _ptr) return;
    final delta  = e.localPosition - _origin;
    final travel = _r * 1.5;
    final rawX   = (delta.dx  / travel).clamp(-1.0, 1.0);
    final rawY   = (-delta.dy / travel).clamp(-1.0, 1.0); // drag up = look up

    final s   = WebSocketService.instance.sensitivity;
    final mag = (delta / travel).distance.clamp(0.0, 1.5);
    final x   = mag < s.deadZone ? 0.0 : (rawX * s.rightStickSensitivity).clamp(-1.0, 1.0);
    final y   = mag < s.deadZone ? 0.0 : (rawY * s.rightStickSensitivity).clamp(-1.0, 1.0);

    setState(() { _nx = rawX; _ny = rawY; });
    WebSocketService.instance.send({
      'type': 'right_stick',
      'x': double.parse(x.toStringAsFixed(3)),
      'y': double.parse(y.toStringAsFixed(3)),
    });
  }

  void _up(PointerEvent e) {
    if (e.pointer != _ptr) return;
    _ptr = null;
    setState(() { _nx = 0; _ny = 0; });
    WebSocketService.instance.send({'type': 'right_trigger', 'value': 0.0});
    WebSocketService.instance.send({'type': 'right_stick',   'x': 0.0, 'y': 0.0});
    Haptics.instance.medium();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown:   _down,
      onPointerMove:   _move,
      onPointerUp:     _up,
      onPointerCancel: _up,
      child: SizedBox(
        width: widget.size, height: widget.size,
        child: CustomPaint(
          painter: _SwingPaint(held: _held, nx: _nx, ny: _ny, r: _r),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                _held ? Icons.open_with : Icons.wifi_tethering,
                color: Colors.white,
                size: _r * 0.46,
              ),
              SizedBox(height: _r * 0.05),
              Text(
                _held ? 'SWINGING' : 'SWING',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _r * 0.21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              SizedBox(height: _r * 0.04),
              Text(
                _held ? 'DRAG TO LOOK' : 'HOLD + DRAG',
                style: TextStyle(
                  color: _held ? _kRed.withValues(alpha: 0.85) : Colors.white38,
                  fontSize: _r * 0.13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SwingPaint extends CustomPainter {
  const _SwingPaint({
    required this.held,
    required this.nx,
    required this.ny,
    required this.r,
  });
  final bool   held;
  final double nx, ny, r;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);

    if (held) {
      canvas.drawCircle(c, r - 2, Paint()..color = const Color(0x22E5484D));
      canvas.drawCircle(c, r - 2, Paint()
        ..color      = _kRed.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    }

    canvas.drawCircle(c, r - 2, Paint()
      ..color       = held ? _kRed : _kRest
      ..style       = PaintingStyle.stroke
      ..strokeWidth = held ? 2.5 : 1.5);

    // Direction arrow â€” shows where the camera is being pushed
    final drag = Offset(nx, -ny);
    if (held && drag.distance > 0.10) {
      final dir  = drag / drag.distance;
      final tip  = c + dir * (r * 0.62);
      final perp = Offset(-dir.dy, dir.dx);
      canvas.drawLine(c, tip, Paint()
        ..color       = _kRed.withValues(alpha: 0.85)
        ..strokeWidth = 2.5
        ..strokeCap   = StrokeCap.round
        ..style       = PaintingStyle.stroke);
      final head = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo((tip - dir * 11 + perp * 5.5).dx, (tip - dir * 11 + perp * 5.5).dy)
        ..lineTo((tip - dir * 11 - perp * 5.5).dx, (tip - dir * 11 - perp * 5.5).dy)
        ..close();
      canvas.drawPath(head, Paint()
        ..color = _kRed.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(_SwingPaint o) =>
      o.held != held || o.nx != nx || o.ny != ny || o.r != r;
}
