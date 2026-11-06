import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() => runApp(const NexaLink());

/// Reject cleartext, credentials, query strings and paths; tokens must only go to
/// the exact server the user chose. This is not a guarantee a server is trusted.
Uri? parseServer(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
      uri.userInfo.isNotEmpty || (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery || uri.hasFragment) return null;
  return Uri(scheme: 'https', host: uri.host, port: uri.hasPort ? uri.port : null);
}

class Api {
  final Uri base;
  Api(this.base);
  Future<Map<String, dynamic>> request(String path, {String? token, Map<String, dynamic>? body, bool post = false}) async {
    final headers = {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
    final uri = base.replace(path: path);
    // Do not follow redirects: otherwise bearer credentials may reach another host.
    final request = http.Request(post ? 'POST' : 'GET', uri)
      ..headers.addAll(headers)
      ..followRedirects = false;
    if (post) request.body = jsonEncode(body ?? {});
    final client = http.Client();
    try {
      final response = await client.send(request).timeout(const Duration(seconds: 15));
      final text = await response.stream.bytesToString().timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Serveur : erreur ${response.statusCode}');
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } finally { client.close(); }
  }
}

class NexaLink extends StatelessWidget {
  const NexaLink({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'NexaLink', debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff527cff), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xff080c1a),
      cardTheme: const CardTheme(color: Color(0xff151d35)),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    ), home: const Home(),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override State<Home> createState() => _HomeState();
}
class _HomeState extends State<Home> {
  final storage = const FlutterSecureStorage();
  final serverController = TextEditingController();
  final nameController = TextEditingController(text: 'Téléphone invité');
  Uri? server;
  String? ownerToken, guestToken, guestServer, guestStatus;
  List<dynamic> guests = [];
  String? qr;
  DateTime? qrExpiry;
  bool busy = false;
  int tab = 0;

  @override void initState() { super.initState(); load(); }
  @override void dispose() { serverController.dispose(); nameController.dispose(); super.dispose(); }
  Future<void> load() async {
    final s = await storage.read(key: 'owner_server');
    final o = await storage.read(key: 'owner_token');
    final gs = await storage.read(key: 'guest_server');
    final gt = await storage.read(key: 'guest_token');
    if (!mounted) return;
    setState(() { server = s == null ? null : parseServer(s); serverController.text = s ?? ''; ownerToken = o; guestServer = gs; guestToken = gt; });
    if (server != null && ownerToken != null) await refreshOwner();
    if (guestServer != null && guestToken != null) await refreshGuest();
  }
  Future<void> run(Future<void> Function() task) async {
    if (busy) return;
    setState(() => busy = true);
    try { await task(); } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Opération impossible : $e')));
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> configure() => run(() async {
    final target = parseServer(serverController.text);
    if (target == null) throw Exception('Indiquez une adresse HTTPS valide, sans chemin.');
    if (server != null && server != target && ownerToken != null) {
      if (!mounted) return;
      final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: const Text('Changer de serveur ?'),
        content: const Text('L’identité propriétaire enregistrée sur ce téléphone sera remplacée. Les invités existants resteront sur l’ancien serveur et ne pourront plus être gérés depuis cette identité.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continuer'))],
      ));
      if (confirm != true) return;
    }
    if (server != target || ownerToken == null) {
      final result = await Api(target).request('/v1/owners', post: true);
      final newToken = result['token'] as String;
      await storage.write(key: 'owner_token', value: newToken);
      await storage.write(key: 'owner_server', value: target.toString());
      ownerToken = newToken;
      guests = []; qr = null;
    }
    if (mounted) setState(() { server = target; serverController.text = target.toString(); });
    await refreshOwner();
  });
  Future<void> refreshOwner() async {
    if (server == null || ownerToken == null) return;
    final result = await Api(server!).request('/v1/guests', token: ownerToken);
    if (mounted) setState(() => guests = result['guests'] as List<dynamic>);
  }
  Future<void> invite() => run(() async {
    if (server == null || ownerToken == null) throw Exception('Configurez d’abord le serveur.');
    final data = await Api(server!).request('/v1/invitations', post: true, token: ownerToken);
    if (mounted) {
      setState(() {
      qr = jsonEncode({'version': 1, 'server': server.toString(), 'secret': data['secret']});
      qrExpiry = DateTime.fromMillisecondsSinceEpoch(data['expiresAt'] as int);
      });
    }
  });
  Future<void> action(String id, String action) => run(() async {
    await Api(server!).request('/v1/guests/$id/$action', post: true, token: ownerToken);
    await refreshOwner();
  });
  Future<void> refreshGuest() async {
    final uri = guestServer == null ? null : parseServer(guestServer!);
    if (uri == null || guestToken == null) return;
    final data = await Api(uri).request('/v1/guest', token: guestToken);
    if (mounted) setState(() => guestStatus = data['status'] as String);
  }
  Future<void> scan() async {
    final value = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const Scanner()));
    if (value == null || !mounted) return;
    await run(() async {
      final dynamic decoded = jsonDecode(value);
      if (decoded is! Map || decoded['version'] != 1 || decoded['server'] is! String || decoded['secret'] is! String || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(decoded['secret'] as String)) throw Exception('QR code NexaLink invalide.');
      final target = parseServer(decoded['server'] as String);
      if (target == null) throw Exception('Le serveur du QR code doit utiliser HTTPS.');
      if (!mounted) return;
      final agree = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: const Text('Confirmer l’association'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Serveur : $target\n\nN’acceptez que si vous faites confiance au propriétaire et au serveur. L’association ne crée pas de connexion VPN.'),
          const SizedBox(height: 16), TextField(controller: nameController, maxLength: 60, decoration: const InputDecoration(labelText: 'Nom de cet appareil')),
          if (guestToken != null) const Text('Cette association remplacera celle enregistrée sur ce téléphone.'),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Demander l’accès'))],
      ));
      if (agree != true) return;
      final data = await Api(target).request('/v1/claims', post: true, body: {'secret': decoded['secret'], 'name': nameController.text.trim()});
      final newToken = data['token'] as String;
      await storage.write(key: 'guest_token', value: newToken);
      await storage.write(key: 'guest_server', value: target.toString());
      if (mounted) setState(() { guestServer = target.toString(); guestToken = newToken; guestStatus = data['status'] as String; });
    });
  }
  String status(String? s) => switch (s) { 'pending' => 'En attente d’approbation', 'approved' => 'Approuvé', 'revoked' => 'Révoqué', _ => 'Inconnu' };
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('NexaLink'), actions: [if (busy) const Padding(padding: EdgeInsets.all(18), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))]),
    bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [NavigationDestination(icon: Icon(Icons.hub_outlined), label: 'Propriétaire'), NavigationDestination(icon: Icon(Icons.phone_android), label: 'Invité')]),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Connexion à distance', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.info_outline, color: Colors.lightBlueAccent), const SizedBox(width: 12), Expanded(child: Text('Version en développement : association uniquement. Le VPN et le partage Internet ne sont pas encore disponibles.', style: TextStyle(color: Colors.blue.shade100)))]))),
      const SizedBox(height: 16),
      if (tab == 0) ...[
        const Text('Serveur d’association', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)), const SizedBox(height: 8),
        const Text('Utilisez votre propre serveur NexaLink accessible en HTTPS.'), const SizedBox(height: 12),
        TextField(controller: serverController, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Adresse HTTPS', hintText: 'https://exemple.fr')),
        const SizedBox(height: 12), FilledButton.icon(onPressed: busy ? null : configure, icon: const Icon(Icons.cloud_done_outlined), label: const Text('Enregistrer le serveur')),
        const SizedBox(height: 24), const Text('Invitations', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const Text('Chaque code est utilisable une fois et expire après 5 minutes. Traitez-le comme un mot de passe.'), const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: busy || server == null ? null : invite, icon: const Icon(Icons.qr_code), label: const Text('Créer un QR code')),
        if (qr != null) ...[const SizedBox(height: 12), Center(child: Container(color: Colors.white, padding: const EdgeInsets.all(12), child: QrImageView(data: qr!, size: 220))), Text('Expire à ${qrExpiry!.toLocal().toString().substring(11, 19)}', textAlign: TextAlign.center)],
        const SizedBox(height: 24), Row(children: [const Expanded(child: Text('Invités', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))), IconButton(onPressed: busy || server == null ? null : () => run(refreshOwner), icon: const Icon(Icons.refresh), tooltip: 'Actualiser')]),
        if (guests.isEmpty) const Text('Aucun invité à afficher.'),
        for (final guest in guests) Card(child: ListTile(title: Text(guest['name'] as String), subtitle: Text(status(guest['status'] as String)), trailing: Wrap(children: [
          if (guest['status'] == 'pending') IconButton(tooltip: 'Approuver', onPressed: busy ? null : () => action(guest['id'] as String, 'approve'), icon: const Icon(Icons.check_circle_outline)),
          if (guest['status'] != 'revoked') IconButton(tooltip: 'Révoquer', onPressed: busy ? null : () => action(guest['id'] as String, 'revoke'), icon: const Icon(Icons.block)),
        ]))),
      ] else ...[
        const Text('Association invitée', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)), const SizedBox(height: 8),
        const Text('Scannez le code présenté par le propriétaire. Il devra ensuite approuver votre demande.'), const SizedBox(height: 12),
        FilledButton.icon(onPressed: busy ? null : scan, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scanner une invitation')),
        if (guestToken != null) Card(child: ListTile(title: Text(status(guestStatus)), subtitle: Text(guestServer ?? ''), trailing: IconButton(onPressed: busy ? null : () => run(refreshGuest), tooltip: 'Actualiser', icon: const Icon(Icons.refresh)))),
      ]
    ]),
  );
}

class Scanner extends StatefulWidget {
  const Scanner({super.key});
  @override State<Scanner> createState() => _ScannerState();
}
class _ScannerState extends State<Scanner> {
  bool scanned = false;
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Scanner le QR code')), body: MobileScanner(onDetect: (capture) {
    if (scanned) return;
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null) { scanned = true; Navigator.pop(context, barcode.rawValue); return; }
    }
  }));
}
