import 'dart:math';
import 'package:flutter/material.dart';
import '../services/websocket_service.dart';

const _neutralColor = Color(0x66FFFFFF);

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

  void _update(DragUpdateDetails d) {
    final r = widget.size / 2;
    final center = Offset(r, r);
    var delta = d.localPosition - center;
    if (delta.distance > r) delta = delta / delta.distance * r;

    final nx = delta.dx / r;
    final ny = -delta.dy / r;
    final mag = sqrt(nx * nx + ny * ny);
    final x = mag < widget.deadZone ? 0.0 : (nx * widget.sensitivity).clamp(-1.0, 1.0);
    final y = mag < widget.deadZone ? 0.0 : (ny * widget.sensitivity).clamp(-1.0, 1.0);

    setState(() => _norm = Offset(delta.dx / r, delta.dy / r));

    if (widget.mouseMode) {
      final speed = widget.mouseSensitivity / 10.0;
      WebSocketService.instance.send({
        'type': 'mouse_move',
        'dx': (d.delta.dx * speed).round(),
        'dy': (d.delta.dy * speed).round(),
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
      onPanUpdate: (d) => _update(d),
      onPanEnd: (_) => _reset(),
      onPanCancel: _reset,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _StickPainter(
            norm: _norm,
            thumbR: size * 0.28,
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

    // Outer base rings
    final outerRingPaint = Paint()
      ..color = _neutralColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, outerR, outerRingPaint);
    canvas.drawCircle(center, outerR * 0.7, outerRingPaint);

    // Thumb position
    final pos = center + Offset(norm.dx * outerR, norm.dy * outerR);
    
    // Draw solid light gray thumb circle
    canvas.drawCircle(pos, thumbR,
        Paint()
          ..color = const Color(0xFFC0C0C0)
          ..style = PaintingStyle.fill);

    // Draw grid of dots on the thumb
    final dotPaint = Paint()
      ..color = const Color(0xFF888888)
      ..style = PaintingStyle.fill;
    
    final int rows = 5;
    final int cols = 5;
    final double spacing = thumbR * 0.25;
    final double startX = pos.dx - ((cols - 1) * spacing / 2);
    final double startY = pos.dy - ((rows - 1) * spacing / 2);

    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        // Only draw dots that fit inside a smaller inner radius
        double dx = startX + j * spacing - pos.dx;
        double dy = startY + i * spacing - pos.dy;
        if (dx * dx + dy * dy < (thumbR * 0.6) * (thumbR * 0.6)) {
           canvas.drawCircle(Offset(startX + j * spacing, startY + i * spacing), 1.5, dotPaint);
        }
      }
    }

    // Mouse mode icon
    if (mouseMode) {
      final tp = TextPainter(
        text: const TextSpan(text: '🖱', style: TextStyle(fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_StickPainter old) => old.norm != norm || old.mouseMode != mouseMode;
}
