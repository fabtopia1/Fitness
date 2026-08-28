import 'package:flutter_test/flutter_test.dart';

import '../support/scenarios.dart';

/// The end-to-end journeys, run headlessly so CI catches a broken flow on
/// every push rather than only when someone attaches a device.
///
/// The same scenarios run on a device from `integration_test/app_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerAppScenarios();
}
