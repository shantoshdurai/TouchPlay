import 'package:flutter/material.dart';
import '../widgets/analog_stick.dart';
import '../widgets/trigger_button.dart';
import '../widgets/action_button.dart';

/// FH6-specific controller layout in landscape.
///
/// Left side:  LT trigger, Left Stick (steer), D-Pad, LB bumper
/// Center:     BACK / START
/// Right side: RT trigger, Right Stick, ABXY face buttons, RB bumper
class FH6Layout extends StatelessWidget {
  const FH6Layout({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Left column ──────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // LB bumper
                ActionButton(button: 'LB', size: 48),
                // Left Stick + label
                Column(
                  children: [
                    const AnalogStick(side: 'left', button: 'LS', size: 130),
                    const SizedBox(height: 2),
                    Text('STEER', style: _labelStyle),
                  ],
                ),
                // D-Pad
                Column(
                  children: [
                    const DPad(size: 100),
                    const SizedBox(height: 2),
                    Text('ANNA ↑↓', style: _labelStyle),
                  ],
                ),
                // LT trigger + label
                Column(
                  children: [
                    const TriggerBar(side: 'left', label: 'LT', width: 56, height: 90),
                    const SizedBox(height: 2),
                    Text('BRAKE', style: _labelStyle),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ── Center column ────────────────────────────────────
        SizedBox(
          width: 80,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ActionButton(button: 'BACK', size: 38, label: '☰'),
              const SizedBox(height: 16),
              ActionButton(button: 'START', size: 38, label: '▶'),
            ],
          ),
        ),

        // ── Right column ─────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // RB bumper
                ActionButton(button: 'RB', size: 48),
                // ABXY face buttons
                _FaceButtons(),
                // Right Stick + label
                Column(
                  children: [
                    const AnalogStick(side: 'right', button: 'RS', size: 120),
                    const SizedBox(height: 2),
                    Text('LOOK', style: _labelStyle),
                  ],
                ),
                // RT trigger + label
                Column(
                  children: [
                    const TriggerBar(side: 'right', label: 'RT', width: 56, height: 90),
                    const SizedBox(height: 2),
                    Text('ACCEL', style: _labelStyle),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static final _labelStyle = TextStyle(
    color: Colors.white24,
    fontSize: 9,
    letterSpacing: 1,
  );
}

class _FaceButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Xbox diamond layout: Y top, X left, B right, A bottom
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Y — top
          Positioned(top: 0, child: ActionButton(button: 'Y', size: 46)),
          // X — left
          Positioned(left: 0, top: 47, child: ActionButton(button: 'X', size: 46)),
          // B — right
          Positioned(right: 0, top: 47, child: ActionButton(button: 'B', size: 46)),
          // A — bottom
          Positioned(bottom: 0, child: ActionButton(button: 'A', size: 46)),
        ],
      ),
    );
  }
}
