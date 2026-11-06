import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexalink/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(EngineDiagnostics.channel, null));
  test('returns the native runtime value without claiming a connection', () async {
    messenger.setMockMethodCallHandler(EngineDiagnostics.channel, (call) async {
      expect(call.method, 'runtimeVersion');
      return 'go-test';
    });
    expect(await EngineDiagnostics.runtimeVersion(), 'go-test');
  });
  test('native failure is reported as unavailable', () async {
    messenger.setMockMethodCallHandler(EngineDiagnostics.channel, (call) async {
      throw PlatformException(code: 'engine_unavailable');
    });
    expect(await EngineDiagnostics.runtimeVersion(), isNull);
  });
}
