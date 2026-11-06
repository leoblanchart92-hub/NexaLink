import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/device.dart';
import '../../services/app_provider.dart';
import '../../services/data_limit_service.dart';
import '../../models/connection_stats.dart';

/// Advanced statistics screen with charts and data usage visualization
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DataLimitService _dataLimitService;
  bool _isLoading = true;

  // Mock traffic data for chart display
  final List<TrafficDataPoint> _trafficHistory = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initData();
  }

  Future<void> _initData() async {
    _dataLimitService = await DataLimitService.getInstance();
    _generateMockTrafficData();
    setState(() => _isLoading = false);
  }

  void _generateMockTrafficData() {
    final now = DateTime.now();
    _trafficHistory.clear();
    for (int i = 23; i >= 0; i--) {
      final time = now.subtract(Duration(hours: i));
      final rx = (math.Random(i).nextDouble() * 50 * 1024 * 1024).round();
      final tx = (math.Random(i + 100).nextDouble() * 20 * 1024 * 1024).round();
      _trafficHistory.add(TrafficDataPoint(time: time, rxBytes: rx, txBytes: tx));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final stats = app.stats;

    return Scaffold(
      backgroundColor: NexaLinkTheme.darkBackground,
      appBar: AppBar(
        title: const Text('Statistiques'),
        backgroundColor: NexaLinkTheme.darkBackground,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: NexaLinkTheme.electricBlue,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: NexaLinkTheme.electricBlue,
          unselectedLabelColor: NexaLinkTheme.textMuted,
          tabs: const [
            Tab(text: 'Temps réel'),
            Tab(text: 'Consommation'),
            Tab(text: 'Historique'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRealTimeTab(stats),
                _buildConsumptionTab(app),
                _buildHistoryTab(),
              ],
            ),
    );
  }

  // ==================== REAL TIME TAB ====================
  Widget _buildRealTimeTab(ConnectionStats stats) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Speed gauge
          _buildSectionTitle('Vitesse actuelle'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildSpeedCard(
                label: 'Téléchargement',
                speed: stats.formattedRxSpeed,
                icon: Icons.download_rounded,
                color: NexaLinkTheme.electricBlue,
              )),
              const SizedBox(width: 12),
              Expanded(child: _buildSpeedCard(
                label: 'Envoi',
                speed: stats.formattedTxSpeed,
                icon: Icons.upload_rounded,
                color: NexaLinkTheme.neonViolet,
              )),
            ],
          ),

          const SizedBox(height: 24),

          // Real-time chart
          _buildSectionTitle('Trafic (dernières heures)'),
          const SizedBox(height: 12),
          _buildRealTimeChart(),

          const SizedBox(height: 24),

          // Connection info
          _buildSectionTitle('Informations connexion'),
          const SizedBox(height: 12),
          _buildInfoCard([
            _buildInfoRow('Durée', stats.formattedDuration),
            _buildInfoRow('Latence', '${stats.latencyMs} ms'),
            _buildInfoRow('Qualité signal', stats.signalQuality),
          ]),
        ],
      ),
    );
  }

  Widget _buildSpeedCard({
    required String label,
    required String speed,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexaLinkTheme.surfaceCard,
        borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: NexaLinkTheme.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            speed,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== CONSUMPTION TAB ====================
  Widget _buildConsumptionTab(AppProvider app) {
    final stats = app.stats;
    final totalRx = stats.bytesReceived;
    final totalTx = stats.bytesSent;
    final total = totalRx + totalTx;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total consumption
          _buildSectionTitle('Consommation totale'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: NexaLinkTheme.primaryGradient,
              borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
            ),
            child: Column(
              children: [
                Text(
                  _formatBytes(total),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Données transitant par le tunnel VPN',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                // RX/TX breakdown
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildBreakdownItem(
                      icon: Icons.download_rounded,
                      label: 'Reçu',
                      value: stats.formattedRx,
                      percent: total > 0 ? (totalRx / total * 100) : 0,
                      color: NexaLinkTheme.cyan,
                    ),
                    _buildBreakdownItem(
                      icon: Icons.upload_rounded,
                      label: 'Envoyé',
                      value: stats.formattedTx,
                      percent: total > 0 ? (totalTx / total * 100) : 0,
                      color: NexaLinkTheme.neonViolet,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Per-guest consumption
          _buildSectionTitle('Consommation par invité'),
          const SizedBox(height: 12),
          if (app.guestDevices.isEmpty)
            _buildEmptyState(
              icon: Icons.people_outline,
              message: 'Aucun invité connecté',
            )
          else
            ...app.guestDevices.map((guest) => _buildGuestUsageCard(guest)),

          const SizedBox(height: 24),

          // Distribution chart
          if (app.guestDevices.isNotEmpty) ...[
            _buildSectionTitle('Répartition'),
            const SizedBox(height: 12),
            _buildDistributionChart(app.guestDevices),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakdownItem({
    required IconData icon,
    required String label,
    required String value,
    required double percent,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${percent.toStringAsFixed(0)}%',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildGuestUsageCard(guest) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexaLinkTheme.surfaceCard,
        borderRadius: BorderRadius.circular(NexaLinkTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: NexaLinkTheme.electricBlue.withOpacity(0.2),
                    child: const Icon(Icons.phone_android, color: NexaLinkTheme.electricBlue, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guest.name,
                        style: const TextStyle(
                          color: NexaLinkTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        guest.status == DeviceStatus.connected ? 'Connecté' : 'Déconnecté',
                        style: TextStyle(
                          color: guest.status == DeviceStatus.connected
                              ? NexaLinkTheme.success
                              : NexaLinkTheme.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Text(
                _formatBytes((math.Random(guest.name.hashCode).nextDouble() * 100 * 1024 * 1024).round()),
                style: const TextStyle(
                  color: NexaLinkTheme.electricBlue,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (guest.hasDataLimit) ...[
            const SizedBox(height: 12),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: guest.dataUsagePercent,
                backgroundColor: NexaLinkTheme.surfaceElevated,
                valueColor: AlwaysStoppedAnimation(Color(guest.usageColorHex)),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${guest.formattedDataUsed} / ${guest.formattedDataLimit}',
                  style: TextStyle(
                    color: NexaLinkTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
                Text(
                  guest.isDataLimitExceeded ? 'Limite atteinte' : '${guest.formattedDataRemaining} restant',
                  style: TextStyle(
                    color: guest.isDataLimitExceeded ? NexaLinkTheme.error : NexaLinkTheme.textMuted,
                    fontSize: 11,
                    fontWeight: guest.isDataLimitExceeded ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDistributionChart(devices) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexaLinkTheme.surfaceCard,
        borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
      ),
      child: CustomPaint(
        size: const Size(double.infinity, 160),
        painter: _DonutChartPainter(
          values: List.generate(
            devices.length,
            (i) => (math.Random(i.hashCode).nextDouble() * 100),
          ),
          colors: [
            NexaLinkTheme.electricBlue,
            NexaLinkTheme.neonViolet,
            NexaLinkTheme.cyan,
            NexaLinkTheme.success,
            NexaLinkTheme.warning,
            NexaLinkTheme.error,
          ],
          labels: devices.map((d) => d.name).toList(),
        ),
      ),
    );
  }

  // ==================== HISTORY TAB ====================
  Widget _buildHistoryTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Trafic horaire (24h)'),
          const SizedBox(height: 12),
          _buildHourlyChart(),

          const SizedBox(height: 24),

          _buildSectionTitle('Statistiques détaillées'),
          const SizedBox(height: 12),
          _buildInfoCard([
            _buildInfoRow('Période', 'Dernières 24h'),
            _buildInfoRow('Pic téléchargement', '12.4 MB/s à 14:30'),
            _buildInfoRow('Pic envoi', '3.2 MB/s à 15:12'),
            _buildInfoRow('Moyenne RX', '4.8 MB/s'),
            _buildInfoRow('Moyenne TX', '1.2 MB/s'),
          ]),

          const SizedBox(height: 24),

          _buildSectionTitle('Connexions récentes'),
          const SizedBox(height: 12),
          _buildRecentConnections(),
        ],
      ),
    );
  }

  Widget _buildRecentConnections() {
    final connections = [
      {'name': 'Samsung Galaxy A54', 'time': 'Il y a 5 min', 'status': true, 'data': '245 MB'},
      {'name': 'Pixel 7a', 'time': 'Il y a 12 min', 'status': true, 'data': '128 MB'},
      {'name': 'iPhone 14', 'time': 'Hier, 22:15', 'status': false, 'data': '1.2 GB'},
      {'name': 'Redmi Note 12', 'time': 'Hier, 18:30', 'status': false, 'data': '890 MB'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: NexaLinkTheme.surfaceCard,
        borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
      ),
      child: Column(
        children: connections.map<Widget>((conn) => ListTile(
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: conn['status'] as bool
                ? NexaLinkTheme.success.withOpacity(0.2)
                : NexaLinkTheme.surfaceElevated,
            child: Icon(
              conn['status'] as bool ? Icons.phone_android : Icons.phone_android_outlined,
              color: conn['status'] as bool ? NexaLinkTheme.success : NexaLinkTheme.textMuted,
              size: 18,
            ),
          ),
          title: Text(
            conn['name'] as String,
            style: const TextStyle(color: NexaLinkTheme.textPrimary, fontSize: 13),
          ),
          subtitle: Text(
            conn['time'] as String,
            style: const TextStyle(color: NexaLinkTheme.textMuted, fontSize: 11),
          ),
          trailing: Text(
            conn['data'] as String,
            style: const TextStyle(
              color: NexaLinkTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        )).toList(),
      ),
    );
  }

  // ==================== CHARTS ====================
  Widget _buildRealTimeChart() {
    return Container(
      height: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexaLinkTheme.surfaceCard,
        borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
      ),
      child: CustomPaint(
        size: const Size(double.infinity, double.infinity),
        painter: _AreaChartPainter(
          data: _trafficHistory,
          lineColor: NexaLinkTheme.electricBlue,
          fillColor: NexaLinkTheme.electricBlue.withOpacity(0.15),
          showDots: true,
        ),
        child: Container(),
      ),
    );
  }

  Widget _buildHourlyChart() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexaLinkTheme.surfaceCard,
        borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
      ),
      child: CustomPaint(
        size: const Size(double.infinity, double.infinity),
        painter: _BarChartPainter(
          data: _trafficHistory.map((p) => p.rxBytes.toDouble()).toList(),
          data2: _trafficHistory.map((p) => p.txBytes.toDouble()).toList(),
          color1: NexaLinkTheme.electricBlue,
          color2: NexaLinkTheme.neonViolet.withOpacity(0.7),
        ),
        child: Container(),
      ),
    );
  }

  // ==================== HELPERS ====================
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: NexaLinkTheme.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: NexaLinkTheme.surfaceCard,
        borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
      ),
      child: Column(children: rows),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return ListTile(
      title: Text(label, style: const TextStyle(color: NexaLinkTheme.textSecondary, fontSize: 13)),
      trailing: Text(value, style: const TextStyle(color: NexaLinkTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: NexaLinkTheme.surfaceCard,
        borderRadius: BorderRadius.circular(NexaLinkTheme.radiusLg),
      ),
      child: Column(
        children: [
          Icon(icon, color: NexaLinkTheme.textMuted, size: 40),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: NexaLinkTheme.textMuted, fontSize: 14)),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

// ==================== CHART PAINTERS ====================

/// Area chart for real-time traffic visualization
class _AreaChartPainter extends CustomPainter {
  final List<TrafficDataPoint> data;
  final Color lineColor;
  final Color fillColor;
  final bool showDots;

  _AreaChartPainter({
    required this.data,
    required this.lineColor,
    required this.fillColor,
    this.showDots = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxVal = data.map((d) => d.rxBytes).reduce(math.max).toDouble();
    if (maxVal == 0) return;

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final gradientShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [fillColor, fillColor.withOpacity(0)],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final fillPaint = Paint()..shader = gradientShader;

    final path = Path();
    final fillPath = Path();

    final stepX = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = size.height - (data[i].rxBytes / maxVal * size.height);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Draw fill
    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    canvas.drawPath(path, paint);

    // Draw dots
    if (showDots) {
      final dotPaint = Paint()..color = lineColor;
      for (int i = 0; i < data.length; i++) {
        final x = i * stepX;
        final y = size.height - (data[i].rxBytes / maxVal * size.height);
        canvas.drawCircle(Offset(x, y), 3, dotPaint);
      }
    }

    // Draw grid lines
    final gridPaint = Paint()
      ..color = NexaLinkTheme.textMuted.withOpacity(0.1)
      ..strokeWidth = 0.5;
    
    for (int i = 0; i < 4; i++) {
      final y = size.height * (i + 1) / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Bar chart for hourly comparison
class _BarChartPainter extends CustomPainter {
  final List<double> data;
  final List<double> data2;
  final Color color1;
  final Color color2;

  _BarChartPainter({
    required this.data,
    required this.data2,
    required this.color1,
    required this.color2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxVal = data.reduce(math.max);
    if (maxVal == 0) return;

    final barWidth = size.width / data.length * 0.6;
    final spacing = size.width / data.length * 0.4;

    for (int i = 0; i < data.length; i++) {
      final barHeight = data[i] / maxVal * size.height * 0.8;
      final x = i * (barWidth + spacing) + spacing / 2;

      // RX bar
      final rxRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, size.height - barHeight, barWidth / 2, barHeight),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      canvas.drawRRect(rxRect, Paint()..color = color1);

      // TX bar
      final txHeight = data2[i] / maxVal * size.height * 0.8;
      final txRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x + barWidth / 2, size.height - txHeight, barWidth / 2, txHeight),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      canvas.drawRRect(txRect, Paint()..color = color2);
    }

    // Grid lines
    final gridPaint = Paint()
      ..color = NexaLinkTheme.textMuted.withOpacity(0.1)
      ..strokeWidth = 0.5;
    for (int i = 0; i < 4; i++) {
      final y = size.height * (i + 1) / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Donut chart for distribution
class _DonutChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final List<String> labels;

  _DonutChartPainter({
    required this.values,
    required this.colors,
    required this.labels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.reduce((a, b) => a + b);
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.height / 2 - 10;
    final innerRadius = radius * 0.6;

    final rect = Rect.fromCircle(center: center, radius: radius);
    var startAngle = -math.pi / 2;

    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < values.length; i++) {
      final sweepAngle = (values[i] / total) * 2 * math.pi;
      paint.color = colors[i % colors.length];
      
      final outerPath = Path()..addArc(rect, startAngle, sweepAngle);
      final innerRect = Rect.fromCircle(center: center, radius: innerRadius);
      final innerPath = Path()..addArc(innerRect, startAngle + sweepAngle, -sweepAngle);
      
      final slicePath = Path()
        ..addArc(rect, startAngle, sweepAngle)
        ..lineTo(center.dx, center.dy)
        ..close();
      
      // Draw as arc
      canvas.drawArc(rect, startAngle, sweepAngle, true, paint);
      
      startAngle += sweepAngle;
    }

    // Draw inner circle (donut hole)
    final holePaint = Paint()..color = NexaLinkTheme.surfaceCard;
    canvas.drawCircle(center, innerRadius, holePaint);

    // Draw center text
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${values.length}',
        style: TextStyle(
          color: NexaLinkTheme.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: TextAlign.center,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(
      center.dx - textPainter.width / 2,
      center.dy - textPainter.height / 2,
    ));

    // Draw labels
    final labelPainter = TextPainter(
      text: TextSpan(
        text: 'invités',
        style: TextStyle(
          color: NexaLinkTheme.textMuted,
          fontSize: 11,
        ),
      ),
      textAlign: TextAlign.center,
    );
    labelPainter.layout();
    labelPainter.paint(canvas, Offset(
      center.dx - labelPainter.width / 2,
      center.dy + 12,
    ));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
