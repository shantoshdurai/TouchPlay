// Basic smoke tests: first launch plays the intro; once a name is saved the
// app boots straight into the PS5-style home menu launcher.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:touchplay/main.dart';
import 'package:touchplay/screens/home_menu.dart';
import 'package:touchplay/screens/intro_screen.dart';
import 'package:touchplay/services/player_profile.dart';

void main() {
  testWidgets('First launch shows the intro', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await PlayerProfile.instance.load();
    await tester.pumpWidget(const FH6ControllerApp());

    expect(find.byType(IntroScreen), findsOneWidget);

    // Drain the intro's pending phase timers so the test ends cleanly.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('With a saved name the app boots into the home menu',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'player_name': 'Player'});
    await PlayerProfile.instance.load();
    await tester.pumpWidget(const FH6ControllerApp());

    // Straight to the launcher (not the intro, not a feature screen).
    expect(find.byType(HomeMenu), findsOneWidget);
  });
}
