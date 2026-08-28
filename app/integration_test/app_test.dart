import 'package:integration_test/integration_test.dart';

import '../test/support/scenarios.dart';

/// The end-to-end journeys on a real device or emulator:
///
///   `flutter test integration_test/app_test.dart -d <device>`
///
/// The scenarios themselves live in `test/support/scenarios.dart` and are also
/// run headlessly by `test/integration/app_scenarios_test.dart`, so the same
/// journeys are verified on every push and again on real hardware before a
/// release.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerAppScenarios();
}
