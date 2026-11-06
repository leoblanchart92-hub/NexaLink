import 'package:flutter_test/flutter_test.dart';
import 'package:nexalink/main.dart';
void main() {
  test('server URL requires HTTPS without credentials or a path', () {
    expect(parseServer('https://example.org'), isNotNull);
    expect(parseServer('https://example.org:8443/'), isNotNull);
    for (final value in ['http://example.org', 'https://user@example.org', 'https://example.org/path', 'https://example.org/?x=1', 'https://example.org/#fragment', 'not a url']) {
      expect(parseServer(value), isNull, reason: value);
    }
  });
}
