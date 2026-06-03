import 'package:flutter/material.dart';

/// A selectable on-screen layout ("game UI") the user can switch between.
///
/// All profiles speak the SAME WebSocket protocol (Xbox gamepad events), so a
/// profile is purely a different *presentation* of the same controller — the
/// server never needs to know which one is active.
class GameProfile {
  const GameProfile({
    required this.id,
    required this.name,
    required this.tagline,
    required this.icon,
    this.comingSoon = false,
  });

  /// Stable key persisted in SharedPreferences.
  final String id;

  /// Display name on the card.
  final String name;

  /// One-line subtitle on the card.
  final String tagline;

  /// Launcher-style icon — distinct per game.
  final IconData icon;

  /// Greyed-out placeholder card (not yet selectable).
  final bool comingSoon;
}

// ── Live profiles ──────────────────────────────────────────────────────────────

const kStandardProfile = GameProfile(
  id: 'standard',
  name: 'Standard Gamepad',
  tagline: 'Full Xbox controller',
  icon: Icons.sports_esports,
);

const kForzaProfile = GameProfile(
  id: 'forza',
  name: 'Forza Horizon',
  tagline: 'Wheel · pedals · drift',
  icon: Icons.directions_car_filled,
);

const kSpidermanProfile = GameProfile(
  id: 'spiderman',
  name: "Marvel's Spider-Man 2",
  tagline: 'Swing · launch · combat',
  icon: Icons.filter_tilt_shift,
);

/// Every card shown in the picker, in order. Coming-soon cards advertise that
/// more per-game layouts can be dropped in later.
const kGameProfiles = <GameProfile>[
  kStandardProfile,
  kForzaProfile,
  kSpidermanProfile,
  GameProfile(
    id: 'nfs',
    name: 'Need for Speed',
    tagline: 'Arcade racing',
    icon: Icons.bolt,
    comingSoon: true,
  ),
  GameProfile(
    id: 'minecraft',
    name: 'Minecraft',
    tagline: 'Build & explore',
    icon: Icons.view_in_ar,
    comingSoon: true,
  ),
  GameProfile(
    id: 'flight',
    name: 'Flight Sim',
    tagline: 'Throttle & yoke',
    icon: Icons.flight,
    comingSoon: true,
  ),
];

GameProfile profileById(String? id) => kGameProfiles.firstWhere(
      (p) => p.id == id,
      orElse: () => kStandardProfile,
    );
