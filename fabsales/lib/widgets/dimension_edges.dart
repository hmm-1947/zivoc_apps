import 'dart:math' as math;
import 'dart:ui';

import '../models/shape.dart';

/// A straight outline segment of a shape, in scene coordinates.
class DimEdge {
  final Offset a;
  final Offset b;
  const DimEdge(this.a, this.b);

  Offset get delta => b - a;
  double get length => delta.distance;
  Offset get midpoint => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

  /// Unit direction vector of the edge.
  Offset get unit {
    final l = length;
    return l < 1e-9 ? const Offset(1, 0) : delta / l;
  }
}

/// Straight outline edges of a shape. Curved shapes have none. A semicircle
/// contributes only its straight diameter.
List<DimEdge> dimensionEdges(CanvasShape shape) {
  final r = shape.rect;
  switch (shape.type) {
    case ShapeType.rectangle:
    case ShapeType.square:
    case ShapeType.door:
    case ShapeType.doorDouble:
    case ShapeType.window:
    case ShapeType.windowSliding:
    case ShapeType.text:
      return [
        DimEdge(r.topLeft, r.topRight),
        DimEdge(r.topRight, r.bottomRight),
        DimEdge(r.bottomRight, r.bottomLeft),
        DimEdge(r.bottomLeft, r.topLeft),
      ];

    case ShapeType.semiCircle:
      return [DimEdge(r.bottomLeft, r.bottomRight)];

    // A plain line is its own single straight edge.
    case ShapeType.line:
      return [DimEdge(shape.topLeft, shape.bottomRight)];

    case ShapeType.triangle:
      final top = Offset(r.center.dx, r.top);
      return [
        DimEdge(top, r.bottomRight),
        DimEdge(r.bottomRight, r.bottomLeft),
        DimEdge(r.bottomLeft, top),
      ];

    case ShapeType.rightTriangle:
      return [
        DimEdge(r.topLeft, r.bottomLeft),
        DimEdge(r.bottomLeft, r.bottomRight),
        DimEdge(r.bottomRight, r.topLeft),
      ];

    case ShapeType.diamond:
      final t = Offset(r.center.dx, r.top);
      final rt = Offset(r.right, r.center.dy);
      final b = Offset(r.center.dx, r.bottom);
      final l = Offset(r.left, r.center.dy);
      return [DimEdge(t, rt), DimEdge(rt, b), DimEdge(b, l), DimEdge(l, t)];

    case ShapeType.pentagon:
    case ShapeType.hexagon:
      final sides = shape.type == ShapeType.pentagon ? 5 : 6;
      final start = shape.type == ShapeType.pentagon ? -math.pi / 2 : 0.0;
      final pts = List.generate(sides, (i) {
        final ang = start + 2 * math.pi * i / sides;
        return Offset(
          r.center.dx + r.width / 2 * math.cos(ang),
          r.center.dy + r.height / 2 * math.sin(ang),
        );
      });
      return [
        for (var i = 0; i < pts.length; i++) DimEdge(pts[i], pts[(i + 1) % pts.length]),
      ];

    default:
      return const [];
  }
}

/// Distance from [p] to the segment of [e].
double distanceToEdge(Offset p, DimEdge e) {
  final ab = e.delta;
  final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lenSq < 1e-9) return (p - e.a).distance;
  var t = ((p - e.a).dx * ab.dx + (p - e.a).dy * ab.dy) / lenSq;
  t = t.clamp(0.0, 1.0);
  return (p - (e.a + ab * t)).distance;
}

/// Edge of [shape] closest to [p] within [tolerance], or null.
DimEdge? edgeNear(CanvasShape shape, Offset p, double tolerance) {
  DimEdge? best;
  var bestD = double.infinity;
  for (final e in dimensionEdges(shape)) {
    final d = distanceToEdge(p, e);
    if (d < bestD) {
      bestD = d;
      best = e;
    }
  }
  return bestD <= tolerance ? best : null;
}

/// Topmost edge of a polygon (smallest midpoint y), the default for a click
/// inside the shape.
DimEdge topmostEdge(CanvasShape shape) {
  final edges = dimensionEdges(shape);
  var best = edges.first;
  for (final e in edges.skip(1)) {
    if (e.midpoint.dy < best.midpoint.dy - 1e-6) best = e;
  }
  return best;
}

/// True if two edges are parallel within [toleranceDeg].
bool edgesParallel(DimEdge a, DimEdge b, {double toleranceDeg = 1.0}) {
  final cross = a.unit.dx * b.unit.dy - a.unit.dy * b.unit.dx;
  return cross.abs() <= math.sin(toleranceDeg * math.pi / 180);
}

/// Perpendicular distance between two parallel edges: from the midpoint of
/// [a] to the infinite line through [b].
double parallelGap(DimEdge a, DimEdge b) {
  final n = Offset(-b.unit.dy, b.unit.dx);
  final v = a.midpoint - b.a;
  return (v.dx * n.dx + v.dy * n.dy).abs();
}
