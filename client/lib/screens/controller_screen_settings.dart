part of 'controller_screen.dart';

// Settings overlay panel — extracted from controller_screen.dart.

class _SettingsPanel extends StatefulWidget {
  const _SettingsPanel({
    required this.onClose,
    required this.profileId,
    required this.steerMode,
    required this.onSteerMode,
    required this.onEditCurrent,
    required this.streamOn,
    required this.mouseMode,
    required this.onHideHud,
  });
  final VoidCallback onClose;
  final String profileId;
  final String steerMode;
  final ValueChanged<String> onSteerMode;
  final VoidCallback onEditCurrent;
  final bool streamOn;
  final bool mouseMode;           // surface mouse settings first when in mouse mode
  final VoidCallback onHideHud;   // enter monitor mode (hide all controls)
  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  late double _leftStick;
  late double _rightStick;
  late double _dead;
  late double _mouse;
  late double _vibStrength;
  late double _joyRadius;
  late double _gasSize;
  late double _brakeSize;
  late double _hbSize;
  late String _streamQuality;
  late bool _streamFit;

  @override
  void initState() {
    super.initState();
    final s     = WebSocketService.instance.sensitivity;
    _leftStick  = s.stickSensitivity;
    _rightStick = s.rightStickSensitivity;
    _dead       = s.deadZone;
    _mouse       = s.mouseSensitivity;
    _vibStrength = s.vibrationStrength;
    _joyRadius   = s.joyRadius;
    _gasSize    = s.gasSize;
    _brakeSize  = s.brakeSize;
    _hbSize     = s.handbrakeSize;
    _streamQuality = s.streamQuality;
    _streamFit     = s.streamFitStretch;
  }

  @override
  void dispose() {
    // Persist whenever the panel closes, however it was dismissed.
    WebSocketService.instance.saveSensitivity();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final sz = MediaQuery.of(context).size;
    final forza = widget.profileId == 'forza';
    return Stack(children: [
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: widget.onClose,
        child: const SizedBox.expand())),
      Positioned(
        top: top + 42, left: 10,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, (1 - t) * -8), child: child),
          ),
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              width: 200,
              constraints: BoxConstraints(maxHeight: (sz.height - top - 54).clamp(200.0, sz.height)),
              decoration: BoxDecoration(
                color: const Color(0xFF14161F).withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _header(),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // While streaming, the controls that matter live up top.
                        if (widget.streamOn) ...[
                          _section('Streaming'),
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final opt in const [
                              ('360p', '360p'),
                              ('480p', '480p'),
                              ('720p', '720p'),
                              ('1080p', '1080p'),
                              ('screen', '2nd Screen'),
                            ])
                              GestureDetector(
                                onTap: () {
                                  setState(() => _streamQuality = opt.$1);
                                  WebSocketService.instance.sensitivity.streamQuality = opt.$1;
                                  WebSocketService.instance.send({'type': 'set_stream_quality', 'quality': opt.$1});
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _streamQuality == opt.$1 ? const Color(0x226FB6FF) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _streamQuality == opt.$1 ? const Color(0xFF6FB6FF) : const Color(0xFF3A3A55)),
                                  ),
                                  child: Text(opt.$2, style: TextStyle(
                                    color: _streamQuality == opt.$1 ? const Color(0xFF6FB6FF) : Colors.white54,
                                    fontSize: 12, fontWeight: _streamQuality == opt.$1 ? FontWeight.bold : FontWeight.normal)),
                                ),
                              ),
                          ]),
                          const SizedBox(height: 4),
                          _switchRow('Stretch to fill', _streamFit, (v) {
                            setState(() => _streamFit = v);
                            WebSocketService.instance.sensitivity.streamFitStretch = v;
                          }),
                          // Monitor mode lives here (only meaningful while mirroring).
                          GestureDetector(
                            onTap: widget.onHideHud,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Row(children: [
                                const Icon(Icons.visibility_off, color: Colors.white60, size: 16),
                                const SizedBox(width: 8),
                                const Text('Hide controls (monitor mode)',
                                  style: TextStyle(color: Colors.white70, fontSize: 11)),
                                const Spacer(),
                                Icon(Icons.chevron_right,
                                  color: Colors.white.withValues(alpha: 0.3), size: 16),
                              ]),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 24, bottom: 2),
                            child: Text('Double-tap the screen to bring them back',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 9)),
                          ),
                          const Divider(color: Color(0xFF24243A), height: 20),
                        ],
                        ...forza ? _forzaSettings() : _standardSettings(),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
            ),
            ),
          ),
        ),
      ),
    ]);
  }

  List<Widget> _sticksSettings() => [
    _section('Sticks'),
    _sliderRow('Left sensitivity', _leftStick, 0.3, 2.0, (v) {
      setState(() => _leftStick = v);
      WebSocketService.instance.sensitivity.stickSensitivity = v;
    }),
    _sliderRow('Right sensitivity', _rightStick, 0.5, 3.0, (v) {
      setState(() => _rightStick = v);
      WebSocketService.instance.sensitivity.rightStickSensitivity = v;
    }),
    _sliderRow('Size', _joyRadius, 0.5, 2.0, (v) {
      setState(() => _joyRadius = v);
      WebSocketService.instance.sensitivity.joyRadius = v;
    }),
    _sliderRow('Dead zone', _dead, 0.01, 0.25, (v) {
      setState(() => _dead = v);
      WebSocketService.instance.sensitivity.deadZone = v;
    }, fmt: (v) => '${(v * 100).round()}%'),
  ];

  List<Widget> _mouseSettings() => [
    _section('Mouse'),
    _sliderRow('Speed', _mouse, 5, 40, (v) {
      setState(() => _mouse = v);
      WebSocketService.instance.sensitivity.mouseSensitivity = v;
    }, fmt: (v) => v.toStringAsFixed(0)),
  ];

  // In mouse mode the player wants mouse speed first; on the controller, stick
  // feel comes first. Same controls, order follows what they're actually using.
  List<Widget> _standardSettings() => [
    if (widget.mouseMode) ...[
      ..._mouseSettings(),
      const SizedBox(height: 16),
      ..._sticksSettings(),
    ] else ...[
      ..._sticksSettings(),
      const SizedBox(height: 16),
      ..._mouseSettings(),
    ],
    _section('General'),
    _vibrationRow(),
    const SizedBox(height: 18),
    _resetLink(),
  ];

  List<Widget> _forzaSettings() => [
    _section('Steering'),
    _modeSegment(),
    _sliderRow('Sensitivity', _leftStick, 0.3, 2.0, (v) {
      setState(() => _leftStick = v);
      WebSocketService.instance.sensitivity.stickSensitivity = v;
    }),
    _sliderRow('Dead zone', _dead, 0.01, 0.25, (v) {
      setState(() => _dead = v);
      WebSocketService.instance.sensitivity.deadZone = v;
    }, fmt: (v) => '${(v * 100).round()}%'),
    const SizedBox(height: 16),
    // All four main controls are resizable — not just the steering.
    _section('Control sizes'),
    _sliderRow(
        widget.steerMode == 'wheel' ? 'Steering wheel'
        : widget.steerMode == 'slider' ? 'Steering slider'
        : widget.steerMode == 'tilt' ? 'Tilt indicator'
        : 'Steering pads',
        _joyRadius, 0.5, 2.0, (v) {
      setState(() => _joyRadius = v);
      WebSocketService.instance.sensitivity.joyRadius = v;
    }),
    _sliderRow('Gas pedal', _gasSize, 0.6, 1.8, (v) {
      setState(() => _gasSize = v);
      WebSocketService.instance.sensitivity.gasSize = v;
    }),
    _sliderRow('Brake pedal', _brakeSize, 0.6, 1.8, (v) {
      setState(() => _brakeSize = v);
      WebSocketService.instance.sensitivity.brakeSize = v;
    }),
    _sliderRow('Handbrake', _hbSize, 0.6, 1.8, (v) {
      setState(() => _hbSize = v);
      WebSocketService.instance.sensitivity.handbrakeSize = v;
    }),
    _section('General'),
    _vibrationRow(),
    const SizedBox(height: 18),
    _resetLink(),
  ];

  Widget _resetLink() => Center(child: GestureDetector(
    onTap: _resetDefaults,
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Text('Reset to defaults', style: TextStyle(
        color: Colors.white.withValues(alpha: 0.4), fontSize: 12,
        decoration: TextDecoration.underline)),
    ),
  ));

  Widget _modeSegment() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Steering style', style: TextStyle(color: Colors.white, fontSize: 14)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _modeChip('Wheel', 'wheel'),
        _modeChip('Slider', 'slider'),
        _modeChip('Tilt', 'tilt'),
        _modeChip('Pads', 'pads'),
      ]),
    ]),
  );

  Widget _modeChip(String label, String mode) {
    final active = widget.steerMode == mode;
    return GestureDetector(
      onTap: () => widget.onSteerMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0x226FB6FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? const Color(0xFF6FB6FF) : const Color(0xFF3A3A55)),
        ),
        child: Text(label, style: TextStyle(
          color: active ? const Color(0xFF6FB6FF) : Colors.white54,
          fontSize: 13, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  void _resetDefaults() {
    final d = SensitivitySettings();
    final s = WebSocketService.instance.sensitivity;
    s.stickSensitivity      = d.stickSensitivity;
    s.rightStickSensitivity = d.rightStickSensitivity;
    s.deadZone              = d.deadZone;
    s.mouseSensitivity      = d.mouseSensitivity;
    s.vibration             = d.vibration;
    s.vibrationStrength     = d.vibrationStrength;
    s.joyRadius             = d.joyRadius;
    s.gasSize               = d.gasSize;
    s.brakeSize             = d.brakeSize;
    s.handbrakeSize         = d.handbrakeSize;
    s.streamQuality = '480p';
    WebSocketService.instance.saveSensitivity();
    setState(() {
      _leftStick     = d.stickSensitivity;
      _rightStick    = d.rightStickSensitivity;
      _dead          = d.deadZone;
      _mouse         = d.mouseSensitivity;
      _vibStrength   = d.vibrationStrength;
      _joyRadius     = d.joyRadius;
      _gasSize       = d.gasSize;
      _brakeSize     = d.brakeSize;
      _hbSize        = d.handbrakeSize;
      _streamQuality = '480p';
    });
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 12, 10),
    child: Row(children: [
      const Text('SETTINGS', style: TextStyle(
        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600,
        letterSpacing: 1.8)),
      const Spacer(),
      GestureDetector(
        onTap: () {
          widget.onClose();
          widget.onEditCurrent();
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(
            shape: BoxShape.circle, color: Color(0xFF1A1A24)),
          child: const Icon(Icons.edit_outlined, color: Color(0xFF6FB6FF), size: 16),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: widget.onClose,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(
            shape: BoxShape.circle, color: Color(0xFF1A1A24)),
          child: const Icon(Icons.close, color: Colors.white54, size: 16),
        ),
      ),
    ]),
  );

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 2),
    child: Text(title.toUpperCase(), style: TextStyle(
      color: Colors.white.withValues(alpha: 0.35), fontSize: 9,
      fontWeight: FontWeight.bold, letterSpacing: 1.5)),
  );

  // Vibration strength sits right alongside the sensitivity/size sliders. 0% =
  // off; dragging previews the buzz so the player feels what they're dialing in.
  int _lastVibPct = -1;
  Widget _vibrationRow() => _sliderRow('Vibration', _vibStrength, 0.0, 1.0, (v) {
        setState(() => _vibStrength = v);
        final s = WebSocketService.instance.sensitivity;
        s.vibrationStrength = v;
        s.vibration = v > 0.01;            // keep master flag in sync
        final pct = (v * 100).round();
        if (pct != _lastVibPct && pct % 5 == 0) {
          _lastVibPct = pct;
          Haptics.instance.preview();      // no-op at 0% (master off)
        }
      }, fmt: (v) => v < 0.01 ? 'Off' : '${(v * 100).round()}%');

  Widget _sliderRow(String label, double value, double min, double max,
      ValueChanged<double> onChanged, {String Function(double)? fmt}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const Spacer(),
          Text(fmt != null ? fmt(value) : value.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
        SizedBox(
          height: 24,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: Colors.white70,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.10),
              thumbColor: Colors.white,
              overlayColor: const Color(0x11FFFFFF),
            ),
            child: Slider(value: value, min: min, max: max, onChanged: onChanged),
          ),
        ),
      ]),
    );

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const Spacer(),
        SizedBox(
          height: 20,
          child: Transform.scale(
            scale: 0.8,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.white,
              activeTrackColor: Colors.white24,
              inactiveThumbColor: Colors.white54,
              inactiveTrackColor: const Color(0xFF20202C),
            ),
          ),
        ),
      ]),
    );
}

// ── Background glow ───────────────────────────────────────────────────────────
