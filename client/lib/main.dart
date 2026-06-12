import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'screens/controller_screen.dart';
import 'screens/file_transfer_screen.dart';
import 'screens/home_menu.dart';
import 'screens/intro_screen.dart';
import 'screens/mouse_keys_screen.dart';
import 'screens/projector_screen.dart';
import 'screens/screen_mirror_screen.dart';
import 'screens/virtual_cam_screen.dart';
import 'services/haptics.dart';
import 'services/player_profile.dart';
import 'services/websocket_service.dart';
import 'package:audioplayers/audioplayers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The home menu adapts to portrait and landscape; feature screens that are
  // landscape-only lock the orientation on entry (see push() below).
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  WakelockPlus.enable();

  // Probe the vibrator once up front so the first buzz isn't delayed.
  await Haptics.instance.init();

  // Start discovery + connection at boot so File Transfer / Virtual Cam /
  // Projector work straight from the menu without opening the gamepad first.
  WebSocketService.instance.init();

  // Decides whether the first-launch intro plays (no saved name yet).
  await PlayerProfile.instance.load();

  runApp(const FH6ControllerApp());
}

class FH6ControllerApp extends StatelessWidget {
  const FH6ControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = ThemeData.dark();
    return MaterialApp(
      title: 'TouchPlay',
      debugShowCheckedModeBanner: false,
      theme: dark.copyWith(
        // Sora everywhere — every Text inherits the family through the theme,
        // so the explicit weights (w200…w700) across the app hit real cuts.
        textTheme: dark.textTheme.apply(fontFamily: 'Sora'),
        primaryTextTheme: dark.primaryTextTheme.apply(fontFamily: 'Sora'),
        scaffoldBackgroundColor: const Color(0xFF080810),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6FB6FF),
          surface: Color(0xFF12121E),
        ),
        dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF12121E)),
      ),
      home: const _Root(),
    );
  }
}

/// Boot gate: plays the first-launch intro until a name is saved, then (and on
/// every later boot) shows the home menu. Settings can replay it to rename.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _showIntro = PlayerProfile.instance.name.value == null;

  @override
  void initState() {
    super.initState();
    AudioPlayer.global.setAudioContext(AudioContextConfig(
      respectSilence: false,
      stayAwake: false,
      focus: AudioContextConfigFocus.mixWithOthers,
    ).build());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 850),
      child: _showIntro
          ? IntroScreen(
              key: const ValueKey('intro'),
              onDone: () => setState(() => _showIntro = false),
            )
          : Builder(
              key: const ValueKey('home'),
              builder: (context) {
                Future<void> push(Widget screen,
                    {bool landscape = true}) async {
                  if (landscape) {
                    await SystemChrome.setPreferredOrientations([
                      DeviceOrientation.landscapeLeft,
                      DeviceOrientation.landscapeRight,
                    ]);
                  }
                  if (!context.mounted) return;
                  await Navigator.push(
                      context, MaterialPageRoute(builder: (_) => screen));
                  // Back on the home menu — portrait allowed again.
                  SystemChrome.setPreferredOrientations(
                      DeviceOrientation.values);
                }

                return HomeMenu(
                  onGamepad: () => push(const ControllerScreen()),
                  onMouse: () =>
                      push(const MouseKeysScreen(), landscape: false),
                  onMirror: () => push(const ScreenMirrorScreen()),
                  onFiles: () =>
                      push(const FileTransferScreen(), landscape: false),
                  onVirtualCam: () =>
                      push(const VirtualCamScreen(), landscape: false),
                  onProjector: () =>
                      push(const ProjectorScreen(), landscape: false),
                  onReplayIntro: () => setState(() => _showIntro = true),
                );
              },
            ),
    );
  }
}
