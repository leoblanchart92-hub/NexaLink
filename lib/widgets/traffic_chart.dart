import 'dart:math';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/connection_stats.dart';

/// Animated traffic chart showing RX/TX over time
class TrafficChart extends StatefulWidget {
  const TrafficChart({super.key});

  @override
  State<TrafficChart> createState() => _TrafficChartState();
}

class _TrafficChartState extends State<TrafficChart> {
  final List<TrafficDataPoint> _dataPoints = [];
  static const int maxPoints = 30;

  @override
  void initState() {
    super.initState();
    // Initialize with empty data
    final now = DateTime.now();
    for (int i = maxPoints; i >= 0; i--) {
      _dataPoints.add(TrafficDataPoint(
        time: now.subtract(Duration(seconds: i * 3)),
        rxBytes: 0,
        txBytes: 0,
      ));
    }
  }

  void _addDataPoint(int rx, int tx) {
    setState(() {
      _dataPoints.add(TrafficDataPoint(
        time: DateTime.now(),
        rxBytes: rx,
        txBytes: tx,
      ));
      if (_dataPoints.length > maxPoints) {
        _dataPoints.removeAt(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: CustomPaint(
        size: Size.infinite,
        painter: _TrafficChartPainter(
          dataPoints: _dataPoints,
          rxColor: NexaLinkTheme.cyan,
          txColor: NexaLinkTheme.neonViolet,
        ),
      ),
    );
  }
}

class _TrafficChartPainter extends CustomPainter {
  final List<TrafficDataPoint> dataPoints;
  final Color rxColor;
  final Color txColor;

  _TrafficChartPainter({
    required this.dataPoints,
    required this.rxColor,
    required this.txColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.length < 2) return;

    // Find max value for scaling
    int maxBytes = 1;
    for (final point in dataPoints) {
      maxBytes = max(maxBytes, max(point.rxBytes, point.txBytes));
    }

    final rxPaint = Paint()
      ..color = rxColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final txPaint = Paint()
      ..color = txColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rxFill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [rxColor.withOpacity(0.3), rxColor.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final txFill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [txColor.withOpacity(0.3), txColor.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final rxPath = Path();
    final txPath = Path();
    final rxFillPath = Path();
    final txFillPath = Path();

    final dx = size.width / (dataPoints.length - 1);

    for (int i = 0; i < dataPoints.length; i++) {
      final x = i * dx;
      final rxY = size.height - (dataPoints[i].rxBytes / maxBytes) * size.height;
      final txY = size.height - (dataPoints[i].txBytes / maxBytes) * size.height;

      if (i == 0) {
        rxPath.moveTo(x, rxY);
        txPath.moveTo(x, txY);
        rxFillPath.moveTo(x, size.height);
        rxFillPath.lineTo(x, rxY);
        txFillPath.moveTo(x, size.height);
        txFillPath.lineTo(x, txY);
      } else {
        rxPath.lineTo(x, rxY);
        txPath.lineTo(x, txY);
        rxFillPath.lineTo(x, rxY);
        txFillPath.lineTo(x, txY);
      }

      if (i == dataPoints.length - 1) {
        rxFillPath.lineTo(x, size.height);
        txFillPath.lineTo(x, size.height);
      }
    }

    // Draw fills
    canvas.drawPath(rxFillPath, rxFill);
    canvas.drawPath(txFillPath, txFill);

    // Draw lines
    canvas.drawPath(rxPath, rxPaint);
    canvas.drawPath(txPath, txPaint);

    // Draw legend
    final legendPaint = Paint()..strokeWidth = 3;
    
    legendPaint.color = rxColor;
    canvas.drawLine(
      const Offset(8, 12),
      const Offset(28, 12),
      legendPaint,
    );
    
    legendPaint.color = txColor;
    canvas.drawLine(
      const Offset(8, 28),
      const Offset(28, 28),
      legendPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
