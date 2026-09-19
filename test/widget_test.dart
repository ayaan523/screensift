// This is a basic Flutter widget test.
//
// Verifies that the ScreenSift app initializes and renders the home screen
// without crashing. It does not depend on the native screenshot bridge, so it
// runs on any host including CI.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:screensift/data/datasources/native_screenshot_source.dart';
import 'package:screensift/data/datasources/settings_store.dart';
import 'package:screensift/data/repositories/capture_repository.dart';
import 'package:screensift/data/services/rule_based_extractor.dart';
import 'package:screensift/main.dart';

void main() {
  testWidgets('ScreenSift app renders home screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsStore.withPrefs(prefs);
    final repository = CaptureRepository(
      native: NativeScreenshotSource(),
      settings: settings,
      prefs: prefs,
      buildExtractor: RuleBasedExtractor.new,
    );

    await tester.pumpWidget(
      ScreenSiftApp(repository: repository, settings: settings),
    );

    await tester.pumpAndSettle();

    // The app title is shown in the scaffold AppBar.
    expect(find.text('ScreenSift'), findsOneWidget);
  });
}
