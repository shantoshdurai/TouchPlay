import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The kinds of control a user can drop onto a custom layout.
enum ControlKind { button, stick, trigger, dpad, mousepad, wheel, pedal }

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
  CustomLayout({required this.id, required this.name, required this.items});

  String id;
  String name;
  List<ControlItem> items;

  CustomLayout copy() =>
      CustomLayout(id: id, name: name, items: items.map((e) => e.copy()).toList());

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'items': items.map((e) => e.toJson()).toList()};

  factory CustomLayout.fromJson(Map<String, dynamic> j) => CustomLayout(
        id: j['id'] as String,
        name: j['name'] as String,
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

ControlItem _b(ControlKind k, double x, double y, String action, double size) =>
    ControlItem(id: _newId(), kind: k, x: x, y: y, size: size, action: action);

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
      items: [
        _b(ControlKind.stick, 0.17, 0.70, 'stick:left', 150),
        _b(ControlKind.stick, 0.83, 0.70, 'stick:right', 150),
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

/// Editable copy of the **Forza** layout, using the new wheel + pedal controls.
CustomLayout cloneForza() => CustomLayout(
      id: _newId(),
      name: 'My Forza',
      items: [
        _b(ControlKind.wheel, 0.17, 0.66, 'wheel', 230),
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
