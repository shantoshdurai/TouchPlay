import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/websocket_service.dart';
import '../services/websocket_service.dart' as ws;
import '../services/device_stats.dart';
import '../services/haptics.dart';
import '../services/stream_service.dart';
import '../games/game_profiles.dart';
import '../games/custom_layout.dart';
import '../widgets/trigger_button.dart';
import '../widgets/action_button.dart';
import '../widgets/forza_controls.dart';
import '../widgets/custom_controls.dart';
import 'layout_editor.dart';

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});
  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  late final StreamSubscription<ws.ConnectionState> _sub;
  ws.ConnectionState _conn = ws.ConnectionState.disconnected;
  bool _mouseMode        = false;
  bool _showSettings     = false;
  bool _showTutorial     = false;
  bool _showGames        = false;   // full grid picker (soon games, new, edit)
  bool _showGamesMenu    = false;   // quick-switch dropdown from the pill
  bool _showSteerChooser = false;
  bool _showForzaEditChooser = false; // "edit which steering?" before the editor

  // ── Game stream ──────────────────────────────────────────────────────────────
  bool        _streamOn   = false;
  Uint8List?  _streamFrame;
  StreamSubscription<Uint8List>? _streamSub;
  String _profileId  = 'standard';   // 'standard' | 'forza' | 'custom:<id>'
  String _forzaSteer = 'wheel';      // 'wheel' | 'pads'
  List<CustomLayout> _customLayouts = [];
  DateTime? _lastBackPress;          // back-button "press again to exit" guard

  bool get _anyOverlayOpen =>
      _showSettings || _showGames || _showGamesMenu ||
      _showTutorial || _showSteerChooser || _showForzaEditChooser;

  // Android back: close any open overlay first; otherwise require a double-press
  // so you can't rage-quit the game by brushing the back gesture mid-match.
  void _onBackInvoked(bool didPop, Object? result) {
    if (didPop) return;
    if (_anyOverlayOpen) {
      setState(() {
        _showSettings = false; _showGames = false; _showGamesMenu = false;
        _showTutorial = false; _showSteerChooser = false; _showForzaEditChooser = false;
      });
      return;
    }
    final now = DateTime.now();
    if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Press back again to exit'),
        duration: Duration(milliseconds: 1800),
        behavior: SnackBarBehavior.floating,
      ));
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _sub = WebSocketService.instance.stateStream.listen((s) => setState(() => _conn = s));
    WebSocketService.instance.init();
    DeviceStats.instance.start();
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    final prefs       = await SharedPreferences.getInstance();
    final customs     = await CustomLayoutStore.load();
    var   p           = prefs.getString('selected_profile') ?? 'standard';
    final steer       = prefs.getString('forza_steering') ?? 'wheel';
    final chooserSeen = prefs.getBool('forza_chooser_seen') ?? false;
    final tutSeen     = prefs.getBool('tutorial_seen_v2') ?? false;

    // If the saved custom layout no longer exists, fall back to standard.
    if (p.startsWith('custom:') && !customs.any((l) => 'custom:${l.id}' == p)) {
      p = 'standard';
    }

    bool showTut = false, showChooser = false;
    if (p == 'standard' && !tutSeen) {
      await prefs.setBool('tutorial_seen_v2', true);
      showTut = true;
    } else if (p == 'forza' && !chooserSeen) {
      showChooser = true;
    }
    if (!mounted) return;
    setState(() {
      _customLayouts    = customs;
      _profileId        = p;
      _forzaSteer       = steer;
      _showTutorial     = showTut;
      _showSteerChooser = showChooser;
    });
  }

  CustomLayout? get _activeCustom {
    if (!_profileId.startsWith('custom:')) return null;
    final id = _profileId.substring(7);
    for (final l in _customLayouts) { if (l.id == id) return l; }
    return null;
  }

  // ── Custom layout management ─────────────────────────────────────────────────
  Future<void> _openEditor(CustomLayout layout) async {
    final edited = await Navigator.of(context).push<CustomLayout>(
      MaterialPageRoute(builder: (_) => LayoutEditorScreen(layout: layout.copy())),
    );
    // Restore our own immersive mode after the editor route pops.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (edited == null) return;
    final i = _customLayouts.indexWhere((l) => l.id == edited.id);
    if (i >= 0) {
      _customLayouts[i] = edited;
    } else {
      _customLayouts.add(edited);
    }
    await CustomLayoutStore.saveAll(_customLayouts);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_profile', 'custom:${edited.id}');
    if (!mounted) return;
    setState(() { _profileId = 'custom:${edited.id}'; _showGames = false; });
  }

  Future<void> _deleteCustom(CustomLayout layout) async {
    _customLayouts.removeWhere((l) => l.id == layout.id);
    await CustomLayoutStore.saveAll(_customLayouts);
    final wasActive = _profileId == 'custom:${layout.id}';
    if (wasActive) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_profile', 'standard');
    }
    if (!mounted) return;
    setState(() { if (wasActive) _profileId = 'standard'; });
  }

  // ── Game stream toggle ───────────────────────────────────────────────────────
  void _toggleStream() {
    if (_streamOn) {
      _streamSub?.cancel();
      StreamService.instance.disconnect();
      setState(() { _streamOn = false; _streamFrame = null; });
    } else {
      final ip = WebSocketService.instance.currentIp;
      if (ip == null) return; // not connected — nothing to stream
      StreamService.instance.connect(ip);
      WebSocketService.instance.send({
        'type': 'set_stream_quality',
        'high_quality': WebSocketService.instance.sensitivity.streamHighQuality,
      });
      _streamSub = StreamService.instance.frameStream.listen((frame) {
        if (mounted) setState(() => _streamFrame = frame);
      });
      setState(() => _streamOn = true);
    }
  }

  void _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_profile', _profileId);
  }

  void _openEditCurrent() {
    if (_profileId == 'standard' || _profileId == 'forza' || _profileId == 'spiderman' || _profileId == 'overcooked') {
      _customizePreset(_profileId);
    } else {
      final c = _activeCustom;
      if (c != null) _openEditor(c);
    }
  }

  void _deleteCurrentCustom() {
    if (!_profileId.startsWith('custom:')) return;
    final id = _profileId.substring(7);
    setState(() {
      _customLayouts.removeWhere((l) => l.id == id);
      _profileId = 'standard';
    });
    CustomLayoutStore.saveAll(_customLayouts);
    _saveProfile();
  }

  void _newLayout() async {
    showDialog(context: context, builder: (_) =>
      _TemplatePicker(onPick: (tpl) {
        Navigator.of(context).pop();
        _openEditor(newLayoutFromTemplate(tpl));
      }));
  }

  // "Customize" a built-in preset → open an editable copy in the editor.
  // Forza first asks which steering style to edit (wheel / slider / tilt / pads),
  // then opens the editor with that steering control + pedals + buttons.
  Future<void> _customizePreset(String id) async {
    if (id == 'standard') {
      await _openEditor(cloneStandard());
    } else if (id == 'forza') {
      setState(() { _showGames = false; _showForzaEditChooser = true; });
    } else if (id == 'spiderman') {
      await _openEditor(cloneSpiderman());
    } else if (id == 'overcooked') {
      await _openEditor(cloneOvercooked());
    }
  }

  Future<void> _selectProfile(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_profile', id);
    final seen = prefs.getBool('forza_chooser_seen') ?? false;
    if (!mounted) return;
    setState(() {
      _profileId        = id;
      _showGames        = false;
      _showSteerChooser = id == 'forza' && !seen;
    });
  }

  Future<void> _setSteer(String mode, {bool markSeen = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('forza_steering', mode);
    if (markSeen) await prefs.setBool('forza_chooser_seen', true);
    if (!mounted) return;
    setState(() {
      _forzaSteer = mode;
      if (markSeen) _showSteerChooser = false;
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _streamSub?.cancel();
    StreamService.instance.disconnect();
    DeviceStats.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final h = size.height;
    final w = size.width;
    final isForza  = _profileId == 'forza';
    final isSpider = _profileId == 'spiderman';
    final isOvercooked = _profileId == 'overcooked';
    final custom   = _activeCustom;
    final disp     = profileById(_profileId);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onBackInvoked,
      child: Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: Stack(
        children: [
          // 1. Background — game stream if active, else standard glow
          if (_streamOn && _streamFrame != null)
            Positioned.fill(
              child: Image.memory(
                _streamFrame!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            )
          else
            _BgGlow(),

          // 2. Active game layout
          ...(custom != null
              ? _customChildren(custom, w, h)
              : isSpider
                  ? _spidermanChildren(w, h)
                  : isOvercooked
                      ? _overcookedChildren(w, h)
                  : isForza
                      ? _forzaChildren(w, h)
                      : _standardChildren(w, h)),

          // 3. Connection chip (top-left)
          Positioned(
            top: 0, left: 8,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _ConnChip(state: _conn, onTap: () => _showDialog(context)),
              ),
            ),
          ),

          // 4. Top-right: Games tab + Settings
          Positioned(
            top: 0, right: 8,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _GamesBtn(
                    icon: custom != null ? Icons.tune : disp.icon,
                    label: custom != null ? custom.name : disp.name,
                    onTap: () => setState(() => _showGamesMenu = !_showGamesMenu),
                  ),
                  const SizedBox(width: 8),
                  _StreamBtn(
                    active: _streamOn,
                    onTap: _toggleStream,
                  ),
                  const SizedBox(width: 8),
                  _SettingsBtn(onTap: () => setState(() => _showSettings = !_showSettings)),
                ]),
              ),
            ),
          ),

          // 5. Overlays
          if (_showSettings)
            _SettingsPanel(
              onClose: () => setState(() => _showSettings = false),
              profileId: _profileId,
              steerMode: _forzaSteer,
              onSteerMode: (m) => _setSteer(m),
              onEditCurrent: _openEditCurrent,
            ),
          if (_showGamesMenu)
            _GamesDropdown(
              currentId: _profileId,
              customLayouts: _customLayouts,
              onPick: (id) { setState(() => _showGamesMenu = false); _selectProfile(id); },
              onNew: () { setState(() => _showGamesMenu = false); _newLayout(); },
              onMore: () => setState(() { _showGamesMenu = false; _showGames = true; }),
              onEditCurrent: () {
                setState(() => _showGamesMenu = false);
                _openEditCurrent();
              },
              onDeleteCurrent: () {
                setState(() => _showGamesMenu = false);
                _deleteCurrentCustom();
              },
              onClose: () => setState(() => _showGamesMenu = false),
            ),
          if (_showGames)
            _GamePicker(
              currentId: _profileId,
              customLayouts: _customLayouts,
              onPick: _selectProfile,
              onNew: _newLayout,
              onEdit: _openEditor,
              onDelete: _deleteCustom,
              onCustomize: _customizePreset,
              onClose: () => setState(() => _showGames = false),
            ),
          if (_showTutorial)
            _TutorialOverlay(onDismiss: () => setState(() => _showTutorial = false)),
          if (_showSteerChooser)
            _SteerChooser(onPick: (m) => _setSteer(m, markSeen: true)),
          if (_showForzaEditChooser)
            _SteerChooser(
              title: 'EDIT WHICH STEERING?',
              subtitle: 'Pick the steering you use — the editor opens with it,\n'
                  'plus the pedals & buttons, all movable & resizable.',
              onPick: (style) {
                setState(() => _showForzaEditChooser = false);
                _openEditor(cloneForza(style));
              },
              onClose: () => setState(() => _showForzaEditChooser = false),
            ),
        ],
      ),
    )); // PopScope + Scaffold
  }

  // ── STANDARD GAMEPAD layout ──────────────────────────────────────────────────
  List<Widget> _standardChildren(double w, double h) => [
        // Center split line
        Positioned(
          left: w * 0.5, top: 0, bottom: 0,
          child: Container(width: 1, color: Colors.white.withValues(alpha: 0.07)),
        ),
        // LEFT floating stick (movement)
        Positioned(
          left: 0, top: 28, bottom: 0, width: w * 0.5,
          child: _FloatingStick(side: 'left', screenH: h),
        ),
        // RIGHT floating stick (camera / mouse)
        Positioned(
          right: 0, top: 28, bottom: 0, width: w * 0.5,
          child: _FloatingStick(side: 'right', screenH: h, mouseMode: _mouseMode),
        ),
        // Top / center navigation
        Positioned(
          top: h * 0.15, left: 0, right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CenterButton(button: 'BACK', icon: Icons.arrow_back_ios_new, size: 24),
              SizedBox(width: w * 0.04),
              const GuideButton(size: 44),
              SizedBox(width: w * 0.04),
              const CenterButton(button: 'START', icon: Icons.play_arrow, size: 24),
            ],
          ),
        ),
        // Mouse toggle + R-Click pill
        Positioned(
          bottom: h * 0.05, left: 0, right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MouseToggleButton(
                mouseMode: _mouseMode,
                onToggle: () => setState(() => _mouseMode = !_mouseMode),
              ),
              if (_mouseMode) ...[
                const SizedBox(width: 12),
                const _MouseBtn(button: 'right', label: 'R-Click'),
              ],
            ],
          ),
        ),
        // Left side buttons
        Positioned(
          top: 28, left: w * 0.02, bottom: h * 0.05,
          child: SizedBox(
            width: w * 0.35,
            child: Stack(
              children: [
                Positioned(top: h * 0.05, left: w * 0.05, child: const TriggerBar(side: 'left', label: 'LT', width: 56, height: 56)),
                Positioned(top: h * 0.05, right: w * 0.05, child: const BumperButton(button: 'LB', label: 'LB', width: 56)),
                Positioned(bottom: h * 0.05, left: 0, child: const ActionButton(button: 'LS', label: 'L3', size: 56)),
                Positioned(top: h * 0.3, left: w * 0.02, child: const DPad(size: 140)),
              ],
            ),
          ),
        ),
        // Right side buttons
        if (!_mouseMode)
          Positioned(
            top: 28, right: w * 0.02, bottom: h * 0.05,
            child: SizedBox(
              width: w * 0.35,
              child: Stack(
                children: [
                  Positioned(top: h * 0.05, left: w * 0.05, child: const BumperButton(button: 'RB', label: 'RB', width: 56)),
                  Positioned(top: h * 0.05, right: w * 0.05, child: const TriggerBar(side: 'right', label: 'RT', width: 56, height: 56)),
                  Positioned(bottom: h * 0.05, right: 0, child: const ActionButton(button: 'RS', label: 'R3', size: 56)),
                  Positioned(bottom: h * 0.25, right: w * 0.05, child: _FaceButtons()),
                ],
              ),
            ),
          ),
      ];

  // ── FORZA HORIZON layout — mobile racing HUD ─────────────────────────────────
  // Every control sends a standard gamepad event (FH5 default mapping):
  //   GAS→RT  BRAKE→LT  HANDBRAKE→A  CAM→RB  REWIND→Y  HORN→RS
  //   CLUTCH→LB  SHIFTâ†‘→B  MAP→BACK  ANNA→DPADâ†“  PHOTO→DPADâ†‘  PAUSE→START
  List<Widget> _forzaChildren(double w, double h) {
    final s      = WebSocketService.instance.sensitivity;
    final joyR   = s.joyRadius;
    final pedalW = (w * 0.12).clamp(70.0, 150.0);
    final small  = (h * 0.13).clamp(46.0, 78.0);
    final big    = (h * 0.18).clamp(64.0, 110.0);
    final mini   = small * 0.72;

    // The four main racing controls are each resizable from Settings: steering
    // uses joyRadius (above); gas / brake / handbrake use their own size factors.
    final gasW   = pedalW * s.gasSize;
    final brakeW = pedalW * s.brakeSize;
    final gasH   = (h * 0.46 * s.gasSize).clamp(150.0, 360.0);
    final brakeH = (h * 0.36 * s.brakeSize).clamp(120.0, 300.0);
    final hbSize = (big * s.handbrakeSize).clamp(56.0, 150.0);

    return [
      // Right floating stick for mouse mode
      Positioned(
        right: 0, top: 28, bottom: 0, width: w * 0.5,
        child: _FloatingStick(side: 'right', screenH: h, mouseMode: _mouseMode),
      ),
      // Mouse toggle + R-Click pill
      Positioned(
        bottom: h * 0.05, left: 0, right: 0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MouseToggleButton(
              mouseMode: _mouseMode,
              onToggle: () => setState(() => _mouseMode = !_mouseMode),
            ),
            if (_mouseMode) ...[
              const SizedBox(width: 12),
              const _MouseBtn(button: 'right', label: 'R-Click'),
            ],
          ],
        ),
      ),

      // STEERING (bottom-left) — wheel / slider / tilt / L-R pads
      if (_forzaSteer == 'wheel')
        Positioned(
          left: 0, right: w * 0.54, top: h * 0.30, bottom: 0,
          child: SteeringWheel(diameter: (h * 0.42 * joyR).clamp(150.0, 320.0)),
        )
      else if (_forzaSteer == 'slider')
        Positioned(
          left: 0, right: w * 0.50, top: h * 0.42, bottom: 0,
          child: SteeringSlider(width: (w * 0.34 * joyR).clamp(220.0, 380.0)),
        )
      else if (_forzaSteer == 'tilt')
        Positioned(
          left: w * 0.05, bottom: h * 0.10,
          child: const SteeringTilt(),
        )
      else ...[
        Positioned(
          left: w * 0.05, bottom: h * 0.11,
          child: SteeringPad(left: true, size: (h * 0.22 * joyR).clamp(80.0, 150.0)),
        ),
        Positioned(
          left: w * 0.21, bottom: h * 0.11,
          child: SteeringPad(left: false, size: (h * 0.22 * joyR).clamp(80.0, 150.0)),
        ),
      ],

      // PEDALS (bottom-right): GAS=RT, BRAKE=LT
      if (!_mouseMode) Positioned(
        right: w * 0.035, bottom: h * 0.07,
        child: RacePedal(gas: true, label: 'GAS', icon: Icons.local_gas_station,
            width: gasW, height: gasH),
      ),
      if (!_mouseMode) Positioned(
        right: w * 0.035 + gasW + w * 0.02, bottom: h * 0.07,
        child: RacePedal(gas: false, label: 'BRAKE', icon: Icons.front_hand,
            width: brakeW, height: brakeH),
      ),

      // HANDBRAKE (drift) = A — just left of the pedals
      if (!_mouseMode) Positioned(
        right: w * 0.06 + gasW + brakeW, bottom: h * 0.13,
        child: RaceButton(button: 'A', label: 'HBRAKE', icon: Icons.local_parking, size: hbSize),
      ),

      // Secondary cluster (upper-right): CAM=RB, REWIND=Y, HORN=RS
      if (!_mouseMode) Positioned(
        top: h * 0.15, right: w * 0.04,
        child: Row(children: [
          RaceButton(button: 'RB', label: 'CAM', icon: Icons.cameraswitch, size: small),
          SizedBox(width: w * 0.015),
          RaceButton(button: 'Y', label: 'REWIND', icon: Icons.replay, size: small),
          SizedBox(width: w * 0.015),
          RaceButton(button: 'RS', label: 'HORN', icon: Icons.campaign, size: small),
        ]),
      ),

      // Menu cluster (upper-left): A = select/confirm, B = back/close — so you can
      // answer in-game prompts (e.g. rewind "confirm?") without switching layouts.
      Positioned(
        top: h * 0.15, left: w * 0.04,
        child: Row(children: [
          RaceButton(button: 'A', label: 'SELECT', icon: Icons.check, size: small),
          SizedBox(width: w * 0.015),
          RaceButton(button: 'B', label: 'BACK', icon: Icons.close, size: small),
        ]),
      ),

      // Top-center utility (quiet, icon-only): MAP, ANNA, PHOTO, PAUSE
      Positioned(
        top: h * 0.05, left: 0, right: 0,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          RaceButton(button: 'BACK', label: 'MAP', icon: Icons.map, size: mini, showLabel: false),
          SizedBox(width: w * 0.022),
          RaceButton(button: 'DPAD_DOWN', label: 'ANNA', icon: Icons.assistant, size: mini, showLabel: false),
          SizedBox(width: w * 0.022),
          RaceButton(button: 'DPAD_UP', label: 'PHOTO', icon: Icons.photo_camera, size: mini, showLabel: false),
          SizedBox(width: w * 0.022),
          RaceButton(button: 'START', label: 'PAUSE', icon: Icons.pause, size: mini, showLabel: false),
        ]),
      ),
    ];
  }

  // ── MARVEL'S SPIDER-MAN 2 layout ─────────────────────────────────────────────
  // Rendered from the SAME editable definition you get when you tap Customize, so
  // the default and the editor always match. Left half = MOVE, right half =
  // CAMERA (fixed sticks); SWING on the right; every button is rebindable.
  CustomLayout? _spidermanLayout;
  List<Widget> _spidermanChildren(double w, double h) =>
      _customChildren(_spidermanLayout ??= cloneSpiderman(), w, h);

  CustomLayout? _overcookedLayout;
  List<Widget> _overcookedChildren(double w, double h) =>
      _customChildren(_overcookedLayout ??= cloneOvercooked(), w, h);

  // ── CUSTOM layout (play mode) ────────────────────────────────────────────────
  List<Widget> _customChildren(CustomLayout layout, double w, double h) {
    if (layout.items.isEmpty) {
      return [
        Center(child: GestureDetector(
          onTap: () => _openEditor(layout),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x66FFFFFF))),
            child: const Text('Empty layout — tap to add controls',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
          ),
        )),
      ];
    }
    return [
      // Standard "Xbox" fixed sticks — full-half floating sticks drawn under the
      // editable controls (so buttons on top still capture their own touches).
      if (layout.floatingSticks) ...[
        Positioned(
          left: w * 0.5, top: 0, bottom: 0,
          child: Container(width: 1, color: Colors.white.withValues(alpha: 0.07)),
        ),
        Positioned(
          left: 0, top: 28, bottom: 0, width: w * 0.5,
          child: _FloatingStick(side: 'left', screenH: h),
        ),
        Positioned(
          right: 0, top: 28, bottom: 0, width: w * 0.5,
          child: _FloatingStick(side: 'right', screenH: h, mouseMode: _mouseMode),
        ),
        Positioned(
          bottom: h * 0.05, left: 0, right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MouseToggleButton(
                mouseMode: _mouseMode,
                onToggle: () => setState(() => _mouseMode = !_mouseMode),
              ),
              if (_mouseMode) ...[
                const SizedBox(width: 12),
                const _MouseBtn(button: 'right', label: 'R-Click'),
              ],
            ],
          ),
        ),
      ],
      for (final item in layout.items)
        if (!_mouseMode || item.x <= 0.5) _positionedCustom(item, w, h),
    ];
  }

  Widget _positionedCustom(ControlItem item, double w, double h) {
    final fp = controlFootprint(item);
    return Positioned(
      left: item.x * w - fp.width / 2,
      top:  item.y * h - fp.height / 2,
      width: fp.width, height: fp.height,
      child: buildCustomControl(item),
    );
  }

  void _showDialog(BuildContext ctx) =>
      showDialog(context: ctx, builder: (_) => const _IpDialog());
}

/// Unified floating joystick — used IDENTICALLY for both left and right halves.
/// Hidden until touched; spawns at the touch point; same size/style on both sides.
class _FloatingStick extends StatefulWidget {
  const _FloatingStick({
    required this.side,        // 'left' = movement, 'right' = camera
    required this.screenH,
    this.mouseMode = false,    // right side only
  });
  final String side;
  final double screenH;
  final bool   mouseMode;

  @override
  State<_FloatingStick> createState() => _FloatingStickState();
}

class _FloatingStickState extends State<_FloatingStick> {
  int?      _trackId;
  Offset?   _center;
  Offset    _thumb = Offset.zero;
  Offset?   _downPos;
  DateTime? _lastTapTime;

  bool get _isLeft  => widget.side == 'left';
  String get _stick => _isLeft ? 'left_stick' : 'right_stick';

  // Same base radius for BOTH sticks → identical size. Scaled by one setting.
  double get _joyR =>
      widget.screenH * 0.16 * WebSocketService.instance.sensitivity.joyRadius;

  static const _tapSlop     = 12.0;
  static const _doubleTapMs = 320;

  void _sendZero() =>
      WebSocketService.instance.send({'type': _stick, 'x': 0.0, 'y': 0.0});

  void _reset() {
    _trackId = null;
    _downPos = null;
    setState(() { _center = null; _thumb = Offset.zero; });
  }

  void _onDown(PointerDownEvent e) {
    if (_trackId != null) return;   // already tracking a finger
    _trackId = e.pointer;
    _downPos = e.localPosition;

    if (widget.mouseMode) {
      // double-tap → left click
      final now = DateTime.now();
      if (_lastTapTime != null &&
          now.difference(_lastTapTime!).inMilliseconds < _doubleTapMs) {
        WebSocketService.instance.send({'type': 'mouse_click', 'button': 'left'});
        _lastTapTime = null;
      }
      return;
    }
    setState(() { _center = e.localPosition; _thumb = Offset.zero; });
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _trackId) return;

    // ── Mouse / trackpad mode (right side toggle) ──
    if (widget.mouseMode) {
      if (e.delta.distance < 0.5) return;
      final sens = WebSocketService.instance.sensitivity.mouseSensitivity / 10.0;
      WebSocketService.instance.send({
        'type': 'mouse_move',
        'dx': (e.delta.dx * sens).round(),
        'dy': (e.delta.dy * sens).round(),
      });
      return;
    }

    // ── Joystick mode ──
    if (_center == null) return;
    final r = _joyR;
    var offset  = e.localPosition - _center!;
    var center  = _center!;

    // Re-centering: if finger passes the ring edge, the ring follows the finger
    // so you can keep turning/moving continuously (no hard stop at the edge).
    if (offset.distance > r) {
      final unit = offset / offset.distance;
      center = e.localPosition - unit * r;
      offset = unit * r;
    }

    setState(() { _center = center; _thumb = offset; });

    final sens = _isLeft
        ? WebSocketService.instance.sensitivity.stickSensitivity
        : WebSocketService.instance.sensitivity.rightStickSensitivity;
    final dead = WebSocketService.instance.sensitivity.deadZone;
    final nx   = offset.dx / r;
    final ny   = -offset.dy / r;
    final mag  = offset.distance / r;
    final x    = mag < dead ? 0.0 : (nx * sens).clamp(-1.0, 1.0);
    final y    = mag < dead ? 0.0 : (ny * sens).clamp(-1.0, 1.0);

    WebSocketService.instance.send({
      'type': _stick,
      'x': double.parse(x.toStringAsFixed(3)),
      'y': double.parse(y.toStringAsFixed(3)),
    });
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _trackId) return;
    if (widget.mouseMode) {
      if (_downPos != null && (e.localPosition - _downPos!).distance < _tapSlop)
        _lastTapTime = DateTime.now();
      _trackId = null;
      _downPos = null;
      return;
    }
    _sendZero();
    _reset();
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _trackId) return;
    if (!widget.mouseMode) _sendZero();
    _reset();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown:   _onDown,
    onPointerMove:   _onMove,
    onPointerUp:     _onUp,
    onPointerCancel: _onCancel,
    child: CustomPaint(
      // null painter when idle → completely hidden, nothing "stuck" on screen
      painter: _center != null
          ? _StickPainter(center: _center!, thumb: _thumb, radius: _joyR)
          : null,
      child: const SizedBox.expand(),
    ),
  );
}

// ── Stick painter — identical style for both sides ────────────────────────────

class _StickPainter extends CustomPainter {
  const _StickPainter({required this.center, required this.thumb, required this.radius});
  final Offset center;
  final Offset thumb;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    // Outer + inner rings — same color/thickness/opacity on both sticks
    final ring = Paint()
      ..color = const Color(0x66FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius,       ring);
    canvas.drawCircle(center, radius * 0.7, ring);

    // Gray dotted thumb — identical to the original left stick
    final tp     = center + thumb;
    final thumbR = radius * 0.38;
    canvas.drawCircle(tp, thumbR,
        Paint()..color = const Color(0xFFC0C0C0)..style = PaintingStyle.fill);

    final dot     = Paint()..color = const Color(0xFF888888)..style = PaintingStyle.fill;
    final spacing = thumbR * 0.25;
    final sx = tp.dx - 2 * spacing;
    final sy = tp.dy - 2 * spacing;
    for (int i = 0; i < 5; i++) {
      for (int j = 0; j < 5; j++) {
        final dx = sx + j * spacing - tp.dx;
        final dy = sy + i * spacing - tp.dy;
        if (dx * dx + dy * dy < (thumbR * 0.6) * (thumbR * 0.6))
          canvas.drawCircle(Offset(sx + j * spacing, sy + i * spacing), 1.5, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_StickPainter o) =>
      o.center != center || o.thumb != thumb || o.radius != radius;
}

class _MouseToggleButton extends StatelessWidget {
  const _MouseToggleButton({required this.mouseMode, required this.onToggle});
  final bool mouseMode;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onToggle,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: mouseMode ? Colors.white24 : Colors.transparent,
        border: Border.all(
          color: mouseMode ? Colors.white : const Color(0x66FFFFFF),
          width: 1.5,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.mouse, size: 13, color: mouseMode ? Colors.white : Colors.white60),
        const SizedBox(width: 6),
        Text('MOUSE', style: TextStyle(
          color: mouseMode ? Colors.white : Colors.white60,
          fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2,
        )),
      ]),
    ),
  );
}

// ── Face buttons ──────────────────────────────────────────────────────────────

class _FaceButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 150, height: 150,
    child: Stack(alignment: Alignment.center, children: [
      Positioned(top: 0,    child: ActionButton(button: 'Y', size: 52)),
      Positioned(left: 0,   child: ActionButton(button: 'X', size: 52)),
      Positioned(right: 0,  child: ActionButton(button: 'B', size: 52)),
      Positioned(bottom: 0, child: ActionButton(button: 'A', size: 52)),
    ]),
  );
}

// ── Mouse click buttons ───────────────────────────────────────────────────────

class _MouseBtn extends StatefulWidget {
  const _MouseBtn({required this.button, required this.label});
  final String button, label;
  @override
  State<_MouseBtn> createState() => _MouseBtnState();
}

class _MouseBtnState extends State<_MouseBtn> {
  bool _p = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) {
      setState(() => _p = true);
      WebSocketService.instance.send({'type': 'mouse_click', 'button': widget.button});
    },
    onTapUp: (_) => setState(() => _p = false),
    onTapCancel: () => setState(() => _p = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 60),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: _p ? Colors.white24 : Colors.transparent,
        border: Border.all(color: _p ? Colors.white : const Color(0x66FFFFFF)),
      ),
      child: Text(widget.label, style: const TextStyle(color: Colors.white, fontSize: 10)),
    ),
  );
}

// ── Settings panel (profile-aware) ────────────────────────────────────────────

class _SettingsPanel extends StatefulWidget {
  const _SettingsPanel({
    required this.onClose,
    required this.profileId,
    required this.steerMode,
    required this.onSteerMode,
    required this.onEditCurrent,
  });
  final VoidCallback onClose;
  final String profileId;
  final String steerMode;
  final ValueChanged<String> onSteerMode;
  final VoidCallback onEditCurrent;
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
  late bool _streamHq;

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
    _streamHq   = s.streamHighQuality;
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
        top: top + 42, right: 10,
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
            child: Container(
              width: 200,
              constraints: BoxConstraints(maxHeight: (sz.height - top - 54).clamp(200.0, sz.height)),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF24243A)),
                boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _header(),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: forza ? _forzaSettings() : _standardSettings(),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  List<Widget> _standardSettings() => [
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
    const SizedBox(height: 16),
    _section('Mouse'),
    _sliderRow('Speed', _mouse, 5, 40, (v) {
      setState(() => _mouse = v);
      WebSocketService.instance.sensitivity.mouseSensitivity = v;
    }, fmt: (v) => v.toStringAsFixed(0)),
    const SizedBox(height: 16),
    _section('Stream'),
    _switchRow('High Quality (USB Only)', _streamHq, (v) {
      setState(() => _streamHq = v);
      WebSocketService.instance.sensitivity.streamHighQuality = v;
      WebSocketService.instance.send({'type': 'set_stream_quality', 'high_quality': v});
    }),
    const SizedBox(height: 16),
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
    const SizedBox(height: 16),
    _section('Stream'),
    _switchRow('High Quality (USB Only)', _streamHq, (v) {
      setState(() => _streamHq = v);
      WebSocketService.instance.sensitivity.streamHighQuality = v;
      WebSocketService.instance.send({'type': 'set_stream_quality', 'high_quality': v});
    }),
    const SizedBox(height: 16),
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
          color: active ? const Color(0x2200D4FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? const Color(0xFF00D4FF) : const Color(0xFF3A3A55)),
        ),
        child: Text(label, style: TextStyle(
          color: active ? const Color(0xFF00D4FF) : Colors.white54,
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
    s.streamHighQuality     = false;
    WebSocketService.instance.saveSensitivity();
    setState(() {
      _leftStick   = d.stickSensitivity;
      _rightStick  = d.rightStickSensitivity;
      _dead        = d.deadZone;
      _mouse       = d.mouseSensitivity;
      _vibStrength = d.vibrationStrength;
      _joyRadius   = d.joyRadius;
      _gasSize     = d.gasSize;
      _brakeSize   = d.brakeSize;
      _hbSize      = d.handbrakeSize;
      _streamHq    = false;
    });
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 12, 10),
    child: Row(children: [
      const Text('Settings', style: TextStyle(
        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
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
          child: const Icon(Icons.edit_outlined, color: Color(0xFF00D4FF), size: 16),
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
    padding: const EdgeInsets.only(top: 6, bottom: 4),
    child: Text(title.toUpperCase(), style: const TextStyle(
      color: Color(0xFF00D4FF), fontSize: 10,
      fontWeight: FontWeight.bold, letterSpacing: 2)),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          const Spacer(),
          Text(fmt != null ? fmt(value) : value.toStringAsFixed(1),
            style: const TextStyle(
              color: Color(0xFF00D4FF), fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 2),
        SizedBox(
          height: 32,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10, elevation: 2),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
              activeTrackColor: const Color(0xFF00D4FF),
              inactiveTrackColor: const Color(0xFF20202C),
              thumbColor: Colors.white,
              overlayColor: const Color(0x2200D4FF),
            ),
            child: Slider(value: value, min: min, max: max, onChanged: onChanged),
          ),
        ),
      ]),
    );

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        const Spacer(),
        SizedBox(
          height: 24,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF00D4FF),
            activeTrackColor: const Color(0x4400D4FF),
            inactiveThumbColor: Colors.white54,
            inactiveTrackColor: const Color(0xFF20202C),
          ),
        ),
      ]),
    );
}

// ── Background glow ───────────────────────────────────────────────────────────

class _BgGlow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GlowPainter(), size: Size.infinite);
}

class _GlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    // Cross-hatch subtle background pattern matching the reference image
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final int spacing = 40;

    // Draw diagonal lines
    for (double i = -s.height; i < s.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i + s.height, s.height), paint);
    }
    for (double i = s.width + s.height; i > 0; i -= spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i - s.height, s.height), paint);
    }

    // Retain subtle glow
    final p = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
    p.color = Colors.white.withValues(alpha: 0.03);
    canvas.drawCircle(Offset(s.width * 0.2, s.height * 0.5), s.width * 0.3, p);
    canvas.drawCircle(Offset(s.width * 0.8, s.height * 0.5), s.width * 0.3, p);
  }
  @override bool shouldRepaint(_) => false;
}

// ── Connection chip + Settings button ─────────────────────────────────────────

class _ConnChip extends StatefulWidget {
  const _ConnChip({required this.state, required this.onTap});
  final ws.ConnectionState state;
  final VoidCallback onTap;
  @override State<_ConnChip> createState() => _ConnChipState();
}

class _ConnChipState extends State<_ConnChip> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  StreamSubscription<int>? _latSub;
  StreamSubscription<DeviceReading>? _devSub;
  StreamSubscription<int?>? _playerSub;
  int? _latency;
  int? _player;
  DeviceReading? _dev;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _latency = WebSocketService.instance.latencyMs;
    _latSub  = WebSocketService.instance.latencyStream.listen((ms) {
      if (mounted) setState(() => _latency = ms);
    });
    _player    = WebSocketService.instance.playerNumber;
    _playerSub = WebSocketService.instance.playerStream.listen((p) {
      if (mounted) setState(() => _player = p);
    });
    _dev    = DeviceStats.instance.last;
    _devSub = DeviceStats.instance.stream.listen((r) {
      if (mounted) setState(() => _dev = r);
    });
  }

  @override
  void dispose() {
    _latSub?.cancel(); _devSub?.cancel(); _playerSub?.cancel();
    _pulse.dispose(); super.dispose();
  }

  Color _latColor(int ms) {
    if (ms < 40) return const Color(0xFF1DB954);
    if (ms < 90) return const Color(0xFFF9A825);
    return const Color(0xFFE53935);
  }

  Color _heatColor(double c) {
    if (c < 38) return const Color(0xFF1DB954);
    if (c < 43) return const Color(0xFFF9A825);
    return const Color(0xFFE53935);
  }

  Color _battColor(int p) =>
      p <= 15 ? const Color(0xFFE53935) : Colors.white60;

  Widget _sep() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 6),
    child: Text('•', style: TextStyle(color: Colors.white24, fontSize: 11)),
  );

  Widget _stat(String text, Color color, {FontWeight w = FontWeight.normal}) =>
      Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: w));



  @override
  Widget build(BuildContext context) {
    final connected = widget.state == ws.ConnectionState.connected;
    final mismatch = WebSocketService.instance.versionMismatch;
    Color dotColor; String label; Color labelColor = Colors.white60;

    if (connected) {
      if (mismatch) {
        dotColor = const Color(0xFFE53935);
        label = 'Version Mismatch';
        labelColor = dotColor;
      } else if (_latency != null) {
        dotColor   = _latColor(_latency!);
        final showP = _player != null && WebSocketService.instance.connectedPlayers > 1;
        label      = showP ? 'P$_player • ${_latency}ms' : '${_latency}ms';
        labelColor = dotColor;
      } else {
        dotColor = const Color(0xFF1DB954); 
        final showP = _player != null && WebSocketService.instance.connectedPlayers > 1;
        label = showP ? 'P$_player • Connected' : 'Connected';
      }
    } else if (widget.state == ws.ConnectionState.connecting) {
      dotColor = const Color(0xFFF9A825); label = 'Connecting';
    } else {
      dotColor = const Color(0xFFE53935);
      label = WebSocketService.instance.serverFull ? 'Server full' : 'Offline';
    }

    final dot = Container(
      width: 7, height: 7,
      decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
    );

    final dev = _dev;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x99000000),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12, width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [

          widget.state == ws.ConnectionState.connecting
              ? FadeTransition(opacity: _pulse, child: dot)
              : dot,
          const SizedBox(width: 6),
          _stat(label, labelColor,
              w: connected && _latency != null ? FontWeight.w600 : FontWeight.normal),
          if (dev != null && dev.hasTemp) ...[
            _sep(),
            _stat('${dev.tempC.toStringAsFixed(0)}°', _heatColor(dev.tempC)),
          ],
          if (dev != null && dev.hasBattery) ...[
            _sep(),
            _stat('${dev.battery}%', _battColor(dev.battery)),
          ],
        ]),
      ),
    );
  }
}

class _SettingsBtn extends StatelessWidget {
  const _SettingsBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: const Icon(Icons.settings, color: Colors.white60, size: 16),
    ),
  );
}

// ── Stream toggle button (top bar) ───────────────────────────────────────────
class _StreamBtn extends StatelessWidget {
  const _StreamBtn({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0x3300D4FF) : const Color(0x99000000),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? const Color(0xFF00D4FF) : Colors.white12,
          width: 1,
        ),
      ),
      child: Icon(
        Icons.cast,
        color: active ? const Color(0xFF00D4FF) : Colors.white60,
        size: 16,
      ),
    ),
  );
}

// ── Games tab (top bar) ───────────────────────────────────────────────────────

class _GamesBtn extends StatelessWidget {
  const _GamesBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: const Color(0xFF00D4FF), size: 14),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70, fontSize: 9,
              fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.expand_more, color: Colors.white38, size: 13),
      ]),
    ),
  );
}

// ── Game picker overlay ───────────────────────────────────────────────────────

class _GamePicker extends StatelessWidget {
  const _GamePicker({
    required this.currentId,
    required this.customLayouts,
    required this.onPick,
    required this.onNew,
    required this.onEdit,
    required this.onDelete,
    required this.onCustomize,
    required this.onClose,
  });
  final String currentId;
  final List<CustomLayout> customLayouts;
  final ValueChanged<String> onPick;
  final VoidCallback onNew;
  final ValueChanged<CustomLayout> onEdit;
  final ValueChanged<CustomLayout> onDelete;
  final ValueChanged<String> onCustomize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final sz = MediaQuery.of(context).size;
    return Stack(children: [
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: onClose,
        child: const SizedBox.expand())),
      Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.95 + (0.05 * t), child: child),
          ),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: (sz.width * 0.85).clamp(360.0, 820.0),
              constraints: BoxConstraints(maxHeight: (sz.height * 0.85).clamp(200.0, 600.0)),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF24243A)),
                boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 4),
                  child: Row(children: [
                    const Icon(Icons.apps_rounded, color: Color(0xFF00D4FF), size: 22),
                    const SizedBox(width: 10),
                    const Text('Game Layouts Library', style: TextStyle(
                      color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    GestureDetector(
                      onTap: onClose,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Color(0xFF1A1A24)),
                        child: const Icon(Icons.close, color: Colors.white54, size: 16),
                      ),
                    ),
                  ]),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Pick a layout from the library, or build your own custom layout from scratch.',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
                    child: Wrap(
                      spacing: 12, runSpacing: 12, alignment: WrapAlignment.center,
                      children: [
                        for (final p in kGameProfiles.where((p) => !p.comingSoon))
                          _GameCard(profile: p, selected: p.id == currentId,
                            onTap: () => onPick(p.id),
                            onCustomize: (p.id == 'standard' || p.id == 'forza' || p.id == 'spiderman' || p.id == 'overcooked')
                                ? () => onCustomize(p.id) : null),
                        for (final l in customLayouts)
                          _CustomCard(
                            layout: l,
                            selected: currentId == 'custom:${l.id}',
                            onTap: () => onPick('custom:${l.id}'),
                            onEdit: () => onEdit(l),
                            onDelete: () => onDelete(l),
                          ),
                        _NewCard(onTap: onNew),
                        for (final p in kGameProfiles.where((p) => p.comingSoon))
                          _GameCard(profile: p, selected: false, onTap: null),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.profile, required this.selected, this.onTap, this.onCustomize});
  final GameProfile profile;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onCustomize;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00D4FF);
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: profile.comingSoon ? 0.45 : 1.0,
        child: Container(
          width: 160, height: 160,
          decoration: BoxDecoration(
            color: selected ? const Color(0x1A00D4FF) : const Color(0xFF161622),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent : const Color(0xFF2C2C40),
              width: selected ? 2 : 1,
            ),
          ),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(profile.icon, color: selected ? accent : Colors.white, size: 44),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(profile.tagline, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ]),
                ],
              ),
            ),
            if (onCustomize != null)
              Positioned(top: 8, right: 8, child: GestureDetector(
                onTap: onCustomize,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF24243A)),
                  child: const Icon(Icons.tune, size: 16, color: Colors.white70),
                ),
              )),
            if (selected && onCustomize == null)
              const Positioned(bottom: 10, right: 10,
                child: Icon(Icons.check_circle, color: accent, size: 20)),
            if (profile.comingSoon)
              Positioned(top: 10, right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C40), borderRadius: BorderRadius.circular(8)),
                  child: const Text('SOON', style: TextStyle(
                    color: Colors.white54, fontSize: 9,
                    fontWeight: FontWeight.bold, letterSpacing: 1)),
                )),
          ]),
        ),
      ),
    );
  }
}

class _CustomCard extends StatelessWidget {
  const _CustomCard({
    required this.layout, required this.selected,
    required this.onTap, required this.onEdit, required this.onDelete,
  });
  final CustomLayout layout;
  final bool selected;
  final VoidCallback onTap, onEdit, onDelete;

  Widget _mini(IconData i, VoidCallback onTap, {Color color = Colors.white54}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1A1A24)),
          child: Icon(i, size: 14, color: color),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00D4FF);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160, height: 160,
        decoration: BoxDecoration(
          color: selected ? const Color(0x1A00D4FF) : const Color(0xFF161622),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? accent : const Color(0xFF2C2C40), width: selected ? 2 : 1),
        ),
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(Icons.tune, color: selected ? accent : Colors.white, size: 40),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(layout.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('${layout.items.length} controls · custom',
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ]),
              ],
            ),
          ),
          Positioned(top: 8, right: 8, child: Row(children: [
            _mini(Icons.edit, onEdit),
            const SizedBox(width: 6),
            _mini(Icons.delete_outline, onDelete, color: const Color(0xFFE53935)),
          ])),
          if (selected)
            const Positioned(bottom: 10, right: 10,
              child: Icon(Icons.check_circle, color: accent, size: 20)),
        ]),
      ),
    );
  }
}

class _NewCard extends StatelessWidget {
  const _NewCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 160, height: 160,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E44), width: 1.5),
      ),
      child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.add_circle_outline, color: Color(0xFF00D4FF), size: 36),
        SizedBox(height: 12),
        Text('New Layout', style: TextStyle(
          color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
        SizedBox(height: 4),
        Text('Build your own', style: TextStyle(color: Colors.white38, fontSize: 11)),
      ]),
    ),
  );
}

class _TemplatePicker extends StatelessWidget {
  const _TemplatePicker({required this.onPick});
  final ValueChanged<String> onPick;

  Widget _opt(IconData icon, String title, String sub, String tpl) => GestureDetector(
    onTap: () => onPick(tpl),
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12121C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF24243A)),
      ),
      child: Row(children: [
        Icon(icon, color: const Color(0xFF00D4FF), size: 26),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ])),
        const Icon(Icons.chevron_right, color: Colors.white24),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(20),
    child: Container(
      width: 380,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF20202C)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('START FROM', style: TextStyle(
          color: Color(0xFF00D4FF), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 14),
        _opt(Icons.crop_square, 'Blank canvas', 'Start empty', 'blank'),
        _opt(Icons.sports_esports, 'Gamepad starter', 'ABXY, sticks, bumpers, D-pad', 'gamepad'),
        _opt(Icons.keyboard, 'Keyboard + Mouse', 'WASD, mouse pad, clicks', 'kbm'),
      ]),
    ),
  );
}

// ── Games quick-switch dropdown (from the top-bar pill) ───────────────────────

class _GamesDropdown extends StatelessWidget {
  const _GamesDropdown({
    required this.currentId,
    required this.customLayouts,
    required this.onPick,
    required this.onNew,
    required this.onMore,
    required this.onEditCurrent,
    required this.onDeleteCurrent,
    required this.onClose,
  });
  final String currentId;
  final List<CustomLayout> customLayouts;
  final ValueChanged<String> onPick;
  final VoidCallback onNew, onMore, onEditCurrent, onDeleteCurrent, onClose;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final sz  = MediaQuery.of(context).size;
    return Stack(children: [
      // tap-outside to dismiss
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: onClose,
        child: const SizedBox.expand())),
      Positioned(
        top: top + 42, right: 10,
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
            child: Container(
              width: 196,
              // Always fit the visible (landscape) screen — never run off-screen.
              constraints: BoxConstraints(maxHeight: (sz.height - top - 54).clamp(140.0, sz.height)),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF24243A)),
                boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 9, 12, 3),
                  child: Align(alignment: Alignment.centerLeft,
                    child: Text('SWITCH LAYOUT', style: TextStyle(
                      color: Colors.white38, fontSize: 9,
                      fontWeight: FontWeight.bold, letterSpacing: 1.8))),
                ),
                Flexible(child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final p in kGameProfiles.where((p) => !p.comingSoon))
                      _row(p.icon, p.name, currentId == p.id, () => onPick(p.id),
                          onEdit: currentId == p.id ? onEditCurrent : null),
                    for (final l in customLayouts)
                      _row(Icons.tune, l.name, currentId == 'custom:${l.id}',
                          () => onPick('custom:${l.id}'),
                          onEdit: currentId == 'custom:${l.id}' ? onEditCurrent : null,
                          onDelete: currentId == 'custom:${l.id}' ? onDeleteCurrent : null),
                  ]),
                )),
                const Divider(height: 1, color: Color(0xFF20202C)),
                _row(Icons.add_circle_outline, 'New layout', false, onNew, accentIcon: true),
                _row(Icons.grid_view_rounded, 'All layouts & more', false, onMore, accentIcon: true),
                const SizedBox(height: 4),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _row(IconData icon, String label, bool active, VoidCallback onTap,
      {bool accentIcon = false, VoidCallback? onEdit, VoidCallback? onDelete}) {
    const accent = Color(0xFF00D4FF);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: active ? const Color(0x1400D4FF) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Icon(icon, size: 16, color: active || accentIcon ? accent : Colors.white70),
          const SizedBox(width: 10),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? accent : Colors.white, fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal))),
          if (active && onEdit == null) const Icon(Icons.check, size: 15, color: accent),
          if (active && onEdit != null) ...[
            GestureDetector(
              onTap: onEdit,
              child: const Icon(Icons.edit_outlined, size: 16, color: accent),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onDelete,
                child: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
              ),
            ],
          ],
        ]),
      ),
    );
  }
}

// ── First-time steering chooser (Forza) ───────────────────────────────────────

class _SteerChooser extends StatelessWidget {
  const _SteerChooser({
    required this.onPick,
    this.title = 'CHOOSE YOUR STEERING',
    this.subtitle = 'How do you want to steer in Forza?\nYou can change this anytime in Settings.',
    this.onClose,
  });
  final ValueChanged<String> onPick;
  final String title;
  final String subtitle;
  final VoidCallback? onClose; // tap-outside to dismiss (null = forced choice)

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose ?? () {},
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: Center(
          // Absorb taps on the card so only taps on the backdrop dismiss.
          child: GestureDetector(
            onTap: () {},
            child: Container(
            width: (w * 0.92).clamp(360.0, 760.0),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF20202C)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: const TextStyle(
                color: Color(0xFF00D4FF), fontSize: 12,
                fontWeight: FontWeight.bold, letterSpacing: 2.5)),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12, runSpacing: 12,
                children: [
                  _SteerOption(icon: Icons.trip_origin, title: 'WHEEL',
                    sub: 'Drag a wheel\nsmooth & precise', onTap: () => onPick('wheel')),
                  _SteerOption(icon: Icons.tune, title: 'SLIDER',
                    sub: 'Slide a knob\nhands stay put', onTap: () => onPick('slider')),
                  _SteerOption(icon: Icons.screen_rotation, title: 'TILT',
                    sub: 'Tilt the phone\nlike a wheel', onTap: () => onPick('tilt')),
                  _SteerOption(icon: Icons.swap_horiz, title: 'L / R PADS',
                    sub: 'Tap arrows\nsimple & arcade', onTap: () => onPick('pads')),
                ],
              ),
            ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _SteerOption extends StatelessWidget {
  const _SteerOption({required this.icon, required this.title, required this.sub, required this.onTap});
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 152,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF12121C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF24243A)),
      ),
      child: Column(children: [
        Icon(icon, color: const Color(0xFF00D4FF), size: 42),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(
          color: Colors.white, fontSize: 15,
          fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 6),
        Text(sub, textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.3)),
      ]),
    ),
  );
}

// ── Tutorial overlay (first launch) ──────────────────────────────────────────

class _TutorialOverlay extends StatefulWidget {
  const _TutorialOverlay({required this.onDismiss});
  final VoidCallback onDismiss;
  @override State<_TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<_TutorialOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, value: 1.0,
        duration: const Duration(milliseconds: 600));
    Future.delayed(const Duration(seconds: 3), _dismiss);
  }
  @override void dispose() { _fade.dispose(); super.dispose(); }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _fade.reverse();
    if (mounted) widget.onDismiss();
  }

  Widget _half(String title, String sub, IconData icon, Alignment align) =>
    Align(alignment: align, child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: align == Alignment.centerLeft
            ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.45), size: 34),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.3),
              fontSize: 10, letterSpacing: 0.5)),
        ],
      ),
    ));

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: GestureDetector(
      onTap: _dismiss,
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Stack(children: [
          // Vertical divider
          Center(child: Container(width: 1, color: Colors.white.withValues(alpha: 0.1))),
          // Left label
          _half('MOVE', 'touch anywhere → stick spawns',
              Icons.touch_app, Alignment.centerLeft),
          // Right label
          _half('CAMERA', 'touch anywhere → stick spawns',
              Icons.touch_app, Alignment.centerRight),
          // Bottom hint
          Align(alignment: Alignment.bottomCenter, child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Text('tap to dismiss',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 10)),
          )),
        ]),
      ),
    ),
  );
}

// ── IP dialog ─────────────────────────────────────────────────────────────────

class _IpDialog extends StatefulWidget {
  const _IpDialog();
  @override State<_IpDialog> createState() => _IpDialogState();
}

class _IpDialogState extends State<_IpDialog> {
  final _ctrl = TextEditingController();
  late StreamSubscription<ws.ConnectionState> _sub;
  Timer? _refresh;
  ws.ConnectionState _conn = WebSocketService.instance.state;

  @override
  void initState() {
    super.initState();
    _sub = WebSocketService.instance.stateStream.listen((s) {
      setState(() => _conn = s);
      if (s == ws.ConnectionState.connected) {
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });
    // Keep diagnostics (discovered IP, candidates) live while it searches.
    _refresh = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() { _sub.cancel(); _refresh?.cancel(); _ctrl.dispose(); super.dispose(); }

  void _connect() {
    final ip = _ctrl.text.trim();
    if (ip.isNotEmpty) WebSocketService.instance.setManualIp(ip);
  }

  Widget _diagRow(String label, String value, {Color? valueColor}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 62, child: Text(label,
        style: const TextStyle(color: Colors.white38, fontSize: 11))),
      Expanded(child: Text(value, style: TextStyle(
        color: valueColor ?? Colors.white70, fontSize: 11, fontWeight: FontWeight.w500))),
    ]),
  );

  Widget _label(String text) => Text(text, style: const TextStyle(
    color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.8));

  @override
  Widget build(BuildContext context) {
    final svc        = WebSocketService.instance;
    final connected  = _conn == ws.ConnectionState.connected;
    final connecting = _conn == ws.ConnectionState.connecting;
    final statusColor = connected
        ? const Color(0xFF1DB954)
        : connecting ? const Color(0xFFF9A825) : const Color(0xFFE53935);
    final statusText = connected ? 'Connected'
        : connecting ? 'Connecting…' : 'Not connected';

    final sz         = MediaQuery.of(context).size;
    final found      = svc.discoveredIp;
    final candidates = svc.candidateIps;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 360,
        constraints: BoxConstraints(maxHeight: sz.height * 0.92),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF252535)),
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header with live status
            Row(children: [
              const Text('CONNECTION', style: TextStyle(
                color: Colors.white, fontSize: 12,
                fontWeight: FontWeight.bold, letterSpacing: 2.5)),
              const Spacer(),
              Container(width: 8, height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor)),
              const SizedBox(width: 6),
              Text(statusText, style: TextStyle(color: statusColor, fontSize: 11)),
            ]),
            const SizedBox(height: 16),

            // Diagnostics
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF15151F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF222232)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _diagRow('Found PC', found ?? (connecting ? 'searching…' : 'not found yet'),
                    valueColor: found != null ? const Color(0xFF00D4FF) : Colors.white38),
                _diagRow('Trying', candidates.isEmpty ? '—' : candidates.join('   ·   ')),
                if (svc.serverVersion != null) _diagRow('Server', 'v${svc.serverVersion}', 
                  valueColor: svc.versionMismatch ? const Color(0xFFE53935) : null),
              ]),
            ),
            if (svc.versionMismatch) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0x33E53935),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x88E53935)),
                ),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFE53935), size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Version mismatch! Please download the correct v1.0.0 server.',
                    style: TextStyle(color: Color(0xFFE53935), fontSize: 11)
                  )),
                ]),
              ),
            ],
            const SizedBox(height: 14),



            _label('OR ENTER PC IP MANUALLY'),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSubmitted: (_) => _connect(),
              decoration: InputDecoration(
                hintText: '192.168.1.42',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF15151F),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF252535))),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF00D4FF))),
              ),
            ),
            const SizedBox(height: 14),

            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () => WebSocketService.instance.reconnect(),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Rescan'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00D4FF),
                  side: const BorderSide(color: Color(0xFF00D4FF)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                onPressed: _connect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D4FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Connect',
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              )),
            ]),
          ]),
        ),
      ),
    );
  }
}
