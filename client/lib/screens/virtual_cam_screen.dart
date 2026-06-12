import 'package:flutter/material.dart';

import '../services/cast_service.dart';
import '../services/haptics.dart';
import '../widgets/ambience.dart';

const _accent = Color(0xFF6FB6FF);

/// Phone camera → PC webcam. The PC feeds frames into the OBS virtual camera
/// (or shows a preview window if the driver isn't installed).
class VirtualCamScreen extends StatefulWidget {
  const VirtualCamScreen({super.key});

  @override
  State<VirtualCamScreen> createState() => _VirtualCamScreenState();
}

class _VirtualCamScreenState extends State<VirtualCamScreen> {
  bool _busy = false;
  String? _error;

  bool get _live => CastService.instance.activeMode.value == 'camera';

  Future<void> _toggle() async {
    if (_busy) return;
    Haptics.instance.heavy();
    setState(() {
      _busy = true;
      _error = null;
    });
    if (_live) {
      await CastService.instance.stop();
    } else {
      final err = await CastService.instance.start('camera');
      if (mounted && err != null) setState(() => _error = err);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    // Leaving the screen ends the cast — no orphaned camera in the background.
    if (_live) CastService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AmbientBackground(
        child: SafeArea(
          child: OrientationBuilder(
            builder: (context, o) =>
                o == Orientation.portrait ? _portrait() : _landscape(),
          ),
        ),
      ),
    );
  }

  // ── Layouts ────────────────────────────────────────────────────────────────
  Widget _landscape() => Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _preview(),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(),
                  const SizedBox(height: 12),
                  _statusText(),
                  ..._errorBlock(),
                  const Spacer(),
                  _controlsRow(),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _portrait() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: 12),
            Expanded(child: _preview()),
            const SizedBox(height: 12),
            _statusText(),
            ..._errorBlock(),
            const SizedBox(height: 14),
            _controlsRow(),
          ],
        ),
      );

  // ── Pieces ─────────────────────────────────────────────────────────────────
  Widget _preview() => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          color: const Color(0xAA0A0D14),
          child: ValueListenableBuilder(
            valueListenable: CastService.instance.preview,
            builder: (_, img, __) => img != null
                ? RawImage(image: img, fit: BoxFit.contain)
                : Center(
                    child: Icon(Icons.videocam_off_outlined,
                        color: Colors.white.withValues(alpha: 0.12),
                        size: 56),
                  ),
          ),
        ),
      );

  Widget _header() => Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white70, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Text('Virtual Cam',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          ValueListenableBuilder(
            valueListenable: CastService.instance.fps,
            builder: (_, fps, __) => _live && fps > 0
                ? Text('$fps fps',
                    style: const TextStyle(color: _accent, fontSize: 11))
                : const SizedBox.shrink(),
          ),
        ],
      );

  Widget _statusText() => ValueListenableBuilder(
        valueListenable: CastService.instance.sink,
        builder: (_, sinkMode, __) {
          final String msg;
          if (!_live) {
            msg = 'Streams this phone\'s camera to your PC as a '
                'webcam. If the PC has no virtual-camera driver, '
                'a preview window opens instead (install OBS '
                'Studio to get the driver).';
          } else if (sinkMode == 'webcam') {
            final dev =
                CastService.instance.sinkDevice ?? 'OBS Virtual Camera';
            msg = 'TouchPlay cam is LIVE on your PC. In Discord '
                '/ Zoom / Meet pick the webcam named "$dev" — '
                'that\'s the PC\'s virtual-camera driver '
                'TouchPlay streams into (the name comes from '
                'the driver, the video is your phone).';
          } else if (sinkMode == 'window') {
            msg = 'LIVE — but the PC has no virtual-camera '
                'driver, so it shows a preview window instead. '
                'Install OBS Studio (it ships the driver), then '
                'restart the TouchPlay server for true webcam '
                'mode.';
          } else {
            msg = 'LIVE — check the preview window or webcam '
                'list on your PC.';
          }
          return Text(msg,
              style: TextStyle(
                  color: _live && sinkMode == 'window'
                      ? const Color(0xFFFFCC4D)
                      : Colors.white54,
                  fontSize: 11.5,
                  height: 1.45));
        },
      );

  List<Widget> _errorBlock() => [
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: const TextStyle(
                  color: Color(0xFFFF6B6B), fontSize: 11, height: 1.4)),
          // Connection errors get a gentle path to the server download —
          // open it here, or copy the link for the PC.
          if (_error!.toLowerCase().contains('connect') ||
              _error!.toLowerCase().contains('server')) ...[
            const SizedBox(height: 10),
            const GetServerHint(),
          ],
        ],
      ];

  Widget _controlsRow() => Row(
        children: [
          Expanded(
            child: PillButton(
              label: _live ? 'Stop Camera' : 'Go Live',
              icon: _live ? Icons.stop_rounded : Icons.videocam_rounded,
              busy: _busy,
              danger: _live,
              onTap: _toggle,
            ),
          ),
          if (_live) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                Haptics.instance.tick();
                CastService.instance.flipCamera();
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: const Icon(Icons.flip_camera_android,
                    color: Colors.white70, size: 20),
              ),
            ),
          ],
        ],
      );
}
