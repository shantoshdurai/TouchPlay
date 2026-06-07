import 'package:flutter/material.dart';
import '../services/websocket_service.dart';
import '../services/haptics.dart';

const _neutralColor = Color(0x1AFFFFFF); // Extremely subtle border

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
    Haptics.instance.heavy();
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    _scale.forward();
    WebSocketService.instance.send({'type': 'button_release', 'button': widget.button});
    Haptics.instance.tick();
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
            color: _pressed ? Colors.white24 : const Color(0x22000000),
            border: Border.all(
              color: _pressed ? Colors.white : _neutralColor,
              width: 0.5,
            ),
          ),
          child: Center(
            child: widget.icon != null
                ? Icon(widget.icon,
                    color: Colors.white,
                    size: widget.size * 0.42)
                : Text(
                    widget.label ?? widget.button,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: widget.size * 0.35,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Bumper button (LB / RB) — styled same as ActionButton now (circle)
class BumperButton extends StatelessWidget {
  const BumperButton({
    super.key,
    required this.button,
    required this.label,
    this.width = 50.0,
  });

  final String button;
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return ActionButton(
      button: button,
      label: label,
      size: width,
    );
  }
}

/// D-Pad — 4 distinct circular buttons (matching reference image)
class DPad extends StatelessWidget {
  const DPad({super.key, this.size = 140.0});
  final double size;

  @override
  Widget build(BuildContext context) {
    final btnSize = size * 0.35;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 0,
            child: _DPadBtn(button: 'DPAD_UP', icon: Icons.keyboard_arrow_up, size: btnSize),
          ),
          Positioned(
            bottom: 0,
            child: _DPadBtn(button: 'DPAD_DOWN', icon: Icons.keyboard_arrow_down, size: btnSize),
          ),
          Positioned(
            left: 0,
            child: _DPadBtn(button: 'DPAD_LEFT', icon: Icons.keyboard_arrow_left, size: btnSize),
          ),
          Positioned(
            right: 0,
            child: _DPadBtn(button: 'DPAD_RIGHT', icon: Icons.keyboard_arrow_right, size: btnSize),
          ),
        ],
      ),
    );
  }
}

class _DPadBtn extends StatefulWidget {
  const _DPadBtn({required this.button, required this.icon, required this.size});
  final String button;
  final IconData icon;
  final double size;

  @override
  State<_DPadBtn> createState() => _DPadBtnState();
}

class _DPadBtnState extends State<_DPadBtn> with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late AnimationController _scale;

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
    Haptics.instance.heavy();
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    _scale.forward();
    WebSocketService.instance.send({'type': 'button_release', 'button': widget.button});
    Haptics.instance.tick();
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
            color: _pressed ? Colors.white24 : const Color(0x22000000),
            border: Border.all(
              color: _pressed ? Colors.white : _neutralColor,
              width: 0.5,
            ),
          ),
          child: Center(
            child: Icon(widget.icon, color: Colors.white70, size: widget.size * 0.55),
          ),
        ),
      ),
    );
  }
}

/// Small center buttons (View/Back, Menu/Start) - pill shaped
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
    Haptics.instance.light();
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    WebSocketService.instance.send({'type': 'button_release', 'button': widget.button});
    Haptics.instance.tick();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: widget.size * 2,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.size / 2),
          color: _pressed ? Colors.white24 : const Color(0x22000000),
          border: Border.all(
            color: _pressed ? Colors.white : _neutralColor,
            width: 0.5,
          ),
        ),
        child: Center(
          child: widget.icon != null
              ? Icon(widget.icon, color: Colors.white70, size: widget.size * 0.5)
              : Text(
                  widget.label ?? '',
                  style: TextStyle(color: Colors.white70, fontSize: widget.size * 0.35),
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
    Haptics.instance.medium();
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    WebSocketService.instance.send({'type': 'button_release', 'button': 'GUIDE'});
    Haptics.instance.tick();
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
          color: _pressed ? Colors.white24 : const Color(0x22000000),
          border: Border.all(
            color: _pressed ? Colors.white : _neutralColor,
            width: 0.5,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.games, // generic gamepad icon
            color: Colors.white70,
            size: widget.size * 0.40,
          ),
        ),
      ),
    );
  }
}
