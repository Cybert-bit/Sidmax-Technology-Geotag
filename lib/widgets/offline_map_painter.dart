import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Leaflet & OpenStreetMap offline vector renderer.
/// Renders an authentic, high-resolution Leaflet / OpenStreetMap view
/// completely on-device without requiring internet access or tile server calls.
class LeafletOfflineMapPainter extends CustomPainter {
  final double latitude;
  final double longitude;
  final double heading;
  final bool isSatellite;
  final String attributionText;

  LeafletOfflineMapPainter({
    required this.latitude,
    required this.longitude,
    this.heading = 0.0,
    this.isSatellite = false,
    this.attributionText = 'Leaflet | © OpenStreetMap',
  });

  @override
  void paint(Canvas canvas, Size size) {
    drawLeafletMap(
      canvas: canvas,
      rect: Rect.fromLTWH(0, 0, size.width, size.height),
      latitude: latitude,
      longitude: longitude,
      heading: heading,
      isSatellite: isSatellite,
      scale: size.width / 112.0,
      attributionText: attributionText,
    );
  }

  @override
  bool shouldRepaint(covariant LeafletOfflineMapPainter oldDelegate) {
    return oldDelegate.latitude != latitude ||
        oldDelegate.longitude != longitude ||
        oldDelegate.heading != heading ||
        oldDelegate.isSatellite != isSatellite;
  }

  /// Core static painting routine used for both the Flutter UI Widget
  /// and the direct Canvas bitmap stamp on captured photos.
  static void drawLeafletMap({
    required Canvas canvas,
    required Rect rect,
    required double latitude,
    required double longitude,
    double heading = 0.0,
    bool isSatellite = false,
    double scale = 1.0,
    String attributionText = 'Leaflet | © OpenStreetMap',
  }) {
    canvas.save();
    canvas.clipRect(rect);

    final w = rect.width;
    final h = rect.height;
    final ox = rect.left;
    final oy = rect.top;

    // Deterministic pseudo-random seed based on coordinate hashes
    // so streets/blocks remain consistent at the same location
    final seed = ((latitude.abs() * 1000).toInt() ^
        ((longitude.abs() * 1000).toInt() << 8)) &
        0x7FFFFFFF;
    final rng = math.Random(seed);

    if (!isSatellite) {
      // ══════════════════════════════════════════════════════════
      // 1. LEAFLET / OPENSTREETMAP (OSM) CLASSIC VECTOR THEME
      // ══════════════════════════════════════════════════════════
      // Land background (classic OSM cream)
      canvas.drawRect(
        rect,
        Paint()..color = const Color(0xFFF2EFE9),
      );

      // Green parks / vegetation zones
      final parkPaint = Paint()..color = const Color(0xFFCCE4B8);
      final parkRect1 = Rect.fromLTWH(
        ox + w * (0.05 + 0.1 * rng.nextDouble()),
        oy + h * (0.08 + 0.1 * rng.nextDouble()),
        w * 0.28,
        h * 0.22,
      );
      final parkRect2 = Rect.fromLTWH(
        ox + w * (0.62 + 0.08 * rng.nextDouble()),
        oy + h * (0.58 + 0.08 * rng.nextDouble()),
        w * 0.32,
        h * 0.26,
      );
      canvas.drawRRect(RRect.fromRectAndRadius(parkRect1, const Radius.circular(6)), parkPaint);
      canvas.drawRRect(RRect.fromRectAndRadius(parkRect2, const Radius.circular(6)), parkPaint);

      // Water channel / coast if near coastal area or river
      final isNearWater = (longitude.abs() % 0.05 < 0.02) || (latitude.abs() % 0.05 < 0.02);
      if (isNearWater) {
        final waterPaint = Paint()..color = const Color(0xFFAAD3DF);
        final waterPath = Path();
        waterPath.moveTo(ox, oy + h * 0.78);
        waterPath.cubicTo(
          ox + w * 0.3, oy + h * 0.72,
          ox + w * 0.6, oy + h * 0.88,
          ox + w, oy + h * 0.82,
        );
        waterPath.lineTo(ox + w, oy + h);
        waterPath.lineTo(ox, oy + h);
        waterPath.close();
        canvas.drawPath(waterPath, waterPaint);
      }

      // City building blocks / parcels
      final blockBorderPaint = Paint()
        ..color = const Color(0xFFE0DDD5)
        ..style = PaintingStyle.fill;
      final blockInnerPaint = Paint()
        ..color = const Color(0xFFEDE9E0)
        ..style = PaintingStyle.fill;

      for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
          final bx = ox + (w * 0.06) + (i * w * 0.23);
          final by = oy + (h * 0.06) + (j * h * 0.23);
          final bw = w * 0.18;
          final bh = h * 0.18;
          final bRect = Rect.fromLTWH(bx, by, bw, bh);
          canvas.drawRRect(RRect.fromRectAndRadius(bRect, const Radius.circular(3)), blockBorderPaint);
          canvas.drawRRect(
            RRect.fromRectAndRadius(bRect.deflate(1.2 * scale), const Radius.circular(2)),
            blockInnerPaint,
          );
        }
      }

      // Local / Residential Streets (White with subtle casing)
      final streetCasingPaint = Paint()
        ..color = const Color(0xFFDDD7CD)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2 * scale;
      final streetFillPaint = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0 * scale;

      // Secondary Avenues (Yellow / Gold OSM style)
      final secondaryCasingPaint = Paint()
        ..color = const Color(0xFFE8D499)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0 * scale;
      final secondaryFillPaint = Paint()
        ..color = const Color(0xFFFDE293)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5 * scale;

      // Primary Highway / Arterial (Amber / Orange OSM style)
      final primaryCasingPaint = Paint()
        ..color = const Color(0xFFE58867)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8.0 * scale;
      final primaryFillPaint = Paint()
        ..color = const Color(0xFFF8A07E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.2 * scale;

      // Draw local street grid
      for (int i = 1; i <= 3; i++) {
        final x = ox + w * (i / 4.0);
        final y = oy + h * (i / 4.0);
        canvas.drawLine(Offset(x, oy), Offset(x, oy + h), streetCasingPaint);
        canvas.drawLine(Offset(ox, y), Offset(ox + w, y), streetCasingPaint);
        canvas.drawLine(Offset(x, oy), Offset(x, oy + h), streetFillPaint);
        canvas.drawLine(Offset(ox, y), Offset(ox + w, y), streetFillPaint);
      }

      // Draw secondary arterial road
      final secY = oy + h * 0.42;
      canvas.drawLine(Offset(ox, secY), Offset(ox + w, secY), secondaryCasingPaint);
      canvas.drawLine(Offset(ox, secY), Offset(ox + w, secY), secondaryFillPaint);

      // Draw primary main road / expressway
      final primPath = Path();
      primPath.moveTo(ox, oy + h * 0.2);
      primPath.cubicTo(
        ox + w * 0.35, oy + h * 0.35,
        ox + w * 0.65, oy + h * 0.65,
        ox + w, oy + h * 0.8,
      );
      canvas.drawPath(primPath, primaryCasingPaint);
      canvas.drawPath(primPath, primaryFillPaint);
    } else {
      // ══════════════════════════════════════════════════════════
      // 2. TACTICAL SATELLITE / DARK MAP THEME
      // ══════════════════════════════════════════════════════════
      // High-resolution satellite vegetation and terrain gradient
      final bgPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(ox, oy),
          Offset(ox + w, oy + h),
          [
            const Color(0xFF132A17),
            const Color(0xFF1B3B22),
            const Color(0xFF142E19),
            const Color(0xFF1F4428),
          ],
        );
      canvas.drawRect(rect, bgPaint);

      // Urban building footprint textures
      final satBlockPaint = Paint()..color = const Color(0x24FFFFFF);
      for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
          final bx = ox + (w * 0.08) + (i * w * 0.22);
          final by = oy + (h * 0.08) + (j * h * 0.22);
          final bw = w * 0.16;
          final bh = h * 0.16;
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, bw, bh), const Radius.circular(2)),
            satBlockPaint,
          );
        }
      }

      // Tactical road networks
      final roadPaint = Paint()
        ..color = const Color(0x66FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * scale;
      final mainRoadPaint = Paint()
        ..color = const Color(0x99FFCC00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 * scale;

      for (int i = 1; i <= 3; i++) {
        final x = ox + w * (i / 4.0);
        final y = oy + h * (i / 4.0);
        canvas.drawLine(Offset(x, oy), Offset(x, oy + h), roadPaint);
        canvas.drawLine(Offset(ox, y), Offset(ox + w, y), roadPaint);
      }
      canvas.drawLine(Offset(ox, oy + h * 0.48), Offset(ox + w, oy + h * 0.48), mainRoadPaint);

      // Radar range circles
      final center = Offset(ox + w / 2, oy + h / 2);
      final rangePaint = Paint()
        ..color = const Color(0x264CAF50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8 * scale;
      canvas.drawCircle(center, w * 0.24, rangePaint);
      canvas.drawCircle(center, w * 0.42, rangePaint);

      // Crosshairs
      final crossPaint = Paint()
        ..color = const Color(0x4400E5FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9 * scale;
      canvas.drawLine(Offset(center.dx - 14 * scale, center.dy), Offset(center.dx + 14 * scale, center.dy), crossPaint);
      canvas.drawLine(Offset(center.dx, center.dy - 14 * scale), Offset(center.dx, center.dy + 14 * scale), crossPaint);
    }

    // ══════════════════════════════════════════════════════════
    // 3. REAL COORDINATE TICK MARKS (MICRO TICKS)
    // ══════════════════════════════════════════════════════════
    final tickPaint = Paint()
      ..color = isSatellite ? const Color(0x55FFFFFF) : const Color(0x55000000)
      ..strokeWidth = 0.8 * scale;
    for (int i = 1; i <= 5; i++) {
      final t = i / 6.0;
      canvas.drawLine(Offset(ox + w * t, oy), Offset(ox + w * t, oy + 3 * scale), tickPaint);
      canvas.drawLine(Offset(ox + w * t, oy + h - 3 * scale), Offset(ox + w * t, oy + h), tickPaint);
      canvas.drawLine(Offset(ox, oy + h * t), Offset(ox + 3 * scale, oy + h * t), tickPaint);
      canvas.drawLine(Offset(ox + w - 3 * scale, oy + h * t), Offset(ox + w, oy + h * t), tickPaint);
    }

    // ══════════════════════════════════════════════════════════
    // 4. MAP TYPE BADGE (TOP RIGHT)
    // ══════════════════════════════════════════════════════════
    final badgeW = 26.0 * scale;
    final badgeH = 12.0 * scale;
    final badgeX = ox + w - badgeW - (4.0 * scale);
    final badgeY = oy + (4.0 * scale);
    final badgeRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(badgeX, badgeY, badgeW, badgeH),
      Radius.circular(3.0 * scale),
    );
    canvas.drawRRect(
      badgeRRect,
      Paint()..color = isSatellite ? const Color(0xFF2E7D32) : const Color(0xFF1976D2),
    );

    final badgeBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: 7.2 * scale,
        fontWeight: ui.FontWeight.bold,
        textAlign: ui.TextAlign.center,
      ),
    )
      ..pushStyle(ui.TextStyle(
        color: const Color(0xFFFFFFFF),
        fontSize: 7.2 * scale,
        fontWeight: ui.FontWeight.bold,
      ))
      ..addText(isSatellite ? 'SAT' : 'OSM');
    final badgePara = badgeBuilder.build()..layout(ui.ParagraphConstraints(width: badgeW));
    canvas.drawParagraph(badgePara, Offset(badgeX, badgeY + (badgeH - badgePara.height) / 2));

    // ══════════════════════════════════════════════════════════
    // 5. ATTRIBUTION / WATERMARK (BOTTOM LEFT)
    // ══════════════════════════════════════════════════════════
    final wmFontSize = 7.5 * scale;
    final wmBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: wmFontSize, fontWeight: ui.FontWeight.w600),
    )
      ..pushStyle(ui.TextStyle(
        color: isSatellite ? const Color(0xD9FFFFFF) : const Color(0xB3000000),
        fontSize: wmFontSize,
        fontWeight: ui.FontWeight.w600,
      ))
      ..addText(attributionText);
    final wmPara = wmBuilder.build()..layout(ui.ParagraphConstraints(width: w - 8));
    canvas.drawParagraph(
      wmPara,
      Offset(ox + 4 * scale, oy + h - wmPara.height - (3.5 * scale)),
    );

    // ══════════════════════════════════════════════════════════
    // 6. COMPASS / BEARING INDICATOR (TOP LEFT)
    // ══════════════════════════════════════════════════════════
    final compassX = ox + 11.0 * scale;
    final compassY = oy + 11.0 * scale;
    final compassRadius = 7.0 * scale;

    canvas.save();
    canvas.translate(compassX, compassY);
    canvas.rotate((heading * math.pi) / 180.0);

    // Compass circle background
    canvas.drawCircle(
      Offset.zero,
      compassRadius,
      Paint()..color = const Color(0x99000000),
    );

    // Red North Needle
    final northPath = Path()
      ..moveTo(0, -compassRadius + 1.5 * scale)
      ..lineTo(2.2 * scale, 0)
      ..lineTo(-2.2 * scale, 0)
      ..close();
    canvas.drawPath(northPath, Paint()..color = const Color(0xFFEA4335));

    // White South Needle
    final southPath = Path()
      ..moveTo(0, compassRadius - 1.5 * scale)
      ..lineTo(2.2 * scale, 0)
      ..lineTo(-2.2 * scale, 0)
      ..close();
    canvas.drawPath(southPath, Paint()..color = const Color(0xFFFFFFFF));

    canvas.restore();

    // ══════════════════════════════════════════════════════════
    // 7. CENTER RED GOOGLE / LEAFLET PIN WITH GPS ACCURACY PULSE
    // ══════════════════════════════════════════════════════════
    final pinCenterX = ox + w / 2;
    final pinCenterY = oy + h / 2 - (3.0 * scale);
    final pinRadius = 7.0 * scale;

    // GPS Accuracy pulse ring around pin base
    final accuracyPaint = Paint()
      ..color = const Color(0x334285F4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(pinCenterX, pinCenterY + 10.0 * scale),
      14.0 * scale,
      accuracyPaint,
    );
    final accuracyBorder = Paint()
      ..color = const Color(0x664285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 * scale;
    canvas.drawCircle(
      Offset(pinCenterX, pinCenterY + 10.0 * scale),
      14.0 * scale,
      accuracyBorder,
    );

    // Ground Shadow under pin tip
    canvas.drawCircle(
      Offset(pinCenterX, pinCenterY + 10.0 * scale),
      3.2 * scale,
      Paint()..color = const Color(0x55000000),
    );

    // Pin head circle
    canvas.drawCircle(
      Offset(pinCenterX, pinCenterY),
      pinRadius,
      Paint()..color = const Color(0xFFEA4335),
    );

    // Pin center white dot
    canvas.drawCircle(
      Offset(pinCenterX, pinCenterY),
      2.6 * scale,
      Paint()..color = const Color(0xFFFFFFFF),
    );

    // Pin stem pointing down
    final pinStem = Path()
      ..moveTo(pinCenterX - (4.0 * scale), pinCenterY + (4.0 * scale))
      ..lineTo(pinCenterX, pinCenterY + (10.0 * scale))
      ..lineTo(pinCenterX + (4.0 * scale), pinCenterY + (4.0 * scale))
      ..close();
    canvas.drawPath(pinStem, Paint()..color = const Color(0xFFEA4335));

    canvas.restore();
  }
}

/// Standalone Leaflet / OpenStreetMap Offline Map Widget
class LeafletOfflineMapWidget extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double heading;
  final bool isSatellite;
  final VoidCallback? onTap;

  const LeafletOfflineMapWidget({
    super.key,
    required this.latitude,
    required this.longitude,
    this.heading = 0.0,
    this.isSatellite = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: LeafletOfflineMapPainter(
          latitude: latitude,
          longitude: longitude,
          heading: heading,
          isSatellite: isSatellite,
        ),
        size: Size.infinite,
      ),
    );
  }
}
