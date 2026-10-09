import 'dart:math' as math;
import 'dart:ui';
import '../models/shape.dart';

/// Angles (in degrees, standard math convention where 0 = pointing right,
/// 90 = down on screen since Y grows downward) that a line should snap to
/// when its current angle is within [kAngleSnapToleranceDeg] of one of them.
const List<double> kSnapAngles = [
  0, 15, 30, 45, 60, 75, 90, 105, 120, 135, 150, 165, 180,
  -15, -30, -45, -60, -75, -90, -105, -120, -135, -150, -165,
  -45, -90, -135,
];

const double kAngleSnapToleranceDeg = 6.0;

/// Pixel distance (in scene units) within which a point/edge snaps to
/// another shape's edge/center for alignment guides.
const double kAlignSnapTolerancePx = 8.0;

double _normalizeDeg(double deg) {
  var d = deg % 360;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d;
}

/// Snaps [raw] angle (degrees) to the nearest value in [kSnapAngles] if within
/// tolerance, otherwise returns [raw] unchanged.
double? snapAngleDeg(double raw) {
  final normalized = _normalizeDeg(raw);
  double? best;
  double bestDiff = double.infinity;
  for (final candidate in kSnapAngles) {
    final diff = (_normalizeDeg(normalized - candidate)).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = candidate;
    }
  }
  if (best != null && bestDiff <= kAngleSnapToleranceDeg) {
    return best;
  }
  return null;
}

/// Pixel distance (in scene units) within which a line endpoint snaps
/// directly onto a shape's corner, edge-midpoint, or center point.
const double kPointSnapTolerancePx = 14.0;

/// Given a fixed [start] point and a free-moving [end] point, returns a new
/// end point snapped to the nearest "nice" angle (0/45/90/...) if close
/// enough, else the original [end]. Also considers the orientation of
/// [nearbyShapes] (their edge directions) as additional candidate angles.
class LineSnapResult {
  final Offset end;
  final double angleDeg;
  final bool snapped;
  final CanvasShape? snappedToShape;
  /// Optional extra guide line to draw (e.g. from a shape's edge/center to
  /// the snapped point) in addition to the standard orientation guide.
  final AlignmentGuide? extraGuide;
  const LineSnapResult(this.end, this.angleDeg, this.snapped, this.snappedToShape, [this.extraGuide]);
}

/// Candidate anchor points on a shape that a line endpoint can snap onto:
/// the 4 corners, the 4 edge midpoints, and the center.
List<Offset> _shapeAnchorPoints(Rect r) => [
      r.topLeft,
      r.topRight,
      r.bottomLeft,
      r.bottomRight,
      Offset(r.center.dx, r.top),
      Offset(r.center.dx, r.bottom),
      Offset(r.left, r.center.dy),
      Offset(r.right, r.center.dy),
      r.center,
    ];

/// Tries to snap [end] directly onto a nearby shape's corner, edge-midpoint,
/// or center. Returns null if nothing is close enough.
_PointSnap? _snapToShapePoint(Offset end, List<CanvasShape> nearbyShapes) {
  Offset? best;
  CanvasShape? bestShape;
  double bestDist = kPointSnapTolerancePx;
  for (final shape in nearbyShapes) {
    for (final anchor in _shapeAnchorPoints(shape.rect)) {
      final d = (anchor - end).distance;
      if (d < bestDist) {
        bestDist = d;
        best = anchor;
        bestShape = shape;
      }
    }
  }
  if (best == null || bestShape == null) return null;
  return _PointSnap(best, bestShape);
}

class _PointSnap {
  final Offset point;
  final CanvasShape shape;
  const _PointSnap(this.point, this.shape);
}

class _EdgeAlign {
  final Offset point;
  final CanvasShape shape;
  final AlignmentGuide guide;
  const _EdgeAlign(this.point, this.shape, this.guide);
}

/// Tries to align [end]'s X coordinate with a shape's left/center/right edge,
/// or its Y coordinate with a shape's top/center/bottom edge (independently),
/// snapping just that one axis so the endpoint lines up straight with the
/// shape even when it isn't near one of the shape's exact anchor points.
_EdgeAlign? _snapToShapeEdgeLine(Offset end, List<CanvasShape> nearbyShapes) {
  const reach = 220.0; // how far from the shape this alignment still applies
  double bestXDist = kAlignSnapTolerancePx;
  double bestYDist = kAlignSnapTolerancePx;
  double? snappedX;
  double? snappedY;
  CanvasShape? xShape;
  CanvasShape? yShape;

  for (final shape in nearbyShapes) {
    final r = shape.rect;
    if ((r.center - end).distance > reach + math.max(r.width, r.height)) continue;

    for (final x in [r.left, r.center.dx, r.right]) {
      final d = (x - end.dx).abs();
      if (d < bestXDist) {
        bestXDist = d;
        snappedX = x;
        xShape = shape;
      }
    }
    for (final y in [r.top, r.center.dy, r.bottom]) {
      final d = (y - end.dy).abs();
      if (d < bestYDist) {
        bestYDist = d;
        snappedY = y;
        yShape = shape;
      }
    }
  }

  if (snappedX == null && snappedY == null) return null;

  // Prefer whichever axis is the closer/stronger match if both triggered.
  if (snappedX != null && (snappedY == null || bestXDist <= bestYDist)) {
    final point = Offset(snappedX, end.dy);
    final r = xShape!.rect;
    final top = math.min(r.top, point.dy) - 30;
    final bottom = math.max(r.bottom, point.dy) + 30;
    return _EdgeAlign(point, xShape, AlignmentGuide(Offset(snappedX, top), Offset(snappedX, bottom)));
  } else {
    final point = Offset(end.dx, snappedY!);
    final r = yShape!.rect;
    final left = math.min(r.left, point.dx) - 30;
    final right = math.max(r.right, point.dx) + 30;
    return _EdgeAlign(point, yShape, AlignmentGuide(Offset(left, snappedY), Offset(right, snappedY)));
  }
}

class PointSnapResult {
  final Offset point;
  final bool snapped;
  final CanvasShape? shape;
  const PointSnapResult(this.point, this.snapped, this.shape);
}

PointSnapResult snapPoint(Offset point, List<CanvasShape> nearbyShapes) {
  final pointSnap = _snapToShapePoint(point, nearbyShapes);
  if (pointSnap != null) {
    return PointSnapResult(pointSnap.point, true, pointSnap.shape);
  }
  final edgeAlign = _snapToShapeEdgeLine(point, nearbyShapes);
  if (edgeAlign != null) {
    return PointSnapResult(edgeAlign.point, true, edgeAlign.shape);
  }
  return PointSnapResult(point, false, null);
}

LineSnapResult snapLineEnd(Offset start, Offset end, List<CanvasShape> nearbyShapes) {
  final vector = end - start;
  if (vector.distance < 0.5) {
    return LineSnapResult(end, 0, false, null);
  }

  // 1) Highest priority: snap directly onto a shape's corner, edge-midpoint
  // or center if the cursor is close enough to one.
  final pointSnap = _snapToShapePoint(end, nearbyShapes);
  if (pointSnap != null) {
    final snappedVector = pointSnap.point - start;
    final snappedAngle = snappedVector.direction * 180 / math.pi;
    return LineSnapResult(
      pointSnap.point,
      snappedAngle,
      true,
      pointSnap.shape,
      AlignmentGuide(pointSnap.shape.rect.center, pointSnap.point),
    );
  }

  // 2) Next, try aligning the endpoint's X or Y coordinate with a nearby
  // shape's left/center/right edge or top/center/bottom edge (without
  // requiring the full point to coincide), producing a straight horizontal
  // or vertical alignment guide.
  final edgeAlign = _snapToShapeEdgeLine(end, nearbyShapes);
  if (edgeAlign != null) {
    final snappedVector = edgeAlign.point - start;
    final snappedAngle = snappedVector.direction * 180 / math.pi;
    return LineSnapResult(
      edgeAlign.point,
      snappedAngle,
      true,
      edgeAlign.shape,
      edgeAlign.guide,
    );
  }

  final rawAngle = vector.direction * 180 / math.pi;

  // 3) Otherwise fall back to angle snapping: standard snap angles + the
  // orientation of whichever nearby shape is closest to the cursor.
  final candidates = <double>[...kSnapAngles];
  // Map each candidate angle to the shape it came from (null for grid angles).
  final candidateShape = <double, CanvasShape>{};

  for (final shape in nearbyShapes) {
    final dist = (shape.rect.center - end).distance;
    if (dist >= 320) continue;
    final shapeAngle = shape.rect.width >= shape.rect.height ? 0.0 : 90.0;
    final baseAngle = _normalizeDeg(shapeAngle + shape.rotation * 180 / math.pi);
    for (final a in [baseAngle, _normalizeDeg(baseAngle + 90)]) {
      candidates.add(a);
      candidateShape.putIfAbsent(a, () => shape);
    }
  }

  double? bestAngle;
  double bestDiff = double.infinity;
  CanvasShape? snappedShape;
  for (final candidate in candidates) {
    final diff = (_normalizeDeg(rawAngle - candidate)).abs();
    final isShapeAngle = candidateShape.containsKey(candidate);
    final tolerance = isShapeAngle ? kAngleSnapToleranceDeg + 2 : kAngleSnapToleranceDeg;
    if (diff < bestDiff && diff <= tolerance) {
      bestDiff = diff;
      bestAngle = candidate;
      snappedShape = candidateShape[candidate];
    }
  }

  if (bestAngle == null) {
    return LineSnapResult(end, rawAngle, false, null);
  }

  final rad = bestAngle * math.pi / 180;
  final length = vector.distance;
  final snappedEnd = start + Offset(math.cos(rad), math.sin(rad)) * length;
  return LineSnapResult(
    snappedEnd,
    bestAngle,
    true,
    snappedShape,
  );
}

/// An alignment guide line to render while dragging/resizing a shape.
class AlignmentGuide {
  final Offset a;
  final Offset b;
  const AlignmentGuide(this.a, this.b);
}

class ShapeSnapResult {
  final Rect rect;
  final List<AlignmentGuide> guides;
  const ShapeSnapResult(this.rect, this.guides);
}

/// Snaps a shape's [rect] (while being drawn or moved) to nearby shapes'
/// edges/centers, returning the adjusted rect plus alignment guide lines to draw.
ShapeSnapResult snapRectToShapes(Rect rect, List<CanvasShape> others, {String? excludeId}) {
  double dx = 0;
  double dy = 0;
  AlignmentGuide? guideX;
  AlignmentGuide? guideY;
  double bestXDist = kAlignSnapTolerancePx;
  double bestYDist = kAlignSnapTolerancePx;

  final xTargets = [rect.left, rect.center.dx, rect.right];
  final yTargets = [rect.top, rect.center.dy, rect.bottom];

  for (final other in others) {
    if (excludeId != null && other.id == excludeId) continue;
    final oRect = other.rect;
    final otherX = [oRect.left, oRect.center.dx, oRect.right];
    final otherY = [oRect.top, oRect.center.dy, oRect.bottom];

    for (final mine in xTargets) {
      for (final theirs in otherX) {
        final d = (mine - theirs).abs();
        if (d < bestXDist) {
          bestXDist = d;
          dx = theirs - mine;
          final top = math.min(rect.top, oRect.top) - 40;
          final bottom = math.max(rect.bottom, oRect.bottom) + 40;
          guideX = AlignmentGuide(Offset(theirs, top), Offset(theirs, bottom));
        }
      }
    }
    for (final mine in yTargets) {
      for (final theirs in otherY) {
        final d = (mine - theirs).abs();
        if (d < bestYDist) {
          bestYDist = d;
          dy = theirs - mine;
          final left = math.min(rect.left, oRect.left) - 40;
          final right = math.max(rect.right, oRect.right) + 40;
          guideY = AlignmentGuide(Offset(left, theirs), Offset(right, theirs));
        }
      }
    }
  }

  final snapped = rect.shift(Offset(dx, dy));
  final guides = <AlignmentGuide>[
    ?guideX,
    ?guideY,
  ];
  return ShapeSnapResult(guides.isEmpty ? rect : snapped, guides);
}

String formatLength(double px) => px.round().toString();

String formatAngle(double deg) => '${deg.round()}°';

/// Pixel tolerance for a resize snapping to the shape's own symmetry
/// (equal width/height — i.e. becoming a square) around a corner drag.
const double kSelfSymmetrySnapTolerancePx = 10.0;

/// During a corner resize, snaps [rect] toward its own symmetry: when the
/// width and height are already close to equal, snaps the free corner so
/// they become exactly equal (a square), keeping [anchor] fixed. Returns
/// the adjusted rect plus a guide line along the square's diagonal when a
/// snap occurred, or the rect unchanged otherwise.
ShapeSnapResult snapRectToOwnSymmetry(Rect rect, Offset anchor) {
  final w = rect.width.abs();
  final h = rect.height.abs();
  if ((w - h).abs() >= kSelfSymmetrySnapTolerancePx) {
    return ShapeSnapResult(rect, const []);
  }

  final side = (w + h) / 2;
  final signX = rect.right >= rect.left ? 1.0 : -1.0;
  final signY = rect.bottom >= rect.top ? 1.0 : -1.0;
  // Keep the anchor corner fixed; the free corner moves to make it square.
  final freeCorner = Offset(anchor.dx + side * signX, anchor.dy + side * signY);
  final squared = Rect.fromPoints(anchor, freeCorner);

  final guide = AlignmentGuide(anchor, freeCorner);
  return ShapeSnapResult(squared, [guide]);
}
