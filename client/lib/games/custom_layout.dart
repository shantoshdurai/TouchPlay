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
    this.opacity = 1.0,
  });

  String id;
  ControlKind kind;
  double x;        // center X, 0..1 of screen width
  double y;        // center Y, 0..1 of screen height
  double size;     // footprint in logical px
  String action;   // encoded binding — see actionLabel() below
  String label;    // optional override text
  double opacity;  // 0..1 — Free-Fire-style per-control transparency

  ControlItem copy() => ControlItem(
      id: id, kind: kind, x: x, y: y, size: size,
      action: action, label: label, opacity: opacity);

  Map<String, dynamic> toJson() => {
        'id': id, 'kind': kind.name, 'x': x, 'y': y,
        'size': size, 'action': action, 'label': label, 'opacity': opacity,
      };

  factory ControlItem.fromJson(Map<String, dynamic> j) => ControlItem(
        id: j['id'] as String,
        kind: ControlKind.values.byName(j['kind'] as String),
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        size: (j['size'] as num).toDouble(),
        action: (j['action'] ?? '') as String,
        label: (j['label'] ?? '') as String,
        opacity: ((j['opacity'] ?? 1.0) as num).toDouble(),
      );
}

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
        [String label = '']) =>
    ControlItem(id: _newId(), kind: k, x: x, y: y, size: size, action: action, label: label);

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
    items: [
      ...steering,
      _b(ControlKind.pedal, 0.93, 0.60, 'pedal:gas', 112),
      _b(ControlKind.pedal, 0.80, 0.62, 'pedal:brake', 100),
      _b(ControlKind.button, 0.66, 0.76, 'gp:A', 80),        // handbrake
      _b(ControlKind.button, 0.40, 0.24, 'gp:RB', 58),       // camera
      _b(ControlKind.button, 0.49, 0.24, 'gp:Y', 58),        // rewind
      _b(ControlKind.button, 0.58, 0.24, 'gp:RS', 58),       // horn
      _b(ControlKind.button, 0.06, 0.24, 'gp:LB', 56),       // clutch
      _b(ControlKind.button, 0.13, 0.24, 'gp:B', 56),        // shift up
      _b(ControlKind.button, 0.42, 0.12, 'gp:BACK', 44),     // map
      _b(ControlKind.button, 0.50, 0.12, 'gp:START', 44),    // pause
      _b(ControlKind.button, 0.58, 0.12, 'gp:DPAD_DOWN', 44),// anna
    ],
  );
}

/// Editable **Marvel's Spider-Man 2** layout. Left/right halves are the fixed
/// move / camera sticks; the SWING control sits on the right (hold = web-swing,
/// drag down + release = Space boost). Buttons carry clear labels and can be
/// rebound to any gamepad button or keyboard key in the editor.
CustomLayout cloneSpiderman() => CustomLayout(
      id: _newId(),
      name: 'My Spider-Man 2',
      floatingSticks: true, // left half = MOVE, right half = CAMERA (fixed)
      items: [
        // SWING — hero control on the right, where the thumb rests.
        _b(ControlKind.swing, 0.66, 0.52, 'swing', 92),
        // Combat cluster (bottom-right).
        _b(ControlKind.button, 0.85, 0.64, 'gp:X', 60, 'ATTACK'),
        _b(ControlKind.button, 0.95, 0.64, 'gp:B', 60, 'DODGE'),
        _b(ControlKind.button, 0.90, 0.84, 'gp:A', 60, 'JUMP'),
        // Traversal extras — keyboard keys you can rebind to your SM2 setup.
        _b(ControlKind.button, 0.55, 0.86, 'key:C', 58, 'ZIP'),       // zip to point
        _b(ControlKind.button, 0.80, 0.30, 'key:F', 58, 'WINGS'),// web wings / glide
        // Web-shooter + gadget + focus (left side, near the move thumb).
        _b(ControlKind.button, 0.06, 0.30, 'gp:RB', 56, 'WEB'),
        _b(ControlKind.button, 0.14, 0.30, 'gp:Y', 56, 'GADGET'),
        _b(ControlKind.button, 0.06, 0.52, 'gp:LB', 56, 'FOCUS'),
        // Utility (top-center).
        _b(ControlKind.button, 0.45, 0.12, 'gp:BACK', 44, 'MAP'),
        _b(ControlKind.button, 0.55, 0.12, 'gp:START', 44, 'PAUSE'),
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
