import 'dart:math';
import 'package:flutter/material.dart';
import '../services/websocket_service.dart';

class AnalogStick extends StatefulWidget {
  const AnalogStick({
    super.key,
    required this.side,
    required this.button,
    this.size = 130.0,
    this.mouseMode = false,
    this.mouseSensitivity = 18.0,
    this.sensitivity = 1.0,
    this.deadZone = 0.08,
  });

  final String side;
  final String button;
  final double size;
  final bool mouseMode;
  final double mouseSensitivity;
  final double sensitivity;
  final double deadZone;

  @override
  State<AnalogStick> createState() => _AnalogStickState();
}

class _AnalogStickState extends State<AnalogStick> {
  Offset _norm = Offset.zero; // -1..1

  String get _stickMsg => widget.side == 'left' ? 'left_stick' : 'right_stick';

  void _update(Offset localPos) {
    final r = widget.size / 2;
    final center = Offset(r, r);
    var delta = localPos - center;
    if (delta.distance > r) delta = delta / delta.distance * r;

    final nx = delta.dx / r;
    final ny = -delta.dy / r;
    final mag = sqrt(nx * nx + ny * ny);
    final x = mag < widget.deadZone ? 0.0 : (nx * widget.sensitivity).clamp(-1.0, 1.0);
    final y = mag < widget.deadZone ? 0.0 : (ny * widget.sensitivity).clamp(-1.0, 1.0);

    setState(() => _norm = Offset(delta.dx / r, delta.dy / r));

    if (widget.mouseMode) {
      final speed = widget.mouseSensitivity;
      WebSocketService.instance.send({
        'type': 'mouse_move',
        'dx': (x * speed).round(),
        'dy': (-y * speed).round(),
      });
    } else {
      WebSocketService.instance.send({
        'type': _stickMsg,
        'x': double.parse(x.toStringAsFixed(3)),
        'y': double.parse(y.toStringAsFixed(3)),
      });
    }
  }

  void _reset() {
    setState(() => _norm = Offset.zero);
    if (!widget.mouseMode) {
      WebSocketService.instance.send({'type': _stickMsg, 'x': 0.0, 'y': 0.0});
    }
  }

  void _onTap() {
    WebSocketService.instance.send({'type': 'button_press', 'button': widget.button});
    Future.delayed(const Duration(milliseconds: 80), () {
      WebSocketService.instance.send({'type': 'button_release', 'button': widget.button});
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final r = size / 2;
    return GestureDetector(
      onTap: _onTap,
      onPanUpdate: (d) => _update(d.localPosition),
      onPanEnd: (_) => _reset(),
      onPanCancel: _reset,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _StickPainter(
            norm: _norm,
            thumbR: size * 0.22,
            outerR: r,
            mouseMode: widget.mouseMode,
          ),
        ),
      ),
    );
  }
}

class _StickPainter extends CustomPainter {
  const _StickPainter({
    required this.norm,
    required this.thumbR,
    required this.outerR,
    required this.mouseMode,
  });

  final Offset norm;
  final double thumbR;
  final double outerR;
  final bool mouseMode;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final accentColor = mouseMode ? const Color(0xFFFF6B35) : const Color(0xFF00D4FF);

    // Outer base
    canvas.drawCircle(center, outerR, Paint()..color = const Color(0xFF252535));
    canvas.drawCircle(center, outerR,
        Paint()
          ..color = accentColor.withOpacity(0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    // Glow on displacement
    final mag = norm.distance;
    if (mag > 0.05) {
      canvas.drawCircle(center, outerR - 1,
          Paint()..color = accentColor.withOpacity(mag * 0.12));
    }

    // Thumb
    final pos = center + Offset(norm.dx * outerR, norm.dy * outerR);
    canvas.drawCircle(pos, thumbR,
        Paint()
          ..shader = RadialGradient(colors: [
            const Color(0xFF5A5A7A),
            const Color(0xFF2E2E45),
          ]).createShader(Rect.fromCircle(center: pos, radius: thumbR)));
    canvas.drawCircle(pos, thumbR,
        Paint()
          ..color = mag > 0.05 ? accentColor.withOpacity(0.8) : const Color(0xFF4A4A6A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    // Mouse mode icon
    if (mouseMode) {
      final tp = TextPainter(
        text: const TextSpan(text: '🖱', style: TextStyle(fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_StickPainter old) => old.norm != norm || old.mouseMode != mouseMode;
}
