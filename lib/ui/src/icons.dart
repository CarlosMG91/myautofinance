import 'package:flutter/material.dart';

/// Identificadores de contornos propios. Renderizar con AfIcon, no Icon.
abstract final class AfIcons {
  static const home = IconData(0, fontFamily: 'AfOutline');
  static const calendar = IconData(1, fontFamily: 'AfOutline');
  static const receipt = IconData(2, fontFamily: 'AfOutline');
  static const account = IconData(3, fontFamily: 'AfOutline');
  static const analysis = IconData(4, fontFamily: 'AfOutline');
  static const more = IconData(5, fontFamily: 'AfOutline');
  static const management = IconData(6, fontFamily: 'AfOutline');
  static const importFile = IconData(7, fontFamily: 'AfOutline');
  static const upload = IconData(8, fontFamily: 'AfOutline');
  static const download = IconData(9, fontFamily: 'AfOutline');
  static const edit = IconData(10, fontFamily: 'AfOutline');
  static const confirm = IconData(11, fontFamily: 'AfOutline');
  static const close = IconData(12, fontFamily: 'AfOutline');
  static const category = IconData(13, fontFamily: 'AfOutline');
  static const back = IconData(14, fontFamily: 'AfOutline');
  static const chevronDown = IconData(15, fontFamily: 'AfOutline');
  static const arrowUp = IconData(16, fontFamily: 'AfOutline');
  static const arrowDown = IconData(17, fontFamily: 'AfOutline');
}

class AfIcon extends StatelessWidget {
  const AfIcon(this.icon, {super.key, this.label, this.color, this.size = 24});
  final IconData icon;
  final String? label;
  final Color? color;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    excludeSemantics: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _OutlinePainter(
          icon.codePoint,
          color ??
              IconTheme.of(context).color ??
              Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ),
  );
}

class _OutlinePainter extends CustomPainter {
  const _OutlinePainter(this.glyph, this.color);
  final int glyph;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..strokeWidth = 1.75
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(List<Offset> points) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, pen);
    }

    void box(double x, double y, double w, double h) => canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        const Radius.circular(1),
      ),
      pen,
    );
    switch (glyph) {
      case 0:
        line(const [Offset(3, 10), Offset(12, 3), Offset(21, 10)]);
        line(const [
          Offset(5, 9),
          Offset(5, 21),
          Offset(10, 21),
          Offset(10, 14),
          Offset(14, 14),
          Offset(14, 21),
          Offset(19, 21),
          Offset(19, 9),
        ]);
      case 1:
        box(4, 5, 16, 16);
        line(const [Offset(4, 10), Offset(20, 10)]);
        for (final x in [8.0, 16.0]) {
          line([Offset(x, 3), Offset(x, 7)]);
        }
        line(const [Offset(8, 14), Offset(10, 14)]);
        line(const [Offset(14, 17), Offset(16, 17)]);
      case 2:
        line(const [
          Offset(6, 3),
          Offset(18, 3),
          Offset(18, 21),
          Offset(15, 19),
          Offset(12, 21),
          Offset(9, 19),
          Offset(6, 21),
          Offset(6, 3),
        ]);
        for (final y in [7.0, 11.0, 15.0]) {
          line([Offset(9, y), Offset(15, y)]);
        }
      case 3:
        line(const [Offset(3, 8), Offset(12, 3), Offset(21, 8), Offset(3, 8)]);
        for (final x in [6.0, 12.0, 18.0]) {
          line([Offset(x, 9), Offset(x, 19)]);
        }
        line(const [Offset(3, 21), Offset(21, 21)]);
      case 4:
        line(const [Offset(3, 21), Offset(21, 21)]);
        box(5, 14, 3, 5);
        box(11, 9, 3, 10);
        box(17, 3, 3, 16);
      case 5:
        for (final x in [5.0, 12.0, 19.0]) {
          canvas.drawCircle(Offset(x, 12), 1, pen);
        }
      case 6:
        canvas.drawCircle(const Offset(12, 12), 6, pen);
        canvas.drawCircle(const Offset(12, 12), 2, pen);
        for (final p in const [
          Offset(12, 2),
          Offset(12, 22),
          Offset(2, 12),
          Offset(22, 12),
        ]) {
          line([Offset(12 + (p.dx - 12) * .65, 12 + (p.dy - 12) * .65), p]);
        }
      case 7:
        line(const [
          Offset(12, 3),
          Offset(20, 3),
          Offset(20, 21),
          Offset(12, 21),
        ]);
        line(const [Offset(3, 12), Offset(15, 12), Offset(10, 7)]);
        line(const [Offset(15, 12), Offset(10, 17)]);
      case 8 || 9:
        final top = glyph == 8 ? 4.0 : 18.0;
        final base = glyph == 8 ? 18.0 : 4.0;
        line([Offset(12, base), Offset(12, top)]);
        line([
          Offset(7, top + (glyph == 8 ? 5 : -5)),
          Offset(12, top),
          Offset(17, top + (glyph == 8 ? 5 : -5)),
        ]);
        line(const [
          Offset(4, 19),
          Offset(4, 22),
          Offset(20, 22),
          Offset(20, 19),
        ]);
      case 10:
        line(const [
          Offset(4, 16),
          Offset(16, 4),
          Offset(20, 8),
          Offset(8, 20),
          Offset(3, 21),
          Offset(4, 16),
        ]);
      case 11:
        line(const [Offset(4, 12), Offset(10, 18), Offset(20, 6)]);
      case 12:
        line(const [Offset(5, 5), Offset(19, 19)]);
        line(const [Offset(19, 5), Offset(5, 19)]);
      case 13:
        for (final x in [3.0, 14.0]) {
          for (final y in [3.0, 14.0]) {
            box(x, y, 7, 7);
          }
        }
      case 14:
        line(const [Offset(10, 5), Offset(3, 12), Offset(10, 19)]);
        line(const [Offset(3, 12), Offset(21, 12)]);
      case 15:
        line(const [Offset(6, 9), Offset(12, 15), Offset(18, 9)]);
      case 16 || 17:
        final tip = glyph == 16 ? 4.0 : 20.0;
        final base = glyph == 16 ? 20.0 : 4.0;
        line([Offset(12, base), Offset(12, tip)]);
        line([
          Offset(6, tip + (glyph == 16 ? 6 : -6)),
          Offset(12, tip),
          Offset(18, tip + (glyph == 16 ? 6 : -6)),
        ]);
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}
