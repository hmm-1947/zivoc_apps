import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/canvas_state.dart';
import '../models/shape.dart';
import 'snap_utils.dart';

class ShapePainter extends CustomPainter {
  final List<CanvasShape> shapes;
  final String? selectedId;
  final Set<String> selectedIds;
  final CanvasShape? previewShape;
  final Matrix4 transform;

  /// Combined bounding box of the current multi-selection; when it covers
  /// exactly one shape, resize/scale handles are drawn on it.
  final Rect? selectionBounds;

  /// The in-progress rubber-band selection rectangle, in scene coordinates.
  final Rect? selectionBoxRect;

  /// Pink alignment guide lines to draw while drawing/moving a shape or line.
  final List<AlignmentGuide> alignmentGuides;

  /// Current rotation angle in degrees while the rotate handle is actively
  /// being dragged, shown alongside the W/H label; null otherwise.
  final double? liveRotationDeg;

  /// Id of a text object currently open in the inline editor; it is not
  /// painted here because the TextField overlay draws it instead.
  final String? hiddenShapeId;

  ShapePainter({
    required this.shapes,
    required this.transform,
    this.selectedId,
    Set<String>? selectedIds,
    this.previewShape,
    this.selectionBounds,
    this.selectionBoxRect,
    this.alignmentGuides = const [],
    this.liveRotationDeg,
    this.hiddenShapeId,
  }) : selectedIds = selectedIds ?? const {};

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.transform(transform.storage);
    final inverseScale = 1 / transform.getMaxScaleOnAxis();
    for (final shape in shapes) {
      if (shape.id == hiddenShapeId) continue;
      _drawShape(canvas, shape, selectedIds.contains(shape.id), handleScale: inverseScale);
    }
    if (previewShape != null) {
      _drawShape(canvas, previewShape!, false, isPreview: true, handleScale: inverseScale);
      if (previewShape!.type == ShapeType.line) {
        _drawAngleHint(canvas, previewShape!, inverseScale);
      }
    }

    _drawAlignmentGuides(canvas, inverseScale);

    if (selectionBounds != null) {
      _drawSelectionHandles(canvas, selectionBounds!, inverseScale, resizable: selectedIds.length == 1);
      if (selectedIds.length == 1) {
        _drawDimensionLabel(canvas, selectionBounds!, inverseScale, liveRotationDeg);
      }
    }

    if (selectionBoxRect != null) {
      _drawSelectionBox(canvas, selectionBoxRect!, inverseScale);
    }

    canvas.restore();
  }

  void _drawAlignmentGuides(Canvas canvas, double scale) {
    if (alignmentGuides.isEmpty) return;
    final guidePaint = Paint()
      ..color = const Color(0xFFFF4FA3)
      ..strokeWidth = 1.5 * scale;
    const dashLength = 6.0;
    const gapLength = 5.0;
    for (final guide in alignmentGuides) {
      final total = (guide.b - guide.a).distance;
      if (total < 0.001) continue;
      final direction = (guide.b - guide.a) / total;
      final dash = dashLength * scale;
      final gap = gapLength * scale;
      var travelled = 0.0;
      while (travelled < total) {
        final segEnd = math.min(travelled + dash, total);
        canvas.drawLine(
          guide.a + direction * travelled,
          guide.a + direction * segEnd,
          guidePaint,
        );
        travelled = segEnd + gap;
      }
    }
  }

  /// Draws "W: x  H: y" near the selected shape, in scene space so it
  /// tracks the shape as it moves/resizes. Placed inside the shape when
  /// there's room for the text, otherwise just below it.
  void _drawDimensionLabel(Canvas canvas, Rect bounds, double scale, [double? rotationDeg]) {
    final w = formatLength(bounds.width.abs());
    final h = formatLength(bounds.height.abs());
    final textStyle = TextStyle(
      color: const Color(0xFF8A8D99),
      fontSize: 12 * scale,
      fontWeight: FontWeight.w500,
    );
    // Normalize to a readable 0-359 degree range (rotation can wind past a
    // full turn either way while dragging).
    final angleLabel = rotationDeg == null ? '' : '   ${((rotationDeg % 360 + 360) % 360).round()}°';
    final painter = TextPainter(
      text: TextSpan(text: 'W: $w   H: $h$angleLabel', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    final padding = 4 * scale;
    final fitsInside = bounds.width - padding * 2 >= painter.width &&
        bounds.height - padding * 2 >= painter.height;

    final Offset origin;
    if (fitsInside) {
      origin = Offset(
        bounds.center.dx - painter.width / 2,
        bounds.bottom - padding - painter.height,
      );
    } else {
      origin = Offset(
        bounds.center.dx - painter.width / 2,
        bounds.bottom + padding,
      );
    }
    painter.paint(canvas, origin);
  }

  void _drawSelectionBox(Canvas canvas, Rect box, double scale) {
    final fillPaint = Paint()..color = const Color(0x1A4C6FFF);
    final strokePaint = Paint()
      ..color = const Color(0xFF4C6FFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * scale;
    canvas.drawRect(box, fillPaint);
    canvas.drawRect(box, strokePaint);
  }

  void _drawSelectionHandles(Canvas canvas, Rect bounds, double scale, {required bool resizable}) {
    final boxPaint = Paint()
      ..color = const Color(0xFF4C6FFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * scale;
    canvas.drawRect(bounds.inflate(6 * scale), boxPaint);

    if (!resizable) return;

    final handleFill = Paint()..color = Colors.white;
    final handleStroke = Paint()
      ..color = const Color(0xFF4C6FFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * scale;
    final r = 5 * scale;

    final points = [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomLeft,
      bounds.bottomRight,
      Offset(bounds.center.dx, bounds.top),
      Offset(bounds.center.dx, bounds.bottom),
      Offset(bounds.left, bounds.center.dy),
      Offset(bounds.right, bounds.center.dy),
    ];
    for (final p in points) {
      canvas.drawCircle(p, r, handleFill);
      canvas.drawCircle(p, r, handleStroke);
    }

    // Rotate icon: a small grip just below the bottom edge of the selection
    // box (matches _rotateHandlePosition in infinite_canvas.dart so the drawn
    // icon lines up with its hit area). Drag it to rotate the shape.
    final rotateCenter = Offset(bounds.center.dx, bounds.bottom + 26.0 * scale);
    final rotateRadius = 9.0 * scale;
    canvas.drawCircle(rotateCenter, rotateRadius, handleFill);
    canvas.drawCircle(rotateCenter, rotateRadius, handleStroke);

    // Circular arrow inside the grip, with an arrowhead, to read as "rotate".
    final arcRadius = rotateRadius * 0.55;
    final arcRect = Rect.fromCircle(center: rotateCenter, radius: arcRadius);
    final arrowPaint = Paint()
      ..color = const Color(0xFF4C6FFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * scale
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, -math.pi * 0.9, math.pi * 1.4, false, arrowPaint);
    // Arrowhead at the arc's end, pointing along the direction of travel.
    const arcStart = -math.pi * 0.9;
    const arcSweep = math.pi * 1.4;
    const endAngle = arcStart + arcSweep;
    final tip = Offset(
      rotateCenter.dx + arcRadius * math.cos(endAngle),
      rotateCenter.dy + arcRadius * math.sin(endAngle),
    );
    final forward = Offset(-math.sin(endAngle), math.cos(endAngle)); // tangent
    final across = Offset(-forward.dy, forward.dx); // perpendicular
    final headLen = 3.0 * scale;
    final head = Path()
      ..moveTo(tip.dx + forward.dx * headLen, tip.dy + forward.dy * headLen)
      ..lineTo(tip.dx + across.dx * headLen * 0.7, tip.dy + across.dy * headLen * 0.7)
      ..lineTo(tip.dx - across.dx * headLen * 0.7, tip.dy - across.dy * headLen * 0.7)
      ..close();
    canvas.drawPath(head, Paint()..color = const Color(0xFF4C6FFF));
  }

  void _drawShape(Canvas canvas, CanvasShape shape, bool selected, {bool isPreview = false, double handleScale = 1}) {
    final hasRotation = shape.rotation != 0 && shape.freePoints.isEmpty;
    if (hasRotation) {
      canvas.save();
      canvas.translate(shape.rect.center.dx, shape.rect.center.dy);
      canvas.rotate(shape.rotation);
      canvas.translate(-shape.rect.center.dx, -shape.rect.center.dy);
    }
    final rect = shape.rect;
    final strokePaint = Paint()
      ..color = isPreview ? shape.style.strokeColor.withValues(alpha: 0.6) : shape.style.strokeColor
      ..strokeWidth = shape.style.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = shape.style.fillColor
      ..style = PaintingStyle.fill;

    void fillAndStroke(Path path) {
      if (shape.style.filled) canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }

    if (shape.type == ShapeType.text) {
      _drawTextShape(canvas, shape, rect);
      if (hasRotation) canvas.restore();
      return;
    }

    if (shape.type == ShapeType.dimension) {
      _drawLinearDimension(canvas, shape, selected, handleScale);
      if (hasRotation) canvas.restore();
      return;
    }

    if (shape.type == ShapeType.radiusDimension) {
      _drawRadiusDimension(canvas, shape, selected, handleScale);
      if (hasRotation) canvas.restore();
      return;
    }

    if (shape.type == ShapeType.angleDimension) {
      _drawAngleDimension(canvas, shape, selected, handleScale);
      if (hasRotation) canvas.restore();
      return;
    }

    switch (shape.type) {
      case ShapeType.rectangle:
      case ShapeType.square:
        fillAndStroke(Path()..addRect(rect));
        break;

      case ShapeType.circle:

        fillAndStroke(Path()..addOval(rect));
        break;

      case ShapeType.semiCircle:
        fillAndStroke(_semiCirclePath(rect));
        break;

      case ShapeType.triangle:
        fillAndStroke(Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close());
        break;

      case ShapeType.rightTriangle:
        fillAndStroke(Path()
          ..moveTo(rect.left, rect.top)
          ..lineTo(rect.left, rect.bottom)
          ..lineTo(rect.right, rect.bottom)
          ..close());
        break;

      case ShapeType.diamond:
        fillAndStroke(Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom)
          ..lineTo(rect.left, rect.center.dy)
          ..close());
        break;

      case ShapeType.pentagon:
        fillAndStroke(_polygonPath(rect, 5, rotationOffset: -math.pi / 2));
        break;

      case ShapeType.hexagon:
        fillAndStroke(_polygonPath(rect, 6));
        break;


      case ShapeType.arrow:
        _drawArrow(canvas, strokePaint, shape.topLeft, shape.bottomRight, isDouble: false);
        break;

      case ShapeType.doubleArrow:
        _drawArrow(canvas, strokePaint, shape.topLeft, shape.bottomRight, isDouble: true);
        break;

      case ShapeType.line:
        canvas.drawLine(shape.topLeft, shape.bottomRight, strokePaint);
        break;

      case ShapeType.curvedLine:
        _drawCurvedLine(canvas, shape, strokePaint);
        break;

      case ShapeType.door:
        _drawDoor(canvas, rect, strokePaint);
        break;

      case ShapeType.doorDouble:
        _drawDoubleDoor(canvas, rect, strokePaint);
        break;

      case ShapeType.window:
        _drawWindow(canvas, rect, strokePaint);
        break;

      case ShapeType.windowSliding:
        _drawSlidingWindow(canvas, rect, strokePaint);
        break;

      case ShapeType.text:
        _drawText(canvas, rect, shape);
        break;

      // Dimensions are drawn earlier in this method and return before here.
      case ShapeType.dimension:
      case ShapeType.radiusDimension:
      case ShapeType.angleDimension:
        break;
    }

    if (selected) {
      // A light highlight outline per selected shape; the authoritative
      // selection box and resize/scale handles are drawn once for the whole
      // selection in _drawSelectionHandles (see paint()), so multi-select
      // doesn't produce overlapping handle clusters per shape.
      final highlightPaint = Paint()
        ..color = const Color(0xFF4C6FFF).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 * handleScale;
      canvas.drawRect(rect.inflate(4 * handleScale), highlightPaint);
    }

    if (hasRotation) canvas.restore();
  }

  Path _semiCirclePath(Rect rect) {
    // A true half-ellipse whose flat edge is rect's bottom edge and whose
    // dome reaches rect.top at the horizontal center (mirrors
    // _semiCircleOutlinePath in shape_hit_test.dart so drawing and hit
    // testing agree exactly).
    final ellipseRect = Rect.fromLTWH(rect.left, rect.bottom - rect.height * 2, rect.width, rect.height * 2);
    return Path()
      ..addArc(ellipseRect, math.pi, -math.pi)
      ..close();
  }

  Path _polygonPath(Rect rect, int sides, {double rotationOffset = 0}) {
    final path = Path();
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final rx = rect.width / 2;
    final ry = rect.height / 2;
    for (int i = 0; i < sides; i++) {
      final angle = rotationOffset + (2 * math.pi * i / sides);
      final point = Offset(cx + rx * math.cos(angle), cy + ry * math.sin(angle));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }


  void _drawArrow(Canvas canvas, Paint paint, Offset from, Offset to, {bool isDouble = false}) {
    canvas.drawLine(from, to, paint);
    final angle = (to - from).direction;
    const headLength = 12.0;
    const headAngle = math.pi / 7;

    void head(Offset tip, double dir) {
      final p1 = tip - Offset(headLength * math.cos(dir - headAngle), headLength * math.sin(dir - headAngle));
      final p2 = tip - Offset(headLength * math.cos(dir + headAngle), headLength * math.sin(dir + headAngle));
      canvas.drawLine(tip, p1, paint);
      canvas.drawLine(tip, p2, paint);
    }

    head(to, angle);
    if (isDouble) head(from, angle + math.pi);
  }

  static const double _dimExtOvershoot = 8; // extension line past the dimension line
  static const double _dimExtGap = 4;       // gap between object point and extension start
  static const double _dimArrowLen = 10;
  static const double _dimArrowHalfWidth = 3.5;

  Paint _dimPaint(CanvasShape shape, bool selected, double handleScale) {
    return Paint()
      ..color = selected ? const Color(0xFF4C6FFF) : shape.style.strokeColor
      ..strokeWidth = shape.style.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
  }

  /// Filled CAD-style arrowhead with its tip at [tip], pointing along [dir]
  /// (radians). The arrow body sits behind the tip, so it reads as an
  /// arrow ending exactly on the measured point.
  void _drawArrowHead(Canvas canvas, Offset tip, double dir, Paint stroke) {
    final back = Offset(math.cos(dir), math.sin(dir)) * -_dimArrowLen;
    final perp = Offset(-math.sin(dir), math.cos(dir)) * _dimArrowHalfWidth;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx + back.dx + perp.dx, tip.dy + back.dy + perp.dy)
      ..lineTo(tip.dx + back.dx - perp.dx, tip.dy + back.dy - perp.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke.color
        ..style = PaintingStyle.fill,
    );
  }

  /// Draws the dimension label centred horizontally on [at], with [lift]
  /// pushing it above that point. Always drawn upright/unrotated — even on
  /// a steep or reversed dimension line — so the number stays straight and
  /// readable instead of running sideways or upside down.
  /// Direction (radians) of the ray from [vertex] along [line]: toward
  /// whichever endpoint is farther from the vertex.
  double _rayAngle(CanvasShape line, Offset vertex) {
    final far = (line.topLeft - vertex).distance >= (line.bottomRight - vertex).distance
        ? line.topLeft
        : line.bottomRight;
    final d = far - vertex;
    return math.atan2(d.dy, d.dx);
  }

  /// Angle marker: an arc at the vertex where two lines meet, with the
  /// angle in degrees beside it. Looks the lines up by id so the arc
  /// follows them when they move.
  void _drawAngleDimension(Canvas canvas, CanvasShape shape, bool selected, double handleScale) {
    final a = shapes.firstWhere(
      (s) => s.id == shape.refShapeId,
      orElse: () => shape,
    );
    final b = shapes.firstWhere(
      (s) => s.id == shape.refShapeId2,
      orElse: () => shape,
    );
    if (identical(a, shape) || identical(b, shape)) return;

    final paint = _dimPaint(shape, selected, handleScale);
    final vertex = shape.topLeft;
    final arc = angleArcFor(
      _rayAngle(a, vertex),
      _rayAngle(b, vertex),
      outside: shape.angleOutside,
    );
    // Radius is in scene units so the arc scales with its lines and vertex.
    final r = shape.angleRadius;
    canvas.drawArc(Rect.fromCircle(center: vertex, radius: r), arc.startAngle, arc.sweep, false, paint);

    // Label sits on the bisector, just beyond the arc.
    final unit = Offset(math.cos(arc.bisector), math.sin(arc.bisector));
    _drawDimLabel(canvas, shape, vertex + unit * (r + 14 * handleScale), 0, outward: unit);
  }

  /// Hint text showing a line's angle from horizontal, placed beside its
  /// midpoint while the line is being drawn.
  void _drawAngleHint(Canvas canvas, CanvasShape line, double inverseScale) {
    final delta = line.bottomRight - line.topLeft;
    if (delta.distance < 1) return;
    var deg = math.atan2(delta.dy, delta.dx) * 180 / math.pi;
    // Fold to 0..180 so the hint doesn't flip for a reversed drag.
    deg = ((deg % 180) + 180) % 180;
    final mid = (line.topLeft + line.bottomRight) / 2;
    final normal = Offset(-delta.dy, delta.dx) / delta.distance;
    final at = mid + normal * (14 * inverseScale);
    final painter = TextPainter(
      text: TextSpan(
        text: '${deg.toStringAsFixed(1)}°',
        style: TextStyle(
          color: line.style.strokeColor,
          fontSize: 12 * inverseScale,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
  }

  void _drawDimLabel(
    Canvas canvas,
    CanvasShape shape,
    Offset at,
    double lift, {
    String prefix = '',
    Offset? outward,
  }) {
    final style = shape.style;
    final painter = TextPainter(
      text: TextSpan(
        text: '$prefix${shape.text ?? ''}',
        style: TextStyle(
          color: style.strokeColor,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final hw = painter.width / 2;
    final hh = painter.height / 2;
    if (outward != null) {
      // Push the label past the dimension line, away from the shape, by
      // its own half-extent along that direction, so it never sits on the line.
      final ext = outward.dx.abs() * hw + outward.dy.abs() * hh + 6;
      final c = at + outward * ext;
      painter.paint(canvas, Offset(c.dx - hw, c.dy - hh));
      return;
    }
    painter.paint(canvas, Offset(at.dx - hw, at.dy - painter.height - lift));
  }

  void _drawLinearDimension(Canvas canvas, CanvasShape shape, bool selected, double handleScale) {
    final a = shape.topLeft;
    final b = shape.bottomRight;
    final delta = b - a;
    final length = delta.distance;
    if (length < 1) return;
    final paint = _dimPaint(shape, selected, handleScale);
    final dir = math.atan2(delta.dy, delta.dx);
    final unit = Offset(math.cos(dir), math.sin(dir));
    final normal = Offset(-unit.dy, unit.dx);

    // Dimension line sits offset from the measured points along the normal.
    final offset = shape.freePoints.isNotEmpty ? shape.freePoints.first.dx : 28.0;
    final dimA = a + normal * offset;
    final dimB = b + normal * offset;

    // Extension lines: from just off each measured point, past the dimension line.
    final extSide = offset >= 0 ? 1.0 : -1.0;
    // They start on the same side as the dimension line and stretch or
    // shrink as it is dragged; hidden when the line sits on the points.
    if (offset.abs() > _dimExtGap) {
      canvas.drawLine(a + normal * (_dimExtGap * extSide), dimA + normal * (_dimExtOvershoot * extSide), paint);
      canvas.drawLine(b + normal * (_dimExtGap * extSide), dimB + normal * (_dimExtOvershoot * extSide), paint);
    }

    // Dimension line with arrowheads at both ends, pointing outward.
    canvas.drawLine(dimA, dimB, paint);
    _drawArrowHead(canvas, dimA, dir + math.pi, paint);
    _drawArrowHead(canvas, dimB, dir, paint);

    // Label above the line (on the side opposite the offset).
    final mid = Offset((dimA.dx + dimB.dx) / 2, (dimA.dy + dimB.dy) / 2);
    _drawDimLabel(canvas, shape, mid, 0, outward: normal * extSide);
  }

  /// CAD-style radius leader: drawn entirely outside the circle. [topLeft]
  /// is the point on the circumference (the arrow touches it, pointing
  /// inward); [bottomRight] is the outer end, away from the circle, where
  /// the label sits. Nothing is drawn from the centre outward.
  void _drawRadiusDimension(Canvas canvas, CanvasShape shape, bool selected, double handleScale) {
    final rim = shape.topLeft;
    final outer = shape.bottomRight;
    final delta = outer - rim;
    if (delta.distance < 1) return;
    final paint = _dimPaint(shape, selected, handleScale);
    final outDir = math.atan2(delta.dy, delta.dx);

    // Leader line from the outer (label) end in to the rim, arrowhead
    // touching the circumference and pointing inward toward the centre.
    canvas.drawLine(outer, rim, paint);
    _drawArrowHead(canvas, rim, outDir + math.pi, paint);

    // Label sits beyond the outer end, on the same line, with the R symbol.
    final unit = Offset(math.cos(outDir), math.sin(outDir));
    final labelAt = outer + unit * 20;
    _drawDimLabel(canvas, shape, labelAt, 6, prefix: 'R');
  }

  /// Draws a text object: the saved font, size, colour and B/I/U style,
  /// laid out to the shape's width and centred within its rect. Text
  /// objects being edited are skipped here (the inline TextField shows them).
  void _drawTextShape(Canvas canvas, CanvasShape shape, Rect rect) {
    final style = shape.style;
    final content = shape.text ?? '';
    final base = fontTextStyle(style.fontFamily, size: style.fontSize, color: style.textColor);
    final textStyle = base.copyWith(
      fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
      decoration: style.underline ? TextDecoration.underline : TextDecoration.none,
      decorationColor: style.textColor,
    );
    final painter = TextPainter(
      text: TextSpan(text: content, style: textStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width > 0 ? rect.width : double.infinity);

    final origin = Offset(
      rect.center.dx - painter.width / 2,
      rect.center.dy - painter.height / 2,
    );
    painter.paint(canvas, origin);
  }

  void _drawCurvedLine(Canvas canvas, CanvasShape shape, Paint paint) {
    final pts = shape.freePoints.isNotEmpty ? shape.freePoints : [shape.topLeft, shape.bottomRight];
    if (pts.length < 2) return;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 2) {
      final mid = Offset((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2 - 40);
      path.quadraticBezierTo(mid.dx, mid.dy, pts[1].dx, pts[1].dy);
    } else {
      for (int i = 1; i < pts.length - 1; i++) {
        final mid = Offset((pts[i].dx + pts[i + 1].dx) / 2, (pts[i].dy + pts[i + 1].dy) / 2);
        path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(pts.last.dx, pts.last.dy);
    }
    canvas.drawPath(path, paint);
  }

  void _drawDoor(Canvas canvas, Rect rect, Paint paint) {
    final hingeX = rect.left;
    final hingeY = rect.bottom;
    final width = rect.width.abs();
    canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.right, rect.bottom), paint);
    final arcRect = Rect.fromCircle(center: Offset(hingeX, hingeY), radius: width);
    canvas.drawArc(arcRect, -math.pi / 2, math.pi / 2, false, paint);
    canvas.drawLine(Offset(hingeX, hingeY), Offset(hingeX, hingeY - width), paint);
  }

  void _drawDoubleDoor(Canvas canvas, Rect rect, Paint paint) {
    final midX = rect.center.dx;
    canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.right, rect.bottom), paint);
    final leftW = midX - rect.left;
    final leftArc = Rect.fromCircle(center: Offset(rect.left, rect.bottom), radius: leftW);
    canvas.drawArc(leftArc, -math.pi / 2, math.pi / 2, false, paint);
    canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.left, rect.bottom - leftW), paint);

    final rightW = rect.right - midX;
    final rightArc = Rect.fromCircle(center: Offset(rect.right, rect.bottom), radius: rightW);
    canvas.drawArc(rightArc, math.pi, math.pi / 2, false, paint);
    canvas.drawLine(Offset(rect.right, rect.bottom), Offset(rect.right, rect.bottom - rightW), paint);
  }

  void _drawWindow(Canvas canvas, Rect rect, Paint paint) {
    canvas.drawRect(rect, paint);
    canvas.drawLine(Offset(rect.left, rect.center.dy), Offset(rect.right, rect.center.dy), paint);
    canvas.drawLine(Offset(rect.center.dx, rect.top), Offset(rect.center.dx, rect.bottom), paint);
  }

  void _drawSlidingWindow(Canvas canvas, Rect rect, Paint paint) {
    canvas.drawRect(rect, paint);
    final thirdW = rect.width / 3;
    canvas.drawLine(Offset(rect.left + thirdW, rect.top), Offset(rect.left + thirdW, rect.bottom), paint);
    canvas.drawLine(Offset(rect.left + 2 * thirdW, rect.top), Offset(rect.left + 2 * thirdW, rect.bottom), paint);
    final arrowPaint = Paint()
      ..color = paint.color
      ..strokeWidth = paint.strokeWidth * 0.7;
    canvas.drawLine(
      Offset(rect.left + 0.15 * rect.width, rect.center.dy),
      Offset(rect.left + 0.85 * rect.width, rect.center.dy),
      arrowPaint,
    );
  }

  void _drawText(Canvas canvas, Rect rect, CanvasShape shape) {
    final painter = TextPainter(
      text: TextSpan(
        text: shape.text ?? '',
        style: TextStyle(color: shape.style.strokeColor, fontSize: 16),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout(maxWidth: rect.width.abs());
    painter.paint(canvas, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant ShapePainter oldDelegate) {
    return true;
  }
}
