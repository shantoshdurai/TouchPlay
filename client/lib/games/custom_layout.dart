import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The kinds of control a user can drop onto a custom layout.
/// The `steer*` kinds are the alternate Forza steering styles, now editable just
/// like the wheel: a drag slider, a phone-tilt indicator, and tap L/R pads.
enum ControlKind {
  button, stick, trigger, dpad, mousepad, wheel, pedal,
  steerSlider, steerTilt, steerPad,
  swing, // Spider-Man: hold = RT web-swing, drag down + release = Space boost
}

/// One placed control. Position is stored as a fraction of the screen so a
/// layout looks the same on any device/resolution.
class ControlItem {
  ControlItem({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.size,
    this.action = '',
    this.label = '',
    this.icon = '',
    this.opacity = 1.0,
  });

  String id;
  ControlKind kind;
  double x;        // center X, 0..1 of screen width
  double y;        // center Y, 0..1 of screen height
  double size;     // footprint in logical px
  String action;   // encoded binding — see actionLabel() below
  String label;    // optional override text
  String icon;     // optional icon key — see kIconRegistry below ('' = none)
  double opacity;  // 0..1 — Free-Fire-style per-control transparency

  ControlItem copy() => ControlItem(
      id: id, kind: kind, x: x, y: y, size: size,
      action: action, label: label, icon: icon, opacity: opacity);

  Map<String, dynamic> toJson() => {
        'id': id, 'kind': kind.name, 'x': x, 'y': y,
        'size': size, 'action': action, 'label': label,
        'icon': icon, 'opacity': opacity,
      };

  factory ControlItem.fromJson(Map<String, dynamic> j) => ControlItem(
        id: j['id'] as String,
        kind: ControlKind.values.byName(j['kind'] as String),
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        size: (j['size'] as num).toDouble(),
        action: (j['action'] ?? '') as String,
        label: (j['label'] ?? '') as String,
        icon: (j['icon'] ?? '') as String,
        opacity: ((j['opacity'] ?? 1.0) as num).toDouble(),
      );
}

/// Stable string-keyed icon table. We store a *key* (not a raw codepoint) so the
/// release build's icon tree-shaker keeps these glyphs — constructing IconData
/// from a dynamic codepoint would strip them and show blank squares. Add new
/// preset icons here; the editor falls back to text for keys it doesn't know.
const Map<String, IconData> kIconRegistry = {
  // Forza HUD
  'gas':     Icons.local_gas_station,
  'brake':   Icons.front_hand,
  'hbrake':  Icons.local_parking,
  'cam':     Icons.cameraswitch,
  'rewind':  Icons.replay,
  'horn':    Icons.campaign,
  'select':  Icons.check,
  'close':   Icons.close,
  'map':     Icons.map,
  'anna':    Icons.assistant,
  'photo':   Icons.photo_camera,
  'pause':   Icons.pause,
  // Spider-Man 2
  'jump':    Icons.keyboard_double_arrow_up,
  'attack':  Icons.sports_mma,
  'dodge':   Icons.directions_run,
  'wings':   Icons.paragliding,
  'gadget':  Icons.adjust,
  'ability': Icons.auto_awesome,
  'heal':    Icons.healing,
  'zip':     Icons.gps_fixed,
  'aim':     Icons.center_focus_strong,
};

class CustomLayout {
  CustomLayout({
    required this.id,
    required this.name,
    required this.items,
    this.floatingSticks = false,
  });

  String id;
  String name;
  List<ControlItem> items;

  /// When true, the left/right screen halves are the Standard "Xbox" floating
  /// sticks — fixed, full-half analog sticks that are NOT placed/editable items.
  /// Play mode renders them automatically; the editor shows them as locked hints
  /// (you can't move, resize, or delete them).
  bool floatingSticks;

  CustomLayout copy() => CustomLayout(
      id: id, name: name, floatingSticks: floatingSticks,
      items: items.map((e) => e.copy()).toList());

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'floatingSticks': floatingSticks,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory CustomLayout.fromJson(Map<String, dynamic> j) => CustomLayout(
        id: j['id'] as String,
        name: j['name'] as String,
        floatingSticks: (j['floatingSticks'] ?? false) as bool,
        items: (j['items'] as List)
            .map((e) => ControlItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── Binding helpers ──────────────────────────────────────────────────────────
// Encoded action strings:
//   gp:A gp:B gp:X gp:Y gp:LB gp:RB gp:LS gp:RS gp:START gp:BACK gp:GUIDE
//   gp:DPAD_UP/DOWN/LEFT/RIGHT      key:W key:SPACE …      mouse:left mouse:right
//   stick:left stick:right         trig:left trig:right    (dpad/mousepad: none)

String actionLabel(String action) {
  if (action.startsWith('gp:')) {
    switch (action.substring(3)) {
      case 'DPAD_UP': return '↑';
      case 'DPAD_DOWN': return '↓';
      case 'DPAD_LEFT': return '←';
      case 'DPAD_RIGHT': return '→';
      default: return action.substring(3);
    }
  }
  if (action.startsWith('key:')) return action.substring(4);
  if (action == 'mouse:left') return 'LMB';
  if (action == 'mouse:right') return 'RMB';
  if (action == 'stick:left') return 'L-STICK';
  if (action == 'stick:right') return 'R-STICK';
  if (action == 'trig:left') return 'LT';
  if (action == 'trig:right') return 'RT';
  if (action == 'wheel') return 'WHEEL';
  if (action == 'steer:slider') return 'SLIDER';
  if (action == 'steer:tilt') return 'TILT';
  if (action == 'steerpad:left') return 'STEER ◄';
  if (action == 'steerpad:right') return 'STEER ►';
  if (action == 'swing') return 'SWING';
  if (action == 'pedal:gas') return 'GAS';
  if (action == 'pedal:brake') return 'BRAKE';
  if (action == 'combo:zip') return 'ZIP';   // L2+R2 — Spider-Man point launch
  return action;
}

IconData kindIcon(ControlKind k) {
  switch (k) {
    case ControlKind.button: return Icons.radio_button_unchecked;
    case ControlKind.stick: return Icons.gamepad;
    case ControlKind.trigger: return Icons.expand_circle_down;
    case ControlKind.dpad: return Icons.control_camera;
    case ControlKind.mousepad: return Icons.mouse;
    case ControlKind.wheel: return Icons.trip_origin;
    case ControlKind.pedal: return Icons.local_gas_station;
    case ControlKind.steerSlider: return Icons.tune;
    case ControlKind.steerTilt: return Icons.screen_rotation;
    case ControlKind.steerPad: return Icons.swap_horiz;
    case ControlKind.swing: return Icons.filter_tilt_shift;
  }
}

String kindName(ControlKind k) {
  switch (k) {
    case ControlKind.button: return 'Button';
    case ControlKind.stick: return 'Stick';
    case ControlKind.trigger: return 'Trigger';
    case ControlKind.dpad: return 'D-Pad';
    case ControlKind.mousepad: return 'Mouse pad';
    case ControlKind.wheel: return 'Steering wheel';
    case ControlKind.pedal: return 'Pedal';
    case ControlKind.steerSlider: return 'Steering slider';
    case ControlKind.steerTilt: return 'Steering tilt';
    case ControlKind.steerPad: return 'Steer pad';
    case ControlKind.swing: return 'Swing';
  }
}

double defaultSize(ControlKind k) {
  switch (k) {
    case ControlKind.button: return 64;
    case ControlKind.stick: return 150;
    case ControlKind.trigger: return 64;
    case ControlKind.dpad: return 130;
    case ControlKind.mousepad: return 240;
    case ControlKind.wheel: return 230;
    case ControlKind.pedal: return 110;
    case ControlKind.steerSlider: return 300;
    case ControlKind.steerTilt: return 240;
    case ControlKind.steerPad: return 96;
    case ControlKind.swing: return 92;
  }
}

String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

ControlItem newControl(ControlKind kind, {String action = ''}) => ControlItem(
      id: _newId(),
      kind: kind,
      x: 0.5,
      y: 0.5,
      size: defaultSize(kind),
      action: action.isNotEmpty
          ? action
          : kind == ControlKind.button ? 'gp:A'
          : kind == ControlKind.wheel ? 'wheel'
          : kind == ControlKind.steerSlider ? 'steer:slider'
          : kind == ControlKind.steerTilt ? 'steer:tilt'
          : kind == ControlKind.steerPad ? 'steerpad:left'
          : kind == ControlKind.swing ? 'swing'
          : kind == ControlKind.pedal ? 'pedal:gas'
          : '',
    );

// ── Templates (head-start layouts) ───────────────────────────────────────────

CustomLayout newLayoutFromTemplate(String template) {
  final id = _newId();
  switch (template) {
    case 'gamepad':
      return CustomLayout(id: id, name: 'My Gamepad', items: _gamepadTemplate());
    case 'kbm':
      return CustomLayout(id: id, name: 'My Keyboard+Mouse', items: _kbmTemplate());
    default:
      return CustomLayout(id: id, name: 'My Layout', items: []);
  }
}

ControlItem _b(ControlKind k, double x, double y, String action, double size,
        [String label = '', String icon = '']) =>
    ControlItem(id: _newId(), kind: k, x: x, y: y, size: size,
        action: action, label: label, icon: icon);

List<ControlItem> _gamepadTemplate() => [
      _b(ControlKind.stick, 0.15, 0.70, 'stick:left', 150),
      _b(ControlKind.stick, 0.85, 0.70, 'stick:right', 150),
      _b(ControlKind.dpad, 0.15, 0.34, '', 130),
      // ABXY diamond (right)
      _b(ControlKind.button, 0.86, 0.26, 'gp:Y', 62),
      _b(ControlKind.button, 0.80, 0.40, 'gp:X', 62),
      _b(ControlKind.button, 0.92, 0.40, 'gp:B', 62),
      _b(ControlKind.button, 0.86, 0.54, 'gp:A', 62),
      // bumpers + triggers
      _b(ControlKind.button, 0.07, 0.12, 'gp:LB', 56),
      _b(ControlKind.button, 0.93, 0.12, 'gp:RB', 56),
      _b(ControlKind.trigger, 0.16, 0.12, 'trig:left', 56),
      _b(ControlKind.trigger, 0.84, 0.12, 'trig:right', 56),
      // center
      _b(ControlKind.button, 0.44, 0.10, 'gp:BACK', 48),
      _b(ControlKind.button, 0.56, 0.10, 'gp:START', 48),
    ];

List<ControlItem> _kbmTemplate() => [
      // WASD
      _b(ControlKind.button, 0.14, 0.44, 'key:W', 66),
      _b(ControlKind.button, 0.08, 0.64, 'key:A', 66),
      _b(ControlKind.button, 0.14, 0.64, 'key:S', 66),
      _b(ControlKind.button, 0.20, 0.64, 'key:D', 66),
      _b(ControlKind.button, 0.14, 0.84, 'key:SPACE', 78),
      // common action keys
      _b(ControlKind.button, 0.30, 0.40, 'key:R', 58),
      _b(ControlKind.button, 0.30, 0.56, 'key:E', 58),
      _b(ControlKind.button, 0.30, 0.72, 'key:F', 58),
      _b(ControlKind.button, 0.05, 0.40, 'key:SHIFT', 58),
      _b(ControlKind.button, 0.05, 0.22, 'key:CTRL', 58),
      // mouse look + clicks (right side)
      _b(ControlKind.mousepad, 0.80, 0.50, '', 260),
      _b(ControlKind.button, 0.66, 0.82, 'mouse:left', 64),
      _b(ControlKind.button, 0.94, 0.82, 'mouse:right', 64),
    ];

/// Build an editable copy of the built-in **Standard** gamepad layout so the
/// user can rearrange / resize / fade it like any custom layout. (The floating
/// sticks become fixed sticks — placed controls, by nature.)
CustomLayout cloneStandard() => CustomLayout(
      id: _newId(),
      name: 'My Standard',
      // Left/right halves are the fixed Xbox sticks — not editable items, so they
      // never show in the editor. Everything else below is fully customizable.
      floatingSticks: true,
      items: [
        _b(ControlKind.dpad, 0.16, 0.42, '', 130),
        // ABXY diamond (right)
        _b(ControlKind.button, 0.86, 0.30, 'gp:Y', 62),
        _b(ControlKind.button, 0.80, 0.44, 'gp:X', 62),
        _b(ControlKind.button, 0.92, 0.44, 'gp:B', 62),
        _b(ControlKind.button, 0.86, 0.58, 'gp:A', 62),
        // bumpers + triggers
        _b(ControlKind.button, 0.07, 0.22, 'gp:LB', 56),
        _b(ControlKind.button, 0.93, 0.22, 'gp:RB', 56),
        _b(ControlKind.trigger, 0.16, 0.22, 'trig:left', 56),
        _b(ControlKind.trigger, 0.84, 0.22, 'trig:right', 56),
        // stick clicks + center
        _b(ControlKind.button, 0.34, 0.88, 'gp:LS', 50),
        _b(ControlKind.button, 0.66, 0.88, 'gp:RS', 50),
        _b(ControlKind.button, 0.45, 0.20, 'gp:BACK', 46),
        _b(ControlKind.button, 0.55, 0.20, 'gp:START', 46),
      ],
    );

/// Editable copy of the **Forza** layout. [steer] picks which steering control
/// is dropped in — 'wheel' | 'slider' | 'tilt' | 'pads' — so the editor opens
/// with the steering style you actually use, all movable / resizable.
CustomLayout cloneForza([String steer = 'wheel']) {
  // The steering control(s) for the chosen style — placed bottom-left.
  final steering = <ControlItem>[
    if (steer == 'slider')
      _b(ControlKind.steerSlider, 0.24, 0.84, 'steer:slider', 300)
    else if (steer == 'tilt')
      _b(ControlKind.steerTilt, 0.17, 0.80, 'steer:tilt', 240)
    else if (steer == 'pads') ...[
      _b(ControlKind.steerPad, 0.09, 0.80, 'steerpad:left', 96),
      _b(ControlKind.steerPad, 0.23, 0.80, 'steerpad:right', 96),
    ]
    else
      _b(ControlKind.wheel, 0.17, 0.66, 'wheel', 230),
  ];

  const labels = {'wheel': 'Wheel', 'slider': 'Slider', 'tilt': 'Tilt', 'pads': 'Pads'};
  return CustomLayout(
    id: _newId(),
    name: 'My Forza · ${labels[steer] ?? 'Wheel'}',
    // Mirror the built-in racing HUD exactly — same positions, sizes, labels and
    // icons — so "Customize" opens with the real layout, not a stripped-down copy.
    items: [
      ...steering,
      // Pedals (bottom-right): GAS=RT, BRAKE=LT
      _b(ControlKind.pedal, 0.90, 0.70, 'pedal:gas',   100, 'GAS',   'gas'),
      _b(ControlKind.pedal, 0.77, 0.74, 'pedal:brake',  92, 'BRAKE', 'brake'),
      // Handbrake (drift) = A, just left of the pedals
      _b(ControlKind.button, 0.66, 0.78, 'gp:A', 64, 'HBRAKE', 'hbrake'),
      // Secondary cluster (upper-right): CAM=RB, REWIND=Y, HORN=RS
      _b(ControlKind.button, 0.78, 0.22, 'gp:RB', 56, 'CAM',    'cam'),
      _b(ControlKind.button, 0.86, 0.22, 'gp:Y',  56, 'REWIND', 'rewind'),
      _b(ControlKind.button, 0.93, 0.22, 'gp:RS', 56, 'HORN',   'horn'),
      // Menu cluster (upper-left): SELECT=A, BACK=B (answer in-game prompts)
      _b(ControlKind.button, 0.07, 0.22, 'gp:A', 56, 'SELECT', 'select'),
      _b(ControlKind.button, 0.14, 0.22, 'gp:B', 56, 'BACK',   'close'),
      // Top-center utility (icon-only): MAP, ANNA, PHOTO, PAUSE
      _b(ControlKind.button, 0.40, 0.10, 'gp:BACK',      46, '', 'map'),
      _b(ControlKind.button, 0.47, 0.10, 'gp:DPAD_DOWN', 46, '', 'anna'),
      _b(ControlKind.button, 0.53, 0.10, 'gp:DPAD_UP',   46, '', 'photo'),
      _b(ControlKind.button, 0.60, 0.10, 'gp:START',     46, '', 'pause'),
    ],
  );
}

/// Editable **Marvel's Spider-Man 2** layout — mapped to the game's real
/// *controller* scheme (the game shows Xbox prompts), so every control sends a
/// gamepad input the game actually reads. PlayStation → Xbox:
///   Swing/sprint/wall-run = hold R2 (RT) · Jump = ✕ (A) · Attack = □ (X)
///   Dodge = ◯ (B) · Web Wings / Yank = △ (Y) · Gadget = R1 (RB)
///   Ability/suit power = L1 (LB) · Heal = D-pad Down · Aim = L2 (LT)
///   Zip / Point Launch = L2 + R2 (LT+RT combo)
///
/// Left half  = floating MOVE stick. Right half = floating CAMERA stick (active
/// anywhere outside a placed button). Earlier builds bound Wings/Zip to keyboard
/// keys (F / C) which do nothing while the game is in controller mode — fixed.
CustomLayout cloneSpiderman() => CustomLayout(
      id: _newId(),
      name: 'My Spider-Man 2',
      floatingSticks: true,
      items: [
        // ── SWING: the hero control ────────────────────────────────────────
        // Hold = RT (web-swing fires). Drag while held = right-stick camera.
        _b(ControlKind.swing, 0.70, 0.53, 'swing', 92),

        // ── ABXY face buttons — to the right of SWING ─────────────────────
        _b(ControlKind.button, 0.91, 0.28, 'gp:Y', 60, 'WINGS',  'wings'),  // △ web wings / yank
        _b(ControlKind.button, 0.95, 0.50, 'gp:B', 60, 'DODGE',  'dodge'),  // ◯ dodge/evade
        _b(ControlKind.button, 0.91, 0.72, 'gp:A', 60, 'JUMP',   'jump'),   // ✕ jump
        _b(ControlKind.button, 0.84, 0.50, 'gp:X', 60, 'ATTACK', 'attack'), // □ melee attack

        // ── Right shoulder — R1 gadget / web-shooter ──────────────────────
        _b(ControlKind.button, 0.82, 0.24, 'gp:RB', 54, 'GADGET', 'gadget'),

        // ── Traversal extras (bottom-center) ──────────────────────────────
        _b(ControlKind.button, 0.60, 0.80, 'combo:zip',     58, 'ZIP',  'zip'),  // L2+R2 point launch
        _b(ControlKind.button, 0.52, 0.86, 'gp:DPAD_DOWN',  52, 'HEAL', 'heal'), // D-pad down heal

        // ── Left side: aim (L2) + ability (L1) ────────────────────────────
        _b(ControlKind.trigger, 0.14, 0.16, 'trig:left', 58, 'AIM'),              // L2 web-shooter aim
        _b(ControlKind.button,  0.06, 0.34, 'gp:LB',     56, 'ABILITY', 'ability'), // L1 suit power

        // ── Center utility ────────────────────────────────────────────────
        _b(ControlKind.button, 0.44, 0.11, 'gp:BACK',  44, '', 'map'),
        _b(ControlKind.button, 0.56, 0.11, 'gp:START', 44, '', 'pause'),
      ],
    );

// ── Persistence ──────────────────────────────────────────────────────────────

class CustomLayoutStore {
  static const _key = 'custom_layouts_v1';

  static Future<List<CustomLayout>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (json.decode(raw) as List)
          .map((e) => CustomLayout.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAll(List<CustomLayout> layouts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, json.encode(layouts.map((e) => e.toJson()).toList()));
  }
}
