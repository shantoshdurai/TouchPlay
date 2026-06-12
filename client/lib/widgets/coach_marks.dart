import 'dart:ui';
import 'package:flutter/material.dart';

class CoachMarksOverlay extends StatefulWidget {
  final VoidCallback onDismiss;

  const CoachMarksOverlay({super.key, required this.onDismiss});

  @override
  State<CoachMarksOverlay> createState() => _CoachMarksOverlayState();
}

class _CoachMarksOverlayState extends State<CoachMarksOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _pulse = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.0, 0.5, curve: Curves.easeInOut)),
    );

    _slide = Tween<double>(begin: -26.0, end: 26.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.0, 0.5, curve: Curves.easeInOut)),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _legendRow(String label, List<String> buttons, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 11,
                  fontWeight: FontWeight.w300)),
          const SizedBox(width: 8),
          for (final b in buttons) ...[
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              margin: EdgeInsets.only(left: buttons.indexOf(b) == 0 ? 0 : 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: highlight
                      ? const Color(0xE66FB6FF)
                      : const Color(0x73FFFFFF),
                  width: 1,
                ),
                boxShadow: highlight
                    ? [
                        const BoxShadow(
                            color: Color(0x666FB6FF),
                            blurRadius: 10,
                            spreadRadius: 0)
                      ]
                    : null,
              ),
              child: Text(b,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      height: 1.0)),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 500),
        builder: (context, opacity, child) {
          return Opacity(
            opacity: opacity,
            child: child,
          );
        },
        child: Stack(
          children: [
            // Backdrop
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0),
                  child: Container(
                    color: const Color(0xA8020408),
                  ),
                ),
              ),
            ),
            
            // Left Joystick demo
            Positioned(
              left: 44,
              top: MediaQuery.of(context).size.height * 0.4,
              child: SizedBox(
                width: 128,
                height: 128,
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) {
                    final p = _pulse.value > 1.0 ? 2.0 - _pulse.value : _pulse.value;
                    final s = _slide.value > 26.0 ? 52.0 - _slide.value : _slide.value;
                    
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Outer pulse ring
                        Positioned.fill(
                          child: Opacity(
                            opacity: p,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: const Color(0x80FFFFFF), width: 1.5),
                              ),
                            ),
                          ),
                        ),
                        // Inner ring
                        Positioned.fill(
                          left: 19,
                          top: 19,
                          right: 19,
                          bottom: 19,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0x66FFFFFF), width: 1.5),
                            ),
                          ),
                        ),
                        // Thumb moving left/right
                        Positioned(
                          left: 40 + s,
                          top: 40,
                          width: 48,
                          height: 48,
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFC8CDD5),
                            ),
                          ),
                        ),
                        // Hint text
                        Positioned(
                          left: -26,
                          top: 142,
                          width: 180,
                          child: const Text(
                            'Slide anywhere on the left side to browse apps',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xD9E9EDF4),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w300,
                              height: 1.55,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            // Right face cluster ring
            Positioned(
              right: 4,
              bottom: 4,
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final p = _pulse.value > 1.0 ? 2.0 - _pulse.value : _pulse.value;
                  return Opacity(
                    opacity: p,
                    child: Container(
                      width: 128,
                      height: 128,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0x8C6FB6FF), width: 1.5),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x4D6FB6FF),
                              blurRadius: 24,
                              spreadRadius: 0),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Right face cluster legend
            Positioned(
              right: 24,
              bottom: 158,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _legendRow('Settings', ['Y']),
                  _legendRow('Browse', ['X', 'B']),
                  _legendRow('Launch', ['A'], highlight: true),
                ],
              ),
            ),

            // Dismiss button
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: Center(
                child: GestureDetector(
                  onTap: widget.onDismiss,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 28, vertical: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9EDF4),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x40FFFFFF),
                            blurRadius: 22,
                            spreadRadius: 0)
                      ],
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(
                          color: Color(0xFF10141B),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
