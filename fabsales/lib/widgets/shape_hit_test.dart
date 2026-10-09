import 'dart:math' as math;
import 'dart:ui';
import '../models/shape.dart';

const double kStrokeHitTolerancePx = 8.0;

Path? _shapeOutlinePath(CanvasShape shape) {
  final rect = shape.rect;
  switch (shape.type) {
    case ShapeType.rectangle:
    case ShapeType.square:
    case ShapeType.door:
    case ShapeType.doorDouble:
    case ShapeType.window:
    case ShapeType.windowSliding:
    case ShapeType.text:
      return Path()..addRect(rect);

    case ShapeType.circle:

      return Path()..addOval(rect);

    case ShapeType.semiCircle:
      return _semiCircleOutlinePath(rect);

    case ShapeType.triangle:
      return Path()
        ..moveTo(rect.center.dx, rect.top)
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.left, rect.bottom)
        ..close();

    case ShapeType.rightTriangle:
      return Path()
        ..moveTo(rect.left, rect.top)
        ..lineTo(rect.left, rect.bottom)
        ..lineTo(rect.right, rect.bottom)
        ..close();

    case ShapeType.diamond:
      return Path()
        ..moveTo(rect.center.dx, rect.top)
        ..lineTo(rect.right, rect.center.dy)
        ..lineTo(rect.center.dx, rect.bottom)
        ..lineTo(rect.left, rect.center.dy)
        ..close();

    case ShapeType.pentagon:
      return _polygonPath(rect, 5, rotationOffset: -math.pi / 2);

    case ShapeType.hexagon:
      return _polygonPath(rect, 6);


    case ShapeType.arrow:
    case ShapeType.doubleArrow:
    case ShapeType.line:
    case ShapeType.dimension:
    case ShapeType.radiusDimension:
    case ShapeType.angleDimension:
      return null;

    case ShapeType.curvedLine:
      return null;
  }
}

/// A true half-ellipse whose flat edge is rect's bottom edge and whose
/// dome reaches rect.top at the horizontal center. Built as the top half
/// of a full ellipse twice rect's height, centered on rect's bottom edge,
/// so the arc never self-intersects (unlike arcToPoint with radius=height).
Path _semiCircleOutlinePath(Rect rect) {
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


double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lenSq < 1e-9) return (p - a).distance;
  var t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lenSq;
  t = t.clamp(0.0, 1.0);
  final proj = a + ab * t;
  return (p - proj).distance;
}

double _distanceToPolyline(Offset p, List<Offset> pts, {bool closed = false}) {
  var best = double.infinity;
  for (int i = 0; i < pts.length - 1; i++) {
    final d = _distanceToSegment(p, pts[i], pts[i + 1]);
    if (d < best) best = d;
  }
  if (closed && pts.length > 1) {
    final d = _distanceToSegment(p, pts.last, pts.first);
    if (d < best) best = d;
  }
  return best;
}

bool hitTestShape(CanvasShape shape, Offset rawPoint) {
  // Undo the shape's rotation around its center so hit-testing can work in
  // the shape's own unrotated local space.
  Offset point = rawPoint;
  if (shape.rotation != 0 && shape.freePoints.isEmpty) {
    final center = shape.rect.center;
    final rel = rawPoint - center;
    final cosA = math.cos(-shape.rotation);
    final sinA = math.sin(-shape.rotation);
    point = center + Offset(rel.dx * cosA - rel.dy * sinA, rel.dx * sinA + rel.dy * cosA);
  }
  switch (shape.type) {
    case ShapeType.line:
    case ShapeType.arrow:
    case ShapeType.doubleArrow:
    case ShapeType.radiusDimension:
    case ShapeType.angleDimension:
      return _distanceToSegment(point, shape.topLeft, shape.bottomRight) <= kStrokeHitTolerancePx;

    case ShapeType.dimension:
      // Grab the dimension line itself (offset from the measured points) or
      // either extension line, not the measured edge underneath.
      final v = shape.bottomRight - shape.topLeft;
      final len = v.distance;
      if (len < 0.5) return false;
      final off = shape.freePoints.isNotEmpty ? shape.freePoints.first.dx : 28.0;
      final n = Offset(-v.dy / len, v.dx / len) * off;
      final dimA = shape.topLeft + n, dimB = shape.bottomRight + n;
      return _distanceToSegment(point, dimA, dimB) <= kStrokeHitTolerancePx ||
          _distanceToSegment(point, shape.topLeft, dimA) <= kStrokeHitTolerancePx ||
          _distanceToSegment(point, shape.bottomRight, dimB) <= kStrokeHitTolerancePx;

    case ShapeType.curvedLine:
      final pts = shape.freePoints.isNotEmpty ? shape.freePoints : [shape.topLeft, shape.bottomRight];
      // Hit the stroke itself, or anywhere inside its bounding box so the
      // whole drawn object is grabbable and draggable.
      if (shape.rect.inflate(kStrokeHitTolerancePx).contains(point)) return true;
      return _distanceToPolyline(point, pts) <= kStrokeHitTolerancePx;

    default:
      final path = _shapeOutlinePath(shape);
      if (path == null) return shape.rect.inflate(kStrokeHitTolerancePx).contains(point);
      // Clicking anywhere inside the shape's outline selects it, regardless
      // of whether it's visually filled — an unfilled rectangle is still
      // "the shape" for selection purposes, not just its stroke.
      if (path.contains(point)) return true;
      final metrics = path.computeMetrics();
      for (final metric in metrics) {
        for (double d = 0; d <= metric.length; d += 4) {
          final tangent = metric.getTangentForOffset(d);
          if (tangent != null && (tangent.position - point).distance <= kStrokeHitTolerancePx) {
            return true;
          }
        }
      }
      return false;
  }
}
/// Canvas-space outline of [shape] as a dense polyline, used to measure the
/// distance between two shapes. Lines are sampled along their length; other
/// shapes are sampled along their outline and rotated into place.
List<Offset> measureOutline(CanvasShape shape, {int samples = 240}) {
  if (shape.type == ShapeType.line ||
      shape.type == ShapeType.arrow ||
      shape.type == ShapeType.doubleArrow) {
    final a = shape.topLeft, b = shape.bottomRight;
    return [for (int i = 0; i <= samples; i++) Offset.lerp(a, b, i / samples)!];
  }
  final path = _shapeOutlinePath(shape);
  if (path == null) return const [];
  final center = shape.rect.center;
  final rotate = shape.rotation != 0 && shape.freePoints.isEmpty;
  final cosA = math.cos(shape.rotation);
  final sinA = math.sin(shape.rotation);
  final pts = <Offset>[];
  for (final metric in path.computeMetrics()) {
    for (int i = 0; i <= samples; i++) {
      final tangent = metric.getTangentForOffset(metric.length * i / samples);
      if (tangent == null) continue;
      var p = tangent.position;
      if (rotate) {
        final rel = p - center;
        p = center + Offset(rel.dx * cosA - rel.dy * sinA, rel.dx * sinA + rel.dy * cosA);
      }
      pts.add(p);
    }
  }
  return pts;
}

/// The closest pair of points between two shapes and the distance between them.
class ShapeGap {
  final Offset a;
  final Offset b;
  final double distance;
  const ShapeGap(this.a, this.b, this.distance);
}

/// Shortest distance between the outlines of [s] and [t], with the two points
/// where it is measured. Null if either shape has no measurable outline.
ShapeGap? closestBetweenShapes(CanvasShape s, CanvasShape t) {
  final pa = measureOutline(s);
  final pb = measureOutline(t);
  if (pa.length < 2 || pb.length < 2) return null;
  var best = double.infinity;
  var bestA = pa.first;
  var bestB = pb.first;

  // Each sample of one outline against every segment of the other, both ways.
  for (final p in pa) {
    for (int j = 0; j < pb.length - 1; j++) {
      final c = _closestOnSegment(p, pb[j], pb[j + 1]);
      final d = (c - p).distance;
      if (d < best) {
        best = d;
        bestA = p;
        bestB = c;
      }
    }
  }
  for (final q in pb) {
    for (int i = 0; i < pa.length - 1; i++) {
      final c = _closestOnSegment(q, pa[i], pa[i + 1]);
      final d = (c - q).distance;
      if (d < best) {
        best = d;
        bestA = c;
        bestB = q;
      }
    }
  }
  return ShapeGap(bestA, bestB, best);
}

Offset _closestOnSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-12) return a;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(0.0, 1.0);
  return a + ab * t;
}

/// The point on [shape]'s outline closest to [p], or null if the shape has
/// no measurable outline.
Offset? closestPointOnShape(Offset p, CanvasShape shape) {
  final pts = measureOutline(shape);
  if (pts.length < 2) return null;
  var best = double.infinity;
  Offset? result;
  for (int i = 0; i < pts.length - 1; i++) {
    final c = _closestOnSegment(p, pts[i], pts[i + 1]);
    final d = (c - p).distance;
    if (d < best) {
      best = d;
      result = c;
    }
  }
  return result;
}
