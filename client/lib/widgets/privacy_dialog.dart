import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/haptics.dart';

Future<void> showPrivacyDialog(BuildContext context) {
  Haptics.instance.tick();
  return showDialog(
    context: context,
    builder: (context) => const PrivacyDialog(),
  );
}

class PrivacyDialog extends StatelessWidget {
  const PrivacyDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF14161F).withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x226FB6FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.privacy_tip_rounded, color: Color(0xFF6FB6FF), size: 32),
                ),
                const SizedBox(height: 20),
                const Text('Privacy Policy',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5)),
                const SizedBox(height: 24),
                const Text('Your data stays on your network.',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                const Text(
                  'TouchPlay connects directly to the TouchPlay server on your own '
                  'PC over your local Wi-Fi or USB. Controller input, the screen '
                  'stream, camera frames and transferred files travel only between '
                  'your phone and your PC — nothing is sent to us or any third '
                  'party, and the app has no analytics, ads or tracking.\n\n'
                  'The app stores your settings (sensitivity, vibration, layouts) '
                  'only on this device. Camera and screen-capture access run only '
                  'while you actively use Virtual Cam or Projector and stop the '
                  'moment you end them.\n\n'
                  'TouchPlay is free and open: if you have questions, open an '
                  'issue on our GitHub.',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                GestureDetector(
                  onTap: () {
                    Haptics.instance.tick();
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9EDF4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('I Understand',
                        style: TextStyle(
                            color: Color(0xFF10141B),
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
