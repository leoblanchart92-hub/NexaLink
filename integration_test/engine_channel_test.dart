import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nexalink/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Flutter reaches Kotlin and the loaded Go runtime', (tester) async {
    // Runs on an emulator, through the real platform channel, not a mock.
    // A runtime version is not a VPN connection or a working tunnel.
    final version = await EngineDiagnostics.runtimeVersion();
    expect(version, isNotNull);
    expect(version, startsWith('go1.26'));
  });
}
