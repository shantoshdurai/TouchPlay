import 'package:flutter/material.dart';
import '../services/websocket_service.dart';
import '../services/haptics.dart';

const _neutralColor = Color(0x1AFFFFFF);

/// Circular trigger button (LT / RT) — styled like ActionButton
class TriggerBar extends StatefulWidget {
  const TriggerBar({
    super.key,
    required this.side,
    required this.label,
    this.width = 50.0,
    this.height = 50.0,
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
  late AnimationController _scale;

  String get _msg => widget.side == 'left' ? 'left_trigger' : 'right_trigger';

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
    WebSocketService.instance.send({'type': _msg, 'value': 1.0});
    Haptics.instance.heavy();
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    _scale.forward();
    WebSocketService.instance.send({'type': _msg, 'value': 0.0});
    Haptics.instance.tick();
  }

  @override
  Widget build(BuildContext context) {
    // We use `width` for the size of the circle to maintain signature compatibility
    // if parent uses width/height for layout. We'll constrain it to be circular.
    final size = widget.width < widget.height ? widget.width : widget.height;

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
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _pressed ? Colors.white24 : const Color(0x22000000),
            border: Border.all(
              color: _pressed ? Colors.white : _neutralColor,
              width: 0.5,
            ),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w400,
                fontSize: size * 0.35,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
