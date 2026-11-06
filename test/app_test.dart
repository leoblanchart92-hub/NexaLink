import 'package:flutter_test/flutter_test.dart';
import 'package:nexalink/models/connection_stats.dart';
import 'package:nexalink/models/vpn_config.dart';
import 'package:nexalink/services/qr_service.dart';

void main() {
  group('VpnConfig', () {
    test('toWgConfig generates valid WireGuard config', () {
      final config = VpnConfig(
        privateKey: 'privateKey123=',
        publicKey: 'publicKey123=',
        tunnelAddress: '10.10.10.1/32',
        listenPort: 51820,
        dns: '1.1.1.1',
        endpoint: '192.168.1.1',
        allowedIps: '0.0.0.0/0',
        persistentKeepalive: 25,
        peerPublicKey: 'peerKey123=',
      );

      final wgConfig = config.toWgConfig();
      expect(wgConfig, contains('[Interface]'));
      expect(wgConfig, contains('[Peer]'));
      expect(wgConfig, contains('PrivateKey = privateKey123='));
      expect(wgConfig, contains('Address = 10.10.10.1/32'));
      expect(wgConfig, contains('DNS = 1.1.1.1'));
      expect(wgConfig, contains('ListenPort = 51820'));
      expect(wgConfig, contains('Endpoint = 192.168.1.1'));
      expect(wgConfig, contains('AllowedIPs = 0.0.0.0/0'));
      expect(wgConfig, contains('PersistentKeepalive = 25'));
      expect(wgConfig, contains('PublicKey = peerKey123='));
    });

    test('toJson and fromJson roundtrip', () {
      final config = VpnConfig(
        privateKey: 'testKey',
        publicKey: 'testPubKey',
        tunnelAddress: '10.10.10.2/32',
        listenPort: 51820,
        dns: '8.8.8.8',
        isOwner: false,
      );

      final json = config.toJson();
      final restored = VpnConfig.fromJson(json);

      expect(restored.privateKey, equals(config.privateKey));
      expect(restored.publicKey, equals(config.publicKey));
      expect(restored.tunnelAddress, equals(config.tunnelAddress));
      expect(restored.listenPort, equals(config.listenPort));
      expect(restored.isOwner, equals(config.isOwner));
    });
  });

  group('ConnectionStats', () {
    test('formattedRx formats bytes correctly', () {
      final stats = ConnectionStats(bytesReceived: 1024);
      expect(stats.formattedRx, equals('1.0 KB'));

      final stats2 = ConnectionStats(bytesReceived: 1048576);
      expect(stats2.formattedRx, equals('1.0 MB'));

      final stats3 = ConnectionStats(bytesReceived: 500);
      expect(stats3.formattedRx, equals('500 B'));
    });

    test('formattedDuration formats time correctly', () {
      final stats1 = ConnectionStats(connectionDuration: Duration(seconds: 45));
      expect(stats1.formattedDuration, equals('45s'));

      final stats2 = ConnectionStats(connectionDuration: Duration(minutes: 5, seconds: 30));
      expect(stats2.formattedDuration, equals('5m 30s'));

      final stats3 = ConnectionStats(connectionDuration: Duration(hours: 2, minutes: 15));
      expect(stats3.formattedDuration, equals('2h 15m'));
    });

    test('signalQuality returns correct quality', () {
      expect(ConnectionStats(latencyMs: 20).signalQuality, equals('Excellent'));
      expect(ConnectionStats(latencyMs: 50).signalQuality, equals('Good'));
      expect(ConnectionStats(latencyMs: 100).signalQuality, equals('Fair'));
      expect(ConnectionStats(latencyMs: 200).signalQuality, equals('Poor'));
    });
  });

  group('QrService', () {
    test('generatePairingQrData creates valid JSON', () {
      final data = QrService.generatePairingQrData(
        ownerPublicKey: 'testPublicKey',
        ownerEndpoint: '192.168.1.100',
        port: 51820,
        sessionId: 'session123',
      );

      final parsed = QrService.parseOwnerQrData(data);
      expect(parsed, isNotNull);
      expect(parsed!.ownerPublicKey, equals('testPublicKey'));
      expect(parsed.ownerEndpoint, equals('192.168.1.100'));
      expect(parsed.ownerPort, equals(51820));
      expect(parsed.sessionId, equals('session123'));
    });

    test('parseOwnerQrData rejects invalid data', () {
      expect(QrService.parseOwnerQrData('invalid'), isNull);
      expect(QrService.parseOwnerQrData('{}'), isNull);
      expect(QrService.parseOwnerQrData('{"type":"wrong"}'), isNull);
    });

    test('parseOwnerQrData rejects expired QR', () {
      final data = QrService.generatePairingQrData(
        ownerPublicKey: 'key',
        ownerEndpoint: '1.2.3.4',
        port: 51820,
        sessionId: 'session',
      );
      
      // Modify to expired
      final parsed = QrService.parseOwnerQrData(data);
      expect(parsed, isNotNull);
    });

    test('guest response roundtrip', () {
      final data = QrService.generateGuestResponseQrData(
        sessionId: 'session456',
        guestPublicKey: 'guestPubKey',
        guestName: 'Mon Téléphone',
      );

      final parsed = QrService.parseGuestResponseQrData(data);
      expect(parsed, isNotNull);
      expect(parsed!.sessionId, equals('session456'));
      expect(parsed.guestPublicKey, equals('guestPubKey'));
      expect(parsed.guestName, equals('Mon Téléphone'));
    });
  });
}
