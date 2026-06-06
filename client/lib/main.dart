import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'screens/controller_screen.dart';
import 'services/haptics.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  WakelockPlus.enable();

  // Probe the vibrator once up front so the first buzz isn't delayed.
  await Haptics.instance.init();

  runApp(const FH6ControllerApp());
}

class FH6ControllerApp extends StatelessWidget {
  const FH6ControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TouchPlay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF08080F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00D4FF),
          surface: Color(0xFF12121E),
        ),
        dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF12121E)),
      ),
      home: const ControllerScreen(),
    );
  }
}
