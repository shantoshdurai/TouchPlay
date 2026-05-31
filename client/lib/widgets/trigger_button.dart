import 'package:flutter/material.dart';
import '../services/websocket_service.dart';

/// Wide horizontal trigger bar (LT / RT) — spans the top edge of each side.
class TriggerBar extends StatefulWidget {
  const TriggerBar({
    super.key,
    required this.side,
    required this.label,
    this.width = 140.0,
    this.height = 44.0,
  });

  final String side;
  final String label;
  final double width;
  final double height;

  @override
  State<TriggerBar> createState() => _TriggerBarState();
}

class _TriggerBarState extends State<TriggerBar>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late AnimationController _anim;
  late Animation<double> _fill;

  String get _msg => widget.side == 'left' ? 'left_trigger' : 'right_trigger';

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 80));
    _fill = Tween<double>(begin: 0, end: 1).animate(_anim);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _down() {
    if (_pressed) return;
    setState(() => _pressed = true);
    _anim.forward();
    WebSocketService.instance.send({'type': _msg, 'value': 1.0});
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    _anim.reverse();
    WebSocketService.instance.send({'type': _msg, 'value': 0.0});
  }

  @override
  Widget build(BuildContext context) {
    final isLeft = widget.side == 'left';
    final radius = BorderRadius.only(
      bottomLeft: Radius.circular(isLeft ? 0 : 12),
      bottomRight: Radius.circular(isLeft ? 12 : 0),
      topLeft: Radius.circular(isLeft ? 8 : 0),
      topRight: Radius.circular(isLeft ? 0 : 8),
    );

    return GestureDetector(
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      onPanDown: (_) => _down(),
      onPanEnd: (_) => _up(),
      onPanCancel: _up,
      child: AnimatedBuilder(
        animation: _fill,
        builder: (_, __) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(const Color(0xFF1E1E30), const Color(0xFF00D4FF), _fill.value)!,
                const Color(0xFF141420),
              ],
            ),
            border: Border.all(
              color: _fill.value > 0.1
                  ? const Color(0xFF00D4FF).withOpacity(0.8)
                  : const Color(0xFF3A3A50),
              width: 1.5,
            ),
            boxShadow: _pressed
                ? [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.4), blurRadius: 12)]
                : [],
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: _pressed ? Colors.black : Colors.white54,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
