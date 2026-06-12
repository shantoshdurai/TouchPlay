import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/haptics.dart';
import '../services/websocket_service.dart' as ws;
import '../widgets/ambience.dart';
import '../widgets/floating_keyboard.dart';

const _accent = Color(0xFF6FB6FF);

/// Dedicated trackpad + keyboard screen ("Mouse & Keys").
///
/// Unlike the gamepad, this screen rotates freely — portrait is often the
/// comfortable one-hand grip for a trackpad. Gestures:
///   • 1 finger        move cursor   • tap        left click
///   • double-tap+hold drag          • 2-finger tap   right click
///   • 2-finger slide  scroll        • pinch      zoom (Ctrl+wheel)
/// Typing: the system keyboard (everything you type is piped to the PC,
/// including backspace and Enter) or the scalable floating mini-keyboard.
class MouseKeysScreen extends StatefulWidget {
  const MouseKeysScreen({super.key});

  @override
  State<MouseKeysScreen> createState() => _MouseKeysScreenState();
}

class _MouseKeysScreenState extends State<MouseKeysScreen>
    with WidgetsBindingObserver {
  late final StreamSubscription<ws.ConnectionState> _sub;
  ws.ConnectionState _conn = ws.WebSocketService.instance.state;

  bool _floatingKb = false;
  bool _touched = false; // hides the trackpad hint after first use

  // ── System-keyboard pipe ────────────────────────────────────────────────
  // A tiny invisible TextField. We seed it with zero-width spaces so that
  // backspace still produces a text change we can observe and forward.
  static const _seed =
      '\u200B\u200B\u200B\u200B\u200B\u200B\u200B\u200B';
  final _kbCtrl = TextEditingController(text: _seed);
  final _kbFocus = FocusNode();
  String _lastText = _seed;
  bool _mutingKb = false;
  // Live echo of what's being typed, shown in a chip above the keyboard
  // (the field itself is invisible, so without this you type blind).
  final _typedN = ValueNotifier<String>('');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // This screen may rotate — the rest of the app stays landscape.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _sub = ws.WebSocketService.instance.stateStream.listen((s) {
      if (mounted) setState(() => _conn = s);
    });
    _kbFocus.addListener(() {
      if (!_kbFocus.hasFocus) _typedN.value = '';
      if (mounted) setState(() {});
    });
  }

  // The user can dismiss the keyboard with the system back/down button — we
  // only learn of it through the inset metrics. Without this the field keeps
  // focus and the "Typing to PC…" button stays stuck active.
  @override
  void didChangeMetrics() {
    final insets =
        WidgetsBinding.instance.platformDispatcher.views.first.viewInsets;
    if (insets.bottom == 0 && _kbFocus.hasFocus) {
      _kbFocus.unfocus();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub.cancel();
    _kbCtrl.dispose();
    _kbFocus.dispose();
    _typedN.dispose();
    // Orientation is owned by main.dart's push(): the home menu rotates
    // freely, landscape-only screens lock it on entry.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    super.dispose();
  }

  void _send(Map<String, dynamic> msg) => ws.WebSocketService.instance.send(msg);

  void _tapKey(String key) {
    _send({'type': 'key_down', 'key': key});
    Future.delayed(const Duration(milliseconds: 40),
        () => _send({'type': 'key_up', 'key': key}));
  }

  void _onKbChanged(String v) {
    if (_mutingKb) return;
    var p = 0;
    while (p < v.length && p < _lastText.length && v[p] == _lastText[p]) {
      p++;
    }
    final removed = _lastText.length - p;
    final added = v.substring(p);
    var typed = _typedN.value;
    for (var i = 0; i < removed; i++) {
      _tapKey('BACKSPACE');
      if (typed.isNotEmpty) typed = typed.substring(0, typed.length - 1);
    }
    if (added.isNotEmpty) {
      final parts = added.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) {
          _send({'type': 'keyboard_string', 'text': parts[i]});
          typed += parts[i];
        }
        if (i < parts.length - 1) {
          _tapKey('ENTER');
          typed = ''; // line committed on the PC — start the echo fresh
        }
      }
    }
    _typedN.value = typed;
    if (v.length < _seed.length) {
      // Deleted into the seed — top it back up so backspace keeps working.
      _mutingKb = true;
      _kbCtrl.value = const TextEditingValue(
        text: _seed,
        selection: TextSelection.collapsed(offset: _seed.length),
      );
      _mutingKb = false;
      _lastText = _seed;
    } else {
      _lastText = v;
    }
  }

  void _toggleSystemKb() {
    Haptics.instance.tick();
    if (_kbFocus.hasFocus) {
      _kbFocus.unfocus();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      _kbFocus.requestFocus();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _showSensitivity() {
    Haptics.instance.tick();
    final s = ws.WebSocketService.instance.sensitivity;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF12121E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pointer speed',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              Row(children: [
                const Icon(Icons.mouse, color: Colors.white24, size: 16),
                Expanded(
                  child: Slider(
                    value: s.mouseSensitivity.clamp(4.0, 40.0),
                    min: 4,
                    max: 40,
                    activeColor: _accent,
                    inactiveColor: Colors.white12,
                    onChanged: (v) {
                      setSheet(() => s.mouseSensitivity = v);
                      ws.WebSocketService.instance.saveSensitivity();
                    },
                  ),
                ),
                Text(s.mouseSensitivity.toStringAsFixed(0),
                    style: const TextStyle(color: _accent, fontSize: 12)),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: AmbientBackground(
        child: SafeArea(
        child: Stack(
          children: [
            OrientationBuilder(
              builder: (context, orientation) =>
                  orientation == Orientation.portrait
                      ? _portrait()
                      : _landscape(),
            ),
            // Invisible 1×1 field that catches system-keyboard input.
            Positioned(
              left: 0,
              bottom: 0,
              width: 1,
              height: 1,
              child: Opacity(
                opacity: 0.01,
                child: TextField(
                  controller: _kbCtrl,
                  focusNode: _kbFocus,
                  onChanged: _onKbChanged,
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  autocorrect: false,
                  // Suggestions ON: with them off Gboard treats the field as
                  // incognito and disables voice (mic) input entirely.
                  enableSuggestions: true,
                  style: const TextStyle(fontSize: 1),
                  decoration: const InputDecoration(border: InputBorder.none),
                ),
              ),
            ),
            // Live echo of what's being typed — floats just above the system
            // keyboard so you're never typing blind into the invisible field.
            if (_kbFocus.hasFocus)
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                child: IgnorePointer(
                  child: Center(
                    child: ValueListenableBuilder<String>(
                      valueListenable: _typedN,
                      builder: (_, t, __) {
                        final show =
                            t.length > 60 ? t.substring(t.length - 60) : t;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 9),
                          decoration: BoxDecoration(
                            color: const Color(0xE60B0E15),
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Border.all(color: const Color(0x556FB6FF)),
                            boxShadow: [
                              BoxShadow(
                                  color:
                                      Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3)),
                            ],
                          ),
                          child: Text(
                            show.isEmpty
                                ? 'Typing to PC — your text shows here'
                                : '$show▏',
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: TextStyle(
                              color: show.isEmpty
                                  ? Colors.white38
                                  : Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            if (_floatingKb)
              FloatingKeyboard(
                  onClose: () => setState(() => _floatingKb = false)),
          ],
        ),
        ),
      ),
    );
  }

  // ── Layouts ───────────────────────────────────────────────────────────────

  Widget _portrait() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
        child: Column(
          children: [
            _topBar(),
            const SizedBox(height: 10),
            Expanded(
              child: Row(children: [
                Expanded(child: _trackpad()),
                const SizedBox(width: 10),
                _scrollStrip(),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(flex: 3, child: _clickBtn('left', 'LEFT')),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: _clickBtn('middle', 'MID')),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: _clickBtn('right', 'RIGHT')),
            ]),
            const SizedBox(height: 10),
            _kbRow(),
          ],
        ),
      );

  Widget _landscape() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
        child: Column(
          children: [
            _topBar(),
            const SizedBox(height: 10),
            Expanded(
              child: Row(children: [
                Expanded(child: _trackpad()),
                const SizedBox(width: 10),
                _scrollStrip(),
                const SizedBox(width: 10),
                SizedBox(
                  width: 130,
                  child: Column(children: [
                    Expanded(child: _clickBtn('left', 'LEFT')),
                    const SizedBox(height: 8),
                    SizedBox(height: 52, child: _clickBtn('middle', 'MID')),
                    const SizedBox(height: 8),
                    Expanded(child: _clickBtn('right', 'RIGHT')),
                    const SizedBox(height: 8),
                    _kbRow(compact: true),
                  ]),
                ),
              ]),
            ),
          ],
        ),
      );

  Widget _topBar() {
    final (dotColor, label) = switch (_conn) {
      ws.ConnectionState.connected => (const Color(0xFF3DDC84), 'Connected'),
      ws.ConnectionState.connecting => (const Color(0xFFFFCC4D), 'Connecting…'),
      _ => (const Color(0xFFFF6B6B), 'Searching for PC…'),
    };
    return Row(children: [
      IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: const Icon(Icons.arrow_back_ios_new,
            color: Colors.white70, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      const SizedBox(width: 10),
      const Text('Mouse & Keys',
          style: TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
      const Spacer(),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
        ]),
      ),
      const SizedBox(width: 6),
      IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: const Icon(Icons.tune, color: Colors.white54, size: 18),
        onPressed: _showSensitivity,
      ),
    ]);
  }

  Widget _trackpad() => Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          _TrackpadSurface(onFirstTouch: () {
            if (!_touched) setState(() => _touched = true);
          }),
          if (!_touched)
            IgnorePointer(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.touch_app_outlined,
                      color: Colors.white.withValues(alpha: 0.12), size: 38),
                  const SizedBox(height: 10),
                  Text(
                    'Slide to move · tap to click\n'
                    'Two fingers: scroll, pinch to zoom, tap = right-click\n'
                    'Double-tap & hold to drag',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.22),
                        fontSize: 10.5,
                        height: 1.6),
                  ),
                ]),
              ),
            ),
        ]),
      );

  Widget _scrollStrip() => _ScrollStrip(
        onScroll: (dy) => _send({'type': 'mouse_scroll', 'dx': 0, 'dy': dy}),
      );

  Widget _clickBtn(String button, String label) => _PressButton(
        label: label,
        onDown: () => _send({'type': 'mouse_down', 'button': button}),
        onUp: () => _send({'type': 'mouse_up', 'button': button}),
      );

  Widget _kbRow({bool compact = false}) {
    final active = _kbFocus.hasFocus;
    final sysBtn = GestureDetector(
      onTap: _toggleSystemKb,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? _accent.withValues(alpha: 0.15)
              : const Color(0xFFE9EDF4),
          borderRadius: BorderRadius.circular(23),
          border: active ? Border.all(color: _accent) : null,
          boxShadow: active
              ? null
              : [
                  BoxShadow(
                      color: Colors.white.withValues(alpha: 0.18),
                      blurRadius: 16,
                      spreadRadius: 1),
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3)),
                ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.keyboard,
              color: active ? _accent : const Color(0xFF10141B), size: 18),
          if (!compact) ...[
            const SizedBox(width: 8),
            Text(active ? 'Typing to PC…' : 'Keyboard',
                style: TextStyle(
                    color: active ? _accent : const Color(0xFF10141B),
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ]),
      ),
    );
    final miniBtn = GestureDetector(
      onTap: () {
        Haptics.instance.tick();
        setState(() => _floatingKb = !_floatingKb);
      },
      child: Container(
        height: 46,
        width: compact ? 46 : 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _floatingKb
              ? _accent.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(
              color: _floatingKb
                  ? _accent
                  : Colors.white.withValues(alpha: 0.12)),
        ),
        child: Icon(Icons.picture_in_picture_alt,
            color: _floatingKb ? _accent : Colors.white54, size: 18),
      ),
    );
    if (compact) {
      return Row(children: [
        Expanded(child: sysBtn),
        const SizedBox(width: 6),
        miniBtn,
      ]);
    }
    return Row(children: [
      Expanded(child: sysBtn),
      const SizedBox(width: 8),
      miniBtn,
    ]);
  }
}

// ── Trackpad gesture surface ─────────────────────────────────────────────────

class _TrackpadSurface extends StatefulWidget {
  const _TrackpadSurface({required this.onFirstTouch});
  final VoidCallback onFirstTouch;

  @override
  State<_TrackpadSurface> createState() => _TrackpadSurfaceState();
}

class _TrackpadSurfaceState extends State<_TrackpadSurface> {
  int? _id1, _id2;
  Offset? _pos1, _pos2;
  Offset? _downPos;
  DateTime? _downTime, _twoDownTime, _lastTapUp;
  double _scrollAcc = 0, _zoomAcc = 0;
  bool _gestureSent = false;
  bool _dragging = false; // double-tap-hold drag (left button held)

  static const _tapSlop = 12.0;

  void _send(Map<String, dynamic> msg) => ws.WebSocketService.instance.send(msg);

  @override
  void dispose() {
    // Stuck-input safety: never leave the PC's left button held down.
    if (_dragging) _send({'type': 'mouse_up', 'button': 'left'});
    super.dispose();
  }

  void _onDown(PointerDownEvent e) {
    widget.onFirstTouch();
    if (_id1 == null) {
      _id1 = e.pointer;
      _pos1 = e.localPosition;
      _downPos = e.localPosition;
      _downTime = DateTime.now();
      // Double-tap-and-hold → start a drag (button stays down while moving).
      if (_lastTapUp != null &&
          DateTime.now().difference(_lastTapUp!).inMilliseconds < 280) {
        _dragging = true;
        _send({'type': 'mouse_down', 'button': 'left'});
        Haptics.instance.tick();
      }
    } else if (_id2 == null) {
      _id2 = e.pointer;
      _pos2 = e.localPosition;
      _twoDownTime = DateTime.now();
      _scrollAcc = 0;
      _zoomAcc = 0;
      _gestureSent = false;
      _downPos = null; // two fingers — never a left click
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (_id2 != null) {
      _twoFingerMove(e);
      return;
    }
    if (e.pointer != _id1) return;
    _pos1 = e.localPosition;
    if (e.delta.distance < 0.5) return;
    final sens =
        ws.WebSocketService.instance.sensitivity.mouseSensitivity / 10.0;
    _send({
      'type': 'mouse_move',
      'dx': (e.delta.dx * sens).round(),
      'dy': (e.delta.dy * sens).round(),
    });
  }

  void _twoFingerMove(PointerMoveEvent e) {
    final old1 = _pos1, old2 = _pos2;
    if (e.pointer == _id1) {
      _pos1 = e.localPosition;
    } else if (e.pointer == _id2) {
      _pos2 = e.localPosition;
    } else {
      return;
    }
    if (old1 == null || old2 == null || _pos1 == null || _pos2 == null) return;

    _zoomAcc += (_pos1! - _pos2!).distance - (old1 - old2).distance;
    _scrollAcc += e.delta.dy / 2;

    if (_zoomAcc.abs() > 28) {
      _send({'type': 'mouse_zoom', 'delta': _zoomAcc > 0 ? 120 : -120});
      _zoomAcc = 0;
      _scrollAcc = 0;
      _gestureSent = true;
    } else if (_scrollAcc.abs() > 6) {
      _send({'type': 'mouse_scroll', 'dx': 0, 'dy': (_scrollAcc * 8).round()});
      _scrollAcc = 0;
      _gestureSent = true;
    }
  }

  void _endTwoFinger() {
    if (!_gestureSent &&
        _twoDownTime != null &&
        DateTime.now().difference(_twoDownTime!).inMilliseconds < 300) {
      _send({'type': 'mouse_click', 'button': 'right'});
      Haptics.instance.tick();
    }
    _id2 = null;
    _pos2 = null;
    _twoDownTime = null;
    _scrollAcc = 0;
    _zoomAcc = 0;
    _gestureSent = false;
  }

  void _endDrag() {
    if (_dragging) {
      _dragging = false;
      _send({'type': 'mouse_up', 'button': 'left'});
    }
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer == _id2) {
      _endTwoFinger();
      return;
    }
    if (e.pointer != _id1) return;
    if (_id2 != null) _endTwoFinger();
    if (_dragging) {
      _endDrag();
    } else if (_downPos != null && _downTime != null) {
      final dist = (e.localPosition - _downPos!).distance;
      final time = DateTime.now().difference(_downTime!).inMilliseconds;
      if (dist < _tapSlop && time < 350) {
        _send({'type': 'mouse_click', 'button': 'left'});
        _lastTapUp = DateTime.now();
      }
    }
    _id1 = null;
    _pos1 = null;
    _downPos = null;
    _downTime = null;
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer == _id2) {
      _id2 = null;
      _pos2 = null;
      _gestureSent = false;
      return;
    }
    if (e.pointer != _id1) return;
    _endDrag();
    _id1 = null;
    _id2 = null;
    _pos1 = null;
    _pos2 = null;
    _downPos = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancel,
        child: const SizedBox.expand(),
      );
}

// ── Scroll strip — dedicated one-finger scroll lane ──────────────────────────

class _ScrollStrip extends StatefulWidget {
  const _ScrollStrip({required this.onScroll});
  final void Function(int dy) onScroll;

  @override
  State<_ScrollStrip> createState() => _ScrollStripState();
}

class _ScrollStripState extends State<_ScrollStrip> {
  double _acc = 0;
  bool _active = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onVerticalDragStart: (_) => setState(() => _active = true),
        onVerticalDragEnd: (_) => setState(() {
          _active = false;
          _acc = 0;
        }),
        onVerticalDragCancel: () => setState(() {
          _active = false;
          _acc = 0;
        }),
        onVerticalDragUpdate: (d) {
          _acc += d.delta.dy;
          if (_acc.abs() > 4) {
            widget.onScroll((_acc * 10).round());
            _acc = 0;
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34,
          decoration: BoxDecoration(
            color: _active
                ? _accent.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: _active
                    ? _accent.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Icon(Icons.keyboard_arrow_up,
                    color: Colors.white.withValues(alpha: _active ? 0.6 : 0.2),
                    size: 18),
              ),
              RotatedBox(
                quarterTurns: 3,
                child: Text('SCROLL',
                    style: TextStyle(
                        color:
                            Colors.white.withValues(alpha: _active ? 0.5 : 0.18),
                        fontSize: 8,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Icon(Icons.keyboard_arrow_down,
                    color: Colors.white.withValues(alpha: _active ? 0.6 : 0.2),
                    size: 18),
              ),
            ],
          ),
        ),
      );
}

// ── Press-and-hold mouse button ──────────────────────────────────────────────

class _PressButton extends StatefulWidget {
  const _PressButton(
      {required this.label, required this.onDown, required this.onUp});
  final String label;
  final VoidCallback onDown, onUp;

  @override
  State<_PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<_PressButton> {
  bool _p = false;

  void _release() {
    if (!_p) return;
    setState(() => _p = false);
    widget.onUp();
  }

  @override
  void dispose() {
    // Stuck-input safety: release if the screen dies mid-press.
    if (_p) widget.onUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) {
          setState(() => _p = true);
          Haptics.instance.tick();
          widget.onDown();
        },
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _p
                ? _accent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: _p ? _accent : Colors.white.withValues(alpha: 0.1)),
          ),
          child: Text(widget.label,
              style: TextStyle(
                  color: _p ? _accent : Colors.white54,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700)),
        ),
      );
}
