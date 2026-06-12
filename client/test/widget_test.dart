// Basic smoke test: the app boots into the PS5-style home menu launcher.

import 'package:flutter_test/flutter_test.dart';

import 'package:touchplay/main.dart';
import 'package:touchplay/screens/home_menu.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const FH6ControllerApp());

    // The app boots into the home menu launcher (not straight into a feature).
    expect(find.byType(HomeMenu), findsOneWidget);
  });
}
