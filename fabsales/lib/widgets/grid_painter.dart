import 'package:flutter/material.dart';

class DotGridPainter extends CustomPainter {
  final Matrix4 transform;
  final double baseSpacing;

  DotGridPainter({required this.transform, this.baseSpacing = 24});

  @override
  void paint(Canvas canvas, Size size) {
    final paintDot = Paint()..color = const Color(0xFFD7DAE3);

    final scale = transform.getMaxScaleOnAxis();
    // Guard against a degenerate (zero/non-finite) scale ever reaching
    // here: without this, the clamp loops below would spin forever on a
    // frame that never finishes, which looks exactly like a frozen white
    // screen with no crash and no error log.
    if (!scale.isFinite || scale <= 0) return;
    double spacing = baseSpacing;
    // keep visual density reasonable while zooming
    while (spacing * scale < 12) {
      spacing *= 2;
    }
    while (spacing * scale > 64) {
      spacing /= 2;
    }

    final inverse = Matrix4.inverted(transform);
    final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
    final bottomRight = MatrixUtils.transformPoint(inverse, Offset(size.width, size.height));

    final startX = (topLeft.dx / spacing).floor() * spacing;
    final startY = (topLeft.dy / spacing).floor() * spacing;

    canvas.save();
    canvas.transform(transform.storage);

    final radius = 1.4 / scale;
    for (double x = startX; x < bottomRight.dx; x += spacing) {
      for (double y = startY; y < bottomRight.dy; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paintDot);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DotGridPainter oldDelegate) {
    return oldDelegate.transform != transform || oldDelegate.baseSpacing != baseSpacing;
  }
}
