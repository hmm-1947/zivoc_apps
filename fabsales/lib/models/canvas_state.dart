import 'dart:math' as math;
import 'dart:ui';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'shape.dart';

enum ToolMode { select, pan, shape, line, curvedLine, text, dimension, angle, eraser }

/// Geometry of an angle marker between two rays leaving [vertex].
///
/// [dirA] and [dirB] are the unit-direction angles (radians) of the two
/// rays, each pointing away from the vertex. [outside] picks the reflex
/// wedge instead of the inside (smaller) one.
class AngleArc {
  final double startAngle;
  final double sweep;
  final double bisector;
  final double degrees;
  const AngleArc(this.startAngle, this.sweep, this.bisector, this.degrees);
}

/// Computes the inside (smaller) or outside (reflex) arc between two rays.
AngleArc angleArcFor(double dirA, double dirB, {bool outside = false}) {
  var sweep = dirB - dirA;
  while (sweep > math.pi) {
    sweep -= 2 * math.pi;
  }
  while (sweep < -math.pi) {
    sweep += 2 * math.pi;
  }
  // Inside angle sweeps the short way; outside sweeps the long way round.
  if (outside) {
    sweep = sweep > 0 ? sweep - 2 * math.pi : sweep + 2 * math.pi;
  }
  final start = dirA;
  final bisector = start + sweep / 2;
  return AngleArc(start, sweep, bisector, sweep.abs() * 180 / math.pi);
}

/// Unsigned angle in degrees (0..180) between the directions of two lines.
double angleBetweenDeg(CanvasShape a, CanvasShape b) {
  final da = a.bottomRight - a.topLeft;
  final db = b.bottomRight - b.topLeft;
  final ang = (da.direction - db.direction).abs() * 180 / math.pi;
  final folded = ang % 360;
  return folded > 180 ? 360 - folded : folded;
}

class CanvasState extends ChangeNotifier {
  final List<CanvasShape> _shapes = [];
  final List<List<CanvasShape>> _undoStack = [];
  final List<List<CanvasShape>> _redoStack = [];

  List<CanvasShape> get shapes => List.unmodifiable(_shapes);

  ToolMode toolMode = ToolMode.pan;
  ShapeType? activeShapeType;

  /// Primary selected shape (kept for backwards compatibility with single-select UI).
  String? selectedShapeId;

  /// Full multi-selection set. Always kept in sync with [selectedShapeId]:
  /// when exactly one shape is selected, [selectedShapeId] mirrors it.
  final Set<String> selectedShapeIds = {};

  ShapeStyle currentStyle = const ShapeStyle();

  final _uuid = const Uuid();

  List<CanvasShape> _snapshot() => _shapes.map((s) => s.clone()).toList();

  void _pushUndo() {
    _undoStack.add(_snapshot());
    if (_undoStack.length > 100) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void setTool(ToolMode mode, {ShapeType? shapeType}) {
    toolMode = mode;
    activeShapeType = shapeType;
    // Selection is preserved across tool switches (Canva-style): handles,
    // move, resize and rotate on the current selection work regardless of
    // which drawing tool is active, so switching tools shouldn't drop it.
    // The dimension and radius tools are the exception: picking either one
    // drops the current selection and selection stays disabled while
    // they're active, so clicks are never ambiguous between "select a
    // shape" and "place a measurement point".
    if (mode == ToolMode.dimension) {
      selectedShapeId = null;
      selectedShapeIds.clear();
    }
    notifyListeners();
  }

  static const String kTextTemplate = 'Double-tap to edit';

  /// Adds a linear dimension between [start] and [end]. The label is
  /// pre-filled with the measured length; the user can overwrite it. If
  /// [refShapeId] is given, the dimension moves along with that shape.
  CanvasShape addDimension(Offset start, Offset end, {double offset = 28, String? refShapeId}) {
    _pushUndo();
    final shape = CanvasShape(
      id: _uuid.v4(),
      type: ShapeType.dimension,
      topLeft: start,
      bottomRight: end,
      style: currentStyle,
      text: (end - start).distance.round().toString(),
      freePoints: [Offset(offset, 0)],
      refShapeId: refShapeId,
    );
    _shapes.add(shape);
    _selectSingle(shape.id);
    notifyListeners();
    return shape;
  }

  /// Adds an angle marker between two lines [lineA] and [lineB]. The arc is
  /// drawn at their intersection; the label defaults to the angle in degrees
  /// and can be overwritten by the user.
  CanvasShape addAngle(CanvasShape lineA, CanvasShape lineB, Offset vertex) {
    _pushUndo();
    final shape = CanvasShape(
      id: _uuid.v4(),
      type: ShapeType.angleDimension,
      topLeft: vertex,
      bottomRight: vertex,
      style: currentStyle,
      text: '${angleBetweenDeg(lineA, lineB).toStringAsFixed(1)}°',
      refShapeId: lineA.id,
      refShapeId2: lineB.id,
      angleOutside: false,
      angleRadius: 36,
    );
    _shapes.add(shape);
    _selectSingle(shape.id);
    notifyListeners();
    return shape;
  }

  /// Updates an angle marker's arc: its radius, and whether it shows the
  /// outside (reflex) angle. Label text is refreshed to the new angle unless
  /// the user has already typed a custom value.
  void setAngleArc(String id, {double? radius, bool? outside, required double degrees}) {
    final shape = _shapes.firstWhereOrNull((s) => s.id == id);
    if (shape == null || shape.type != ShapeType.angleDimension) return;
    final oldText = shape.text;
    if (radius != null) shape.angleRadius = radius;
    if (outside != null && outside != shape.angleOutside) {
      shape.angleOutside = outside;
      if (oldText == null || oldText == _autoAngleText(shape, !outside, degrees)) {
        shape.text = _autoAngleText(shape, outside, degrees);
      }
    }
    notifyListeners();
  }

  String _autoAngleText(CanvasShape shape, bool outside, double insideDeg) {
    final deg = outside ? 360 - insideDeg : insideDeg;
    return '${deg.toStringAsFixed(1)}°';
  }


  /// Ids of dimensions attached to any shape in [ids] that are not themselves
  /// in [ids]. These follow their shape when it moves.
  Set<String> attachedDimensionIds(Iterable<String> ids) {
    final set = ids.toSet();
    return {
      for (final s in _shapes)
        if ((s.type == ShapeType.dimension || s.type == ShapeType.radiusDimension) &&
            s.refShapeId != null &&
            set.contains(s.refShapeId) &&
            !set.contains(s.id))
          s.id,
    };
  }

  /// True if [circleId] already has a radius dimension on it. A circle may
  /// only ever be marked once.
  bool hasRadiusDimension(String circleId) =>
      _shapes.any((s) => s.type == ShapeType.radiusDimension && s.refShapeId == circleId);

  /// Adds a radius dimension for the circle/ellipse [circleId]: a CAD-style
  /// leader that touches the circumference nearest [towards] with an
  /// arrowhead, and runs outward (away from the centre) to a label point
  /// outside the circle. The centre and rim stay derived from the circle
  /// itself, never stored as free points, so later drags can't pull the
  /// rim end off the circle. Returns null (and does nothing) if [circleId]
  /// is already marked — a circle gets only one radius dimension.
  CanvasShape? addRadiusDimension(String circleId, Offset towards) {
    final circle = _shapes.firstWhereOrNull((s) => s.id == circleId);
    if (circle == null) return null;
    if (hasRadiusDimension(circleId)) return null;
    _pushUndo();
    final centre = circle.rect.center;
    final rx = circle.rect.width / 2;
    final ry = circle.rect.height / 2;
    var dir = towards - centre;
    if (dir.distance < 0.5) dir = const Offset(1, 0);
    final angle = math.atan2(dir.dy, dir.dx);
    final rim = Offset(centre.dx + rx * math.cos(angle), centre.dy + ry * math.sin(angle));
    const outerLen = 40.0;
    final unit = Offset(math.cos(angle), math.sin(angle));
    final outer = rim + unit * outerLen;
    final radius = (rx + ry) / 2;
    final shape = CanvasShape(
      id: _uuid.v4(),
      type: ShapeType.radiusDimension,
      topLeft: rim,
      bottomRight: outer,
      style: currentStyle,
      text: radius.round().toString(),
      freePoints: [const Offset(outerLen, 0)],
      refShapeId: circleId,
    );
    _shapes.add(shape);
    _selectSingle(shape.id);
    notifyListeners();
    return shape;
  }

  /// Places a text object centred on [at] with the template content.
  CanvasShape addText(Offset at) {
    _pushUndo();
    const w = 220.0, h = 48.0;
    final shape = CanvasShape(
      id: _uuid.v4(),
      type: ShapeType.text,
      topLeft: Offset(at.dx - w / 2, at.dy - h / 2),
      bottomRight: Offset(at.dx + w / 2, at.dy + h / 2),
      style: currentStyle,
      text: kTextTemplate,
    );
    _shapes.add(shape);
    _selectSingle(shape.id);
    notifyListeners();
    return shape;
  }

  /// Applies [change] to the style of every selected text object.
  void updateSelectedTextStyle(ShapeStyle Function(ShapeStyle) change) {
    _pushUndo();
    for (final s in _shapes) {
      if (selectedShapeIds.contains(s.id) && s.type == ShapeType.text) {
        s.style = change(s.style);
      }
    }
    currentStyle = change(currentStyle);
    notifyListeners();
  }

  void setText(String id, String text) {
    final s = _shapes.firstWhere((s) => s.id == id);
    s.text = text;
    notifyListeners();
  }

  void _selectSingle(String id) {
    selectedShapeIds
      ..clear()
      ..add(id);
    selectedShapeId = id;
  }

  CanvasShape addShape(ShapeType type, Offset topLeft, Offset bottomRight) {
    _pushUndo();
    final shape = CanvasShape(
      id: _uuid.v4(),
      type: type,
      topLeft: topLeft,
      bottomRight: bottomRight,
      style: currentStyle,
    );
    _shapes.add(shape);
    notifyListeners();
    return shape;
  }

  /// True bounding box of a point list (not just first/last point).
  static Rect _boundsOf(List<Offset> points) {
    var minX = points.first.dx, maxX = points.first.dx;
    var minY = points.first.dy, maxY = points.first.dy;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  CanvasShape addFreeform(ShapeType type, List<Offset> points) {
    _pushUndo();
    final bounds = _boundsOf(points);
    final shape = CanvasShape(
      id: _uuid.v4(),
      type: type,
      topLeft: bounds.topLeft,
      bottomRight: bounds.bottomRight,
      style: currentStyle,
      freePoints: points,
    );
    _shapes.add(shape);
    notifyListeners();
    return shape;
  }

  void updateShapeGeometry(String id, Offset topLeft, Offset bottomRight) {
    final shape = _shapes.firstWhere((s) => s.id == id);
    shape.topLeft = topLeft;
    shape.bottomRight = bottomRight;
    notifyListeners();
  }

  void moveShapeBy(String id, Offset delta) => moveShapesBy([id], delta);

  /// Moves every shape in [ids] by the same [delta] (used for multi-select drag).
  /// Dimensions attached to those shapes move with them.
  void moveShapesBy(Iterable<String> ids, Offset delta) {
    final list = ids.toList();
    for (final id in [...list, ...attachedDimensionIds(list)]) {
      final shape = _shapes.firstWhereOrNull((s) => s.id == id);
      if (shape == null) continue;
      shape.topLeft += delta;
      shape.bottomRight += delta;
      // A dimension's freePoints holds its fixed offset from the measured
      // line, not a spatial point, so it must not be shifted.
      if (shape.freePoints.isNotEmpty && shape.type != ShapeType.dimension) {
        shape.freePoints = shape.freePoints.map((p) => p + delta).toList();
      }
    }
    notifyListeners();
  }

  /// Moves shapes to an absolute position derived from their geometry at the
  /// start of the drag (in [originalTopLeft]/[originalBottomRight]/
  /// [originalFreePoints], all keyed by shape id) shifted by [delta]. Using
  /// the drag-start snapshot plus the *total* delta (rather than repeatedly
  /// applying incremental per-frame deltas) lets the caller snap the result
  /// each frame without accumulating drift.
  void moveShapesToDelta(
    Iterable<String> ids,
    Offset delta,
    Map<String, Offset> originalTopLeft,
    Map<String, Offset> originalBottomRight,
    Map<String, List<Offset>> originalFreePoints,
  ) {
    final idSet = ids.toSet();
    for (final id in idSet) {
      final shape = _shapes.firstWhereOrNull((s) => s.id == id);
      final ot = originalTopLeft[id];
      final ob = originalBottomRight[id];
      if (shape == null || ot == null || ob == null) continue;

      // A linear dimension dragged on its own keeps its measured points
      // (topLeft/bottomRight) exactly where they are; only its offset from
      // them changes, so the dimension line slides along the normal and the
      // extension lines grow/shrink. When the dimension travels along with
      // the shape it measures (or as part of a group move), it moves as a
      // whole instead.
      if (shape.type == ShapeType.dimension) {
        final travelsWithShape = (shape.refShapeId != null && idSet.contains(shape.refShapeId)) ||
            idSet.any((i) => _shapes.firstWhereOrNull((s) => s.id == i)?.type != ShapeType.dimension);
        if (travelsWithShape) {
          shape.topLeft = ot + delta;
          shape.bottomRight = ob + delta;
          continue;
        }
        final v = ob - ot;
        final len = v.distance;
        final ofp = originalFreePoints[id];
        final origOffset = (ofp != null && ofp.isNotEmpty) ? ofp.first.dx : 28.0;
        shape.topLeft = ot;
        shape.bottomRight = ob;
        if (len < 0.5) continue;
        final normal = Offset(-v.dy / len, v.dx / len);
        final newOffset = origOffset + (delta.dx * normal.dx + delta.dy * normal.dy);
        shape.freePoints = [Offset(newOffset, 0)];
        continue;
      }

      // A radius dimension's rim end is never a free point: it is always
      // the point on the circle's own circumference nearest the dragged
      // label, so it can't be pulled off the circle. Dragging swings the
      // whole leader (rim + outer label point) around the centre, keeping
      // the outer point's original distance from the rim.
      final ref = shape.type == ShapeType.radiusDimension && shape.refShapeId != null
          ? _shapes.firstWhereOrNull((s) => s.id == shape.refShapeId)
          : null;
      if (ref != null) {
        final centre = ref.rect.center;
        final rx = ref.rect.width / 2;
        final ry = ref.rect.height / 2;
        final outerLen = (originalFreePoints[id]?.isNotEmpty ?? false)
            ? originalFreePoints[id]!.first.dx
            : (ob - ot).distance;
        var dir = (ob + delta) - centre;
        if (dir.distance < 0.5) dir = ob - ot;
        final angle = math.atan2(dir.dy, dir.dx);
        final rim = Offset(centre.dx + rx * math.cos(angle), centre.dy + ry * math.sin(angle));
        final unit = Offset(math.cos(angle), math.sin(angle));
        shape.topLeft = rim;
        shape.bottomRight = rim + unit * outerLen;
      } else {
        shape.topLeft = ot + delta;
        shape.bottomRight = ob + delta;
      }

      // freePoints on a radiusDimension or linear dimension stores a fixed
      // length/offset, not a spatial point, so it must never be shifted by delta.
      if (ref == null && shape.type != ShapeType.dimension) {
        final ofp = originalFreePoints[id];
        if (ofp != null && ofp.isNotEmpty) {
          shape.freePoints = ofp.map((p) => p + delta).toList();
        }
      }
    }
    notifyListeners();
  }

  /// Resizes a shape by directly setting new corner points (used when dragging a handle).
  void resizeShape(String id, Offset topLeft, Offset bottomRight) {
    final shape = _shapes.firstWhereOrNull((s) => s.id == id);
    if (shape == null) return;
    shape.topLeft = topLeft;
    shape.bottomRight = bottomRight;
    notifyListeners();
  }

  /// Sets a shape's rotation (radians) directly, used while dragging the rotate handle.
  void rotateShapeTo(String id, double rotation) {
    final shape = _shapes.firstWhereOrNull((s) => s.id == id);
    if (shape == null) return;
    shape.rotation = rotation;
    notifyListeners();
  }

  /// Uniformly scales a shape's rect from [origin] (the opposite/anchor corner) by [scale].
  void scaleShapeFrom(String id, Offset origin, double scaleX, double scaleY) {
    final shape = _shapes.firstWhereOrNull((s) => s.id == id);
    if (shape == null) return;
    Offset scalePoint(Offset p) => Offset(
          origin.dx + (p.dx - origin.dx) * scaleX,
          origin.dy + (p.dy - origin.dy) * scaleY,
        );
    shape.topLeft = scalePoint(shape.topLeft);
    shape.bottomRight = scalePoint(shape.bottomRight);
    if (shape.freePoints.isNotEmpty) {
      shape.freePoints = shape.freePoints.map(scalePoint).toList();
    }
    notifyListeners();
  }

  void commitMove() {
    // called on drag end to register undo point retroactively
  }

  void beginInteractiveChange() => _pushUndo();

  /// Selects a single shape (or clears selection if [id] is null). Replaces any
  /// existing multi-selection.
  void selectShape(String? id) {
    selectedShapeId = id;
    selectedShapeIds
      ..clear()
      ..addAll(id == null ? const <String>[] : [id]);
    notifyListeners();
  }

  /// Replaces the current selection with [ids] (used for rubber-band / shift-click select).
  void selectShapes(Iterable<String> ids) {
    selectedShapeIds
      ..clear()
      ..addAll(ids);
    selectedShapeId = selectedShapeIds.length == 1 ? selectedShapeIds.first : null;
    notifyListeners();
  }

  /// Toggles [id] in the current multi-selection (shift/ctrl-click behavior).
  void toggleSelection(String id) {
    if (selectedShapeIds.contains(id)) {
      selectedShapeIds.remove(id);
    } else {
      selectedShapeIds.add(id);
    }
    selectedShapeId = selectedShapeIds.length == 1 ? selectedShapeIds.first : null;
    notifyListeners();
  }

  /// Selects every object on the canvas.
  void selectAll() {
    selectShapes(_shapes.map((s) => s.id).toList());
  }


  void clearSelection() {
    selectedShapeId = null;
    selectedShapeIds.clear();
    notifyListeners();
  }

  void deleteSelected() {
    if (selectedShapeIds.isEmpty) return;
    _pushUndo();
    _shapes.removeWhere((s) => selectedShapeIds.contains(s.id));
    selectedShapeId = null;
    selectedShapeIds.clear();
    notifyListeners();
  }

  void deleteShape(String id) {
    _pushUndo();
    _shapes.removeWhere((s) => s.id == id);
    if (selectedShapeId == id) selectedShapeId = null;
    selectedShapeIds.remove(id);
    notifyListeners();
  }

  /// Duplicates the shape with [id], exactly preserving its size, style,
  /// rotation and all other properties, offset slightly so the copy is
  /// visible on top of the original, and selects the new copy.
  void duplicateShape(String id) {
    final shape = _shapes.firstWhereOrNull((s) => s.id == id);
    if (shape == null) return;
    _pushUndo();
    const offset = Offset(24, 24);
    final copy = CanvasShape(
      id: _uuid.v4(),
      type: shape.type,
      topLeft: shape.topLeft + offset,
      bottomRight: shape.bottomRight + offset,
      rotation: shape.rotation,
      style: shape.style,
      freePoints: shape.freePoints.map((p) => p + offset).toList(),
      text: shape.text,
    );
    _shapes.add(copy);
    selectShape(copy.id);
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_snapshot());
    final prev = _undoStack.removeLast();
    _shapes
      ..clear()
      ..addAll(prev);
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_snapshot());
    final next = _redoStack.removeLast();
    _shapes
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void clear() {
    _pushUndo();
    _shapes.clear();
    selectedShapeId = null;
    notifyListeners();
  }
}
