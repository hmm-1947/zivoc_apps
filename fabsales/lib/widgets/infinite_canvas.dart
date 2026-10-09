import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/canvas_state.dart';
import '../models/shape.dart';
import 'dimension_edges.dart';
import 'grid_painter.dart';
import 'shape_hit_test.dart';
import 'shape_painter.dart';
import 'snap_utils.dart';

/// Which part of a shape's bounding box a handle controls.
enum HandleKind { topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right, rotate }

class InfiniteCanvas extends StatefulWidget {
  /// Called once the underlying transform controller exists (synchronously
  /// during this widget's initState, before the first frame), so callers
  /// can listen for pan/zoom changes without polling for currentState.
  final ValueChanged<Listenable>? onControllerReady;

  const InfiniteCanvas({super.key, this.onControllerReady});

  @override
  State<InfiniteCanvas> createState() => InfiniteCanvasState();
}

class InfiniteCanvasState extends State<InfiniteCanvas> {
  Matrix4 _transform = Matrix4.identity();
  final TransformationController _controller = TransformationController();

  /// Current scene<->screen transform, so overlay widgets (like the
  /// floating selection action bar) can track the canvas as it pans/zooms.
  Matrix4 get transform => _transform;

  /// Exposes the controller so overlay widgets can rebuild themselves
  /// whenever the canvas pans/zooms (this state's own pan/zoom changes
  /// are internal setState calls that don't otherwise notify anyone).
  Listenable get transformListenable => _controller;

  /// Public wrapper so overlay widgets can compute where to anchor
  /// themselves relative to the current selection's scene-space bounds.
  Rect? selectionBoundsFor(CanvasState state) => _currentSelectionBounds(state);

  /// Scene point for the action pill of a single selected angle marker: a
  /// spot beyond the outer edge of its arc, along the bisector, so the pill
  /// never covers the arc. Null when no angle marker is selected alone.
  Offset? angleActionAnchor(CanvasState state) {
    if (state.selectedShapeIds.length != 1) return null;
    final s = state.shapes.firstWhereOrNull((x) => x.id == state.selectedShapeIds.first);
    if (s == null || s.type != ShapeType.angleDimension) return null;
    final a = state.shapes.firstWhereOrNull((x) => x.id == s.refShapeId);
    final b = state.shapes.firstWhereOrNull((x) => x.id == s.refShapeId2);
    if (a == null || b == null) return null;
    final vertex = s.topLeft;
    final arc = angleArcFor(
      _rayAngleTo(a, vertex),
      _rayAngleTo(b, vertex),
      outside: s.angleOutside,
    );
    final unit = Offset(math.cos(arc.bisector), math.sin(arc.bisector));
    return vertex + unit * (s.angleRadius + 70);
  }

  List<AlignmentGuide> _activeGuides = [];

  /// Live preview of the line/curve currently being dragged out, rendered
  /// by ShapePainter while the gesture is in progress; null otherwise.
  CanvasShape? get _previewShape {
    if (_lineStartScene != null && _lineEndScene != null) {
      return CanvasShape(
        id: '__preview__',
        type: ShapeType.line,
        topLeft: _lineStartScene!,
        bottomRight: _lineEndScene!,
      );
    }
    if (_curvePoints != null && _curvePoints!.length > 1) {
      return CanvasShape(
        id: '__preview__',
        type: ShapeType.curvedLine,
        topLeft: _curvePoints!.first,
        bottomRight: _curvePoints!.last,
        freePoints: _curvePoints!,
      );
    }
    return null;
  }

  // --- Selection / move / resize / scale state ---
  Set<String>? _draggingShapeIds; // multi-shape move
  Offset? _moveStartScene; // pointer position when the move drag began (fixed)
  String? _movePrimaryId; // the shape whose rect snapping is computed against
  final Map<String, Offset> _moveOriginalTopLeft = {};
  final Map<String, Offset> _moveOriginalBottomRight = {};
  final Map<String, List<Offset>> _moveOriginalFreePoints = {};
  HandleKind? _activeHandle;
  String? _resizingShapeId;
  Rect? _resizeStartRect;
  Offset? _resizeAnchor; // the fixed opposite corner/edge while resizing

  // --- Rotation ---
  String? _rotatingShapeId;
  double _rotateStartShapeRotation = 0;
  double _rotateStartPointerAngle = 0;
  Offset _rotateCenter = Offset.zero;
  /// Current rotation angle in degrees, shown near the W/H label while
  /// actively dragging the rotate handle; null the rest of the time.
  double? _liveRotationDeg;

  // --- Rubber-band multi-select ---
  Offset? _selectionBoxStartScene;
  Offset? _selectionBoxEndScene;

  // --- Panning (drag on empty space, any tool) ---
  bool _isPanning = false;
  Offset _panTotalDelta = Offset.zero;
  // True when the current pan gesture started by clicking an unselected
  // shape (which selects it but doesn't move it); prevents _onPanEnd's
  // tap-on-empty-space deselect logic from immediately undoing that select.
  bool _panStartedOnShape = false;

  // --- Drawing a straight line or freehand curve (line/curvedLine tools) ---
  Offset? _lineStartScene;
  Offset? _lineEndScene;
  List<Offset>? _curvePoints;

  // --- Tap-vs-drag disambiguation ---
  // When a gesture starts on an existing shape, we arm a potential move
  // immediately (so dragging feels instant) but defer the actual
  // selection-state change until _onPanEnd, once we know whether the
  // pointer actually moved (a drag) or stayed put (a tap/click).
  String? _pendingTapHitId;

  // Double-tap tracking for opening the text editor.
  String? _lastTapId;
  DateTime? _lastTapTime;

  // Inline text editing: the shape being edited, and its controller.
  String? _editingTextId;
  TextEditingController? _textController;
  FocusNode? _textFocus;

  /// Ctrl/Cmd+A selects every object; Delete/Backspace deletes the current
  /// selection. Ignored while a text field (inline editor or toolbar input)
  /// has focus, so typing is never mistaken for a canvas shortcut.
  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted || _editingTextId != null) return false;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && focused.findAncestorStateOfType<EditableTextState>() != null) {
      return false;
    }
    final state = context.read<CanvasState>();
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (ctrl && key == LogicalKeyboardKey.keyA) {
      state.selectAll();
      return true;
    }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      if (state.selectedShapeIds.isEmpty) return false;
      state.deleteSelected();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    _textController?.dispose();
    _textFocus?.dispose();
    super.dispose();
  }



  /// True when the pointer barely moved, i.e. the gesture was a tap.
  bool _wasTapNotDrag() => _panTotalDelta.distance < 6;

  void _beginTextEdit(String id, CanvasState state) {
    final shape = state.shapes.firstWhereOrNull((s) => s.id == id);
    if (shape == null) return;
    _textController?.dispose();
    _textFocus?.dispose();
    _textController = TextEditingController(
      text: shape.type == ShapeType.text && shape.text == CanvasState.kTextTemplate
          ? ''
          : (shape.text ?? ''),
    );
    _textFocus = FocusNode();
    setState(() => _editingTextId = id);
    WidgetsBinding.instance.addPostFrameCallback((_) => _textFocus?.requestFocus());
  }

  void _commitTextEdit(CanvasState state) {
    final id = _editingTextId;
    final controller = _textController;
    if (id != null && controller != null) {
      final value = controller.text.trim();
      final shape = state.shapes.firstWhereOrNull((s) => s.id == id);
      final isDimension = shape != null && shape.type != ShapeType.text;
      // An empty dimension label falls back to its measured value; an empty
      // text object falls back to the template.
      final fallback = isDimension ? (shape.text ?? '') : CanvasState.kTextTemplate;
      state.setText(id, value.isEmpty ? fallback : value);
    }
    _endTextEdit();
  }

  void _endTextEdit() {
    _textController?.dispose();
    _textFocus?.dispose();
    _textController = null;
    _textFocus = null;
    if (mounted) setState(() => _editingTextId = null);
  }
  bool _pendingTapAdditive = false;
  static const double _tapMoveThreshold = 6.0; // scene-space px

  /// Cancels any in-progress single-finger gesture (move, resize, rotate,
  /// rubber-band select, or pan) without committing a selection change.
  /// Called when a second finger joins mid-gesture, so a pinch always wins
  /// and never leaves stale drag state behind.
  void _abortSingleFingerGesture() {
    _activeHandle = null;
    _resizingShapeId = null;
    _resizeStartRect = null;
    _resizeAnchor = null;
    _rotatingShapeId = null;
    _draggingShapeIds = null;
    _moveStartScene = null;
    _movePrimaryId = null;
    _moveOriginalTopLeft.clear();
    _moveOriginalBottomRight.clear();
    _moveOriginalFreePoints.clear();
    _pendingTapHitId = null;
    _isPanning = false;
    _panStartedOnShape = false;
    _panTotalDelta = Offset.zero;
    setState(() {
      _selectionBoxStartScene = null;
      _selectionBoxEndScene = null;
      _activeGuides = [];
      _lineStartScene = null;
      _lineEndScene = null;
      _curvePoints = null;
      _liveRotationDeg = null;
    });
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
    _controller.value = _transform;
    _controller.addListener(() {
      setState(() => _transform = _controller.value);
    });
    widget.onControllerReady?.call(_controller);
  }

  Offset _toScene(Offset local) {
    final inverse = Matrix4.inverted(_controller.value);
    return MatrixUtils.transformPoint(inverse, local);
  }

  static const double _minScale = 0.05;
  static const double _maxScale = 8.0;

  void zoomBy(double factor, {Offset? focal}) {
    if (!factor.isFinite || factor <= 0) return;
    final currentScale = _controller.value.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(_minScale, _maxScale);
    // Re-derive the factor from the clamped target scale so we never let
    // scale collapse to 0 or explode. An unclamped zero/huge scale here
    // permanently freezes DotGridPainter (its loop spins until
    // spacing*scale clears a threshold), which looks like a white-screen
    // hang with no crash and no error log.
    if (currentScale <= 0) return;
    final safeFactor = targetScale / currentScale;
    final center = focal ?? (context.size != null ? Offset(context.size!.width / 2, context.size!.height / 2) : Offset.zero);
    final scenePoint = _toScene(center);
    final newMatrix = _controller.value.clone()
      ..translateByDouble(scenePoint.dx, scenePoint.dy, 0, 1)
      ..scaleByDouble(safeFactor, safeFactor, safeFactor, 1)
      ..translateByDouble(-scenePoint.dx, -scenePoint.dy, 0, 1);
    _controller.value = newMatrix;
  }

  void resetView() {
    _controller.value = Matrix4.identity();
  }

  /// Places a default-sized shape of [type] centered on the current
  /// viewport and selects it, so picking a shape from the tray draws it
  /// immediately instead of waiting for a drag gesture.
  void placeShapeAtViewportCenter(CanvasState state, ShapeType type) {
    final size = context.size ?? const Size(800, 600);
    final center = _toScene(Offset(size.width / 2, size.height / 2));
    const halfW = 60.0, halfH = 60.0;
    final shape = state.addShape(
      type,
      center - const Offset(halfW, halfH),
      center + const Offset(halfW, halfH),
    );
    state.selectShape(shape.id);
  }

  CanvasShape? _hitTest(CanvasState state, Offset scenePoint) {
    for (final shape in state.shapes.reversed) {
      if (hitTestShape(shape, scenePoint)) {
        return shape;
      }
    }
    return null;
  }

  double _handleHitRadius(double scale) => 10 / scale;

  /// Returns the handle (if any) under [scenePoint] for the given selection
  /// bounding box, accounting for current zoom so the hit target stays a
  /// constant screen size.
  HandleKind? _hitTestHandle(Rect bounds, Offset scenePoint, double scale) {
    final r = _handleHitRadius(scale);
    final rotateHandlePos = _rotateHandlePosition(bounds, scale);
    if ((rotateHandlePos - scenePoint).distance <= r) return HandleKind.rotate;
    final corners = <HandleKind, Offset>{
      HandleKind.topLeft: bounds.topLeft,
      HandleKind.topRight: bounds.topRight,
      HandleKind.bottomLeft: bounds.bottomLeft,
      HandleKind.bottomRight: bounds.bottomRight,
    };
    for (final entry in corners.entries) {
      if ((entry.value - scenePoint).distance <= r) return entry.key;
    }
    final edges = <HandleKind, Offset>{
      HandleKind.top: Offset(bounds.center.dx, bounds.top),
      HandleKind.bottom: Offset(bounds.center.dx, bounds.bottom),
      HandleKind.left: Offset(bounds.left, bounds.center.dy),
      HandleKind.right: Offset(bounds.right, bounds.center.dy),
    };
    for (final entry in edges.entries) {
      if ((entry.value - scenePoint).distance <= r) return entry.key;
    }
    return null;
  }

  /// Scene-space position of the rotate handle: a fixed screen distance
  /// above the top-center of the bounds, so it stays a constant screen
  /// offset regardless of zoom.
  Offset _rotateHandlePosition(Rect bounds, double scale) {
    const screenOffset = 26.0;
    return Offset(bounds.center.dx, bounds.bottom + screenOffset / scale);
  }

  Rect? _currentSelectionBounds(CanvasState state) {
    if (state.selectedShapeIds.isEmpty) return null;
    Rect? bounds;
    for (final shape in state.shapes) {
      if (!state.selectedShapeIds.contains(shape.id)) continue;
      bounds = bounds == null ? shape.rect : bounds.expandToInclude(shape.rect);
    }
    return bounds;
  }

  /// Tries to begin a select/handle/move interaction at [scene]. Returns
  /// true if the gesture was claimed (so the caller should not also start a
  /// drawing gesture). This runs for every tool, not just ToolMode.select,
  /// so that clicking/dragging an existing shape always selects or moves it
  /// regardless of which drawing tool is currently active; only a gesture
  /// that starts on empty canvas falls through to drawing.
  /// Tries to begin a resize/rotate-handle interaction at [scene] against the
  /// current selection. Returns true if claimed.
  bool _tryBeginHandleGesture(Offset scene, double scale, CanvasState state) {
    final bounds = _currentSelectionBounds(state);
    if (bounds == null) return false;
    final handle = _hitTestHandle(bounds, scene, scale);
    if (handle == HandleKind.rotate && state.selectedShapeId != null) {
      state.beginInteractiveChange();
      final shape = state.shapes.firstWhere((s) => s.id == state.selectedShapeId);
      _activeHandle = handle;
      _rotatingShapeId = shape.id;
      _rotateCenter = bounds.center;
      _rotateStartShapeRotation = shape.rotation;
      _rotateStartPointerAngle = (scene - _rotateCenter).direction;
      return true;
    }
    if (handle != null && state.selectedShapeId != null) {
      state.beginInteractiveChange();
      _activeHandle = handle;
      _resizingShapeId = state.selectedShapeId;
      _resizeStartRect = bounds;
      _resizeAnchor = _oppositeAnchor(bounds, handle);
      return true;
    }
    return false;
  }

  /// Arms a potential move of [hit] (plus the rest of the current
  /// selection, if any) without committing to a selection change yet. The
  /// actual selection update happens in _onPanEnd once we know whether this
  /// was a tap (select only) or a drag (select + move), exactly like Canva:
  /// clicking a shape inside a multi-selection starts a move of the whole
  /// selection; clicking a shape outside the current selection arms a
  /// single-shape select+move.
  void _armPotentialMove(CanvasShape hit, Offset scene, CanvasState state) {
    final additive = HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    _pendingTapHitId = hit.id;
    _pendingTapAdditive = additive;

    final moveSet = (!additive && state.selectedShapeIds.contains(hit.id))
        ? state.selectedShapeIds
        : <String>{hit.id};

    _draggingShapeIds = {...moveSet, ...state.attachedDimensionIds(moveSet)};
    _movePrimaryId = hit.id;
    _moveStartScene = scene;
    _moveOriginalTopLeft.clear();
    _moveOriginalBottomRight.clear();
    _moveOriginalFreePoints.clear();
    for (final id in _draggingShapeIds!) {
      final s = state.shapes.firstWhereOrNull((s) => s.id == id);
      if (s == null) continue;
      _moveOriginalTopLeft[id] = s.topLeft;
      _moveOriginalBottomRight[id] = s.bottomRight;
      _moveOriginalFreePoints[id] = List.of(s.freePoints);
    }
  }

  /// Applies the deferred selection change from a pending tap (see
  /// _armPotentialMove) once we know the gesture turned into a real drag,
  /// then clears the pending-tap bookkeeping. beginInteractiveChange() is
  /// called here (not in _armPotentialMove) so a plain click that never
  /// moves doesn't push a no-op undo entry.
  void _commitPendingSelection(CanvasState state) {
    final id = _pendingTapHitId;
    if (id == null) return;
    state.beginInteractiveChange();
    if (_pendingTapAdditive) {
      if (!state.selectedShapeIds.contains(id)) state.toggleSelection(id);
    } else if (!state.selectedShapeIds.contains(id)) {
      state.selectShape(id);
    }
    _pendingTapHitId = null;
  }

  double _lastScaleGestureScale = 1.0;

  void _onScaleStart(ScaleStartDetails d, CanvasState state) {
    _lastScaleGestureScale = 1.0;
    // Two (or more) fingers down at the very start of the gesture: this is
    // always a pinch/pan-the-canvas gesture, regardless of what's
    // underneath — never a select/move/resize, even over a shape.
    if (d.pointerCount >= 2) return;
    _onPanStart(d.localFocalPoint, state);
  }

  void _onScaleUpdate(ScaleUpdateDetails d, CanvasState state) {
    // Two or more fingers: always pan/zoom the canvas, regardless of what
    // a single finger might have started on. If a second finger joins
    // mid-gesture (e.g. it started as a one-finger move/resize), abort
    // that gesture first so a pinch always wins and never fights with it.
    if (d.pointerCount >= 2) {
      if (_activeHandle != null ||
          _draggingShapeIds != null ||
          _pendingTapHitId != null ||
          _selectionBoxStartScene != null ||
          _lineStartScene != null ||
          _curvePoints != null) {
        _abortSingleFingerGesture();
      }
      final incremental = d.scale / _lastScaleGestureScale;
      _lastScaleGestureScale = d.scale;
      if (incremental != 1.0) {
        zoomBy(incremental, focal: d.localFocalPoint);
      }
      final scale = _controller.value.getMaxScaleOnAxis();
      final m = _controller.value.clone();
      m.translateByDouble(d.focalPointDelta.dx / scale, d.focalPointDelta.dy / scale, 0, 1);
      _controller.value = m;
      return;
    }
    _onPanUpdate(d.localFocalPoint, d.focalPointDelta, state);
  }

  // Scene point where the current pointer gesture started.
  Offset? _downScene;

  void _onPanStart(Offset localPosition, CanvasState state) {
    final scene = _toScene(localPosition);
    _downScene = scene;
    final scale = _controller.value.getMaxScaleOnAxis();

    if (state.toolMode == ToolMode.eraser) {
      final hit = _hitTest(state, scene);
      if (hit != null) state.deleteShape(hit.id);
      return;
    }

    // Any angle marker's arc can be grabbed in any tool mode (except the
    // eraser): pressing it selects the marker and drags the arc.
    if (_tryBeginAngleArcDrag(scene, state)) return;

    // Dimension and radius tools own every click while active: selection
    // is disabled (setTool already dropped it), so clicks never land on
    // the handle/select logic below and go straight to placing a point.
    if (state.toolMode == ToolMode.dimension) {
      // Clicking a circle with the dimension tool marks its radius; any
      // other click measures a straight edge as before.
      _handleDimensionTap(scene, state);
      return;
    }

    if (state.toolMode == ToolMode.angle) {
      _handleAngleTap(scene, state);
      return;
    }

    // Line tool: a drag always draws a new line, even when it starts on an
    // existing line's endpoint or handle, so lines can be chained together.
    if (state.toolMode == ToolMode.line) {
      if (_hitTest(state, scene) == null) state.clearSelection();
      // Snap the start onto an existing line's endpoint (or other anchor)
      // so consecutive lines join without a gap.
      final start = snapPoint(scene, state.shapes.toList()).point;
      setState(() {
        _lineStartScene = start;
        _lineEndScene = start;
      });
      return;
    }

    // Freehand tool: a one-finger drag always draws, even over a shape or
    // a selection handle. Panning is two-finger only in this mode.
    if (state.toolMode == ToolMode.curvedLine) {
      _pendingTapHitId = null;
      setState(() => _curvePoints = [scene]);
      return;
    }

    // 1) A handle on the current selection always wins, in any tool mode:
    // resize/rotate an already-selected shape even while a drawing tool is
    // active, since the selection and its handles are already on screen.
    if (_tryBeginHandleGesture(scene, scale, state)) return;

    // 2) Hitting an existing shape that is ALREADY selected: dragging it
    // moves it. Arm a potential move now (for responsive dragging) but
    // defer the actual selection change to _onPanEnd, so a plain click on
    // an already-selected shape doesn't misfire additive/replace logic
    // before we know this was a tap.
    final hit = _hitTest(state, scene);
    if (hit != null && state.selectedShapeIds.contains(hit.id)) {
      _armPotentialMove(hit, scene, state);
      return;
    }

    // 2b) Pressing anywhere inside a multi-selection's box (including the
    // empty gaps between its objects) moves the whole group together. A tap
    // there must not change the selection, so the pending tap is cleared.
    if (state.selectedShapeIds.length > 1) {
      final bounds = _currentSelectionBounds(state);
      if (bounds != null && bounds.inflate(6 / scale).contains(scene)) {
        final primary = state.shapes.firstWhereOrNull((s) => state.selectedShapeIds.contains(s.id));
        if (primary != null) {
          _armPotentialMove(primary, scene, state);
          _pendingTapHitId = null;
          return;
        }
      }
    }

    // Freehand tool: a one-finger drag always draws, even over a shape.
    // Panning is two-finger only in this mode.
    if (state.toolMode == ToolMode.curvedLine) {
      _pendingTapHitId = null;
      setState(() => _curvePoints = [scene]);
      return;
    }

    // 3) Hitting a shape that is NOT currently selected: defer selection
    // until we know whether this is a tap or a drag, exactly like the
    // empty-space case below. A plain tap (no movement) selects it; a
    // drag instead pans the canvas and leaves selection untouched, so
    // dragging across an unselected shape never moves or selects it.
    if (hit != null) {
      final additive =
          HardwareKeyboard.instance.isShiftPressed ||
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      _pendingTapHitId = hit.id;
      _pendingTapAdditive = additive;
      _isPanning = true;
      _panStartedOnShape = true;
      _panTotalDelta = Offset.zero;
      return;
    }

    // 4) Empty space with the line or freehand-curve tool active: a
    // single-finger drag draws instead of panning (two-finger drag/pinch
    // still pans/zooms via _onScaleUpdate's pointerCount >= 2 branch).
    _pendingTapHitId = null;

    if (state.toolMode == ToolMode.curvedLine) {
      setState(() => _curvePoints = [scene]);
      return;
    }

    // Text tool: a tap on empty space drops a template text object there.
    if (state.toolMode == ToolMode.text) {
      state.addText(scene);
      state.setTool(ToolMode.select);
      return;
    }

    // 5) Empty space, any other tool: the select tool and panning are
    // mutually exclusive. With select active, dragging empty space draws
    // a rubber-band selection box; otherwise (the default) it pans.
    if (state.toolMode == ToolMode.select) {
      setState(() {
        _selectionBoxStartScene = scene;
        _selectionBoxEndScene = scene;
      });
      return;
    }

    _isPanning = true;
    _panTotalDelta = Offset.zero;
  }


  /// Angle arc drag: a press on the arc (within a few px of its curve) and
  /// drag changes its radius. Dragging the arc across the vertex flips it
  /// between the inside and outside angle.
  bool _tryBeginAngleArcDrag(Offset scene, CanvasState state) {
    final tol = 8 / _controller.value.getMaxScaleOnAxis();
    for (final s in state.shapes.toList().reversed) {
      if (s.type != ShapeType.angleDimension) continue;
      final a = state.shapes.firstWhereOrNull((x) => x.id == s.refShapeId);
      final b = state.shapes.firstWhereOrNull((x) => x.id == s.refShapeId2);
      if (a == null || b == null) continue;
      final vertex = s.topLeft;
      final arc = angleArcFor(
        _rayAngleTo(a, vertex),
        _rayAngleTo(b, vertex),
        outside: s.angleOutside,
      );
      final d = (scene - vertex).distance;
      // A selected arc is easier to grab, so it gets a wider band.
      final band = state.selectedShapeIds.contains(s.id) ? tol * 1.75 : tol;
      final onCurve = (d - s.angleRadius).abs() <= band;
      final ang = math.atan2(scene.dy - vertex.dy, scene.dx - vertex.dx);
      if (onCurve && _angleInSweep(ang, arc)) {
        _angleDragId = s.id;
        state.selectShape(s.id);
        return true;
      }
    }
    return false;
  }

  String? _angleDragId;

  /// True if [ang] lies within an arc's sweep.
  bool _angleInSweep(double ang, AngleArc arc) {
    var rel = ang - arc.startAngle;
    while (rel > math.pi) {
      rel -= 2 * math.pi;
    }
    while (rel < -math.pi) {
      rel += 2 * math.pi;
    }
    if (arc.sweep >= 0) return rel >= 0 && rel <= arc.sweep;
    return rel <= 0 && rel >= arc.sweep;
  }

  /// Drag update for an angle arc: the radius follows the pointer, and when
  /// the pointer is on the far side of the vertex from the arc's bisector,
  /// the arc flips to the other angle.
  void _onAngleArcDrag(Offset scene, CanvasState state) {
    final id = _angleDragId;
    if (id == null) return;
    final s = state.shapes.firstWhereOrNull((x) => x.id == id);
    if (s == null) return;
    final vertex = s.topLeft;
    final d = scene - vertex;
    final a = state.shapes.firstWhereOrNull((x) => x.id == s.refShapeId);
    final b = state.shapes.firstWhereOrNull((x) => x.id == s.refShapeId2);
    if (a == null || b == null) return;
    final inside = angleArcFor(_rayAngleTo(a, vertex), _rayAngleTo(b, vertex));
    final pointer = math.atan2(d.dy, d.dx);
    // The inside angle is the shape's wedge at the vertex. While the arc
    // stays inside that wedge it shows the inside angle; once dragged past
    // either line (outside the shape) it switches to the outside angle.
    final wantOutside = !_angleInSweep(pointer, inside);
    state.setAngleArc(
      id,
      radius: math.max(14, d.distance),
      outside: wantOutside,
      degrees: inside.degrees,
    );
  }


  /// Topmost shape with a straight edge under [scene], or null.
  CanvasShape? _dimShapeAt(CanvasState state, Offset scene) {
    final tol = 10 / _controller.value.getMaxScaleOnAxis();
    for (final s in state.shapes.toList().reversed) {
      if (dimensionEdges(s).isEmpty) continue;
      if (edgeNear(s, scene, tol) != null) return s;
      if (s.type != ShapeType.line && s.rect.contains(scene)) return s;
    }
    return null;
  }

  /// The line a click refers to: the nearest edge if the click is on an
  /// outline, otherwise the topmost edge (the default for an interior click).
  DimEdge _dimEdgeAt(CanvasShape shape, Offset scene) {
    final tol = 10 / _controller.value.getMaxScaleOnAxis();
    return edgeNear(shape, scene, tol) ?? topmostEdge(shape);
  }

  /// First line picked by the angle tool, waiting for the second.
  CanvasShape? _angleFirstLine;

  /// Angle tool: the first tap picks a line, the second picks another line
  /// and places the angle arc where the two lines meet.
  void _handleAngleTap(Offset scene, CanvasState state) {
    final hit = _lineAt(state, scene);
    if (hit == null) return;
    if (_angleFirstLine == null) {
      setState(() => _angleFirstLine = hit);
      return;
    }
    if (hit.id == _angleFirstLine!.id) return;
    final vertex = _intersectLines(_angleFirstLine!, hit) ?? scene;
    state.addAngle(_angleFirstLine!, hit, vertex);
    setState(() => _angleFirstLine = null);
    state.setTool(ToolMode.select);
  }

  /// Topmost straight line under [scene], or null.
  CanvasShape? _lineAt(CanvasState state, Offset scene) {
    final tol = 10 / _controller.value.getMaxScaleOnAxis();
    for (final s in state.shapes.toList().reversed) {
      if (s.type != ShapeType.line) continue;
      if (distanceToEdge(scene, DimEdge(s.topLeft, s.bottomRight)) <= tol) return s;
    }
    return null;
  }

  /// Intersection of the infinite lines through [a] and [b], or null if
  /// they are parallel.
  Offset? _intersectLines(CanvasShape a, CanvasShape b) {
    final p = a.topLeft, r = a.bottomRight - a.topLeft;
    final q = b.topLeft, s = b.bottomRight - b.topLeft;
    final denom = r.dx * s.dy - r.dy * s.dx;
    if (denom.abs() < 1e-9) return null;
    final t = ((q.dx - p.dx) * s.dy - (q.dy - p.dy) * s.dx) / denom;
    return p + r * t;
  }

  /// Shape picked by the dimension tool that is waiting for a second pick.
  CanvasShape? _dimFirstShape;

  /// Dimension tool: tap one shape, then tap a second shape to dimension the
  /// shortest distance between the two. Works for any shape. Tapping the
  /// same shape twice measures its own edge (or radius, for a circle).
  void _handleDimensionTap(Offset scene, CanvasState state) {
    final picked = _measurableShapeAt(state, scene);
    final first = _dimFirstShape;
    if (picked == null) {
      // Tapping empty space cancels a pending first pick.
      if (first != null) {
        setState(() => _dimFirstShape = null);
        state.clearSelection();
      }
      return;
    }
    if (first == null) {
      setState(() => _dimFirstShape = picked);
      state.selectShape(picked.id);
      return;
    }
    setState(() => _dimFirstShape = null);
    if (picked.id == first.id) {
      if (picked.type == ShapeType.circle) {
        _handleRadiusTap(scene, state);
      } else {
        _measureEdgeTap(scene, state);
      }
      return;
    }
    final gap = _dimensionGap(first, picked);
    state.clearSelection();
    if (gap == null) return;
    state.addDimension(gap.a, gap.b, offset: 28);
    state.setTool(ToolMode.select);
  }

  /// The two points a distance dimension runs between. A circle is measured
  /// from its centre: centre to centre for two circles, otherwise centre to
  /// the nearest point on the other shape. Other pairs use the shortest gap
  /// between their outlines.
  ShapeGap? _dimensionGap(CanvasShape a, CanvasShape b) {
    final aIsCircle = a.type == ShapeType.circle;
    final bIsCircle = b.type == ShapeType.circle;
    if (aIsCircle && bIsCircle) {
      final ca = a.rect.center, cb = b.rect.center;
      return ShapeGap(ca, cb, (cb - ca).distance);
    }
    if (aIsCircle || bIsCircle) {
      final centreShape = aIsCircle ? a : b;
      final other = aIsCircle ? b : a;
      final centre = centreShape.rect.center;
      final edge = closestPointOnShape(centre, other);
      if (edge == null) return null;
      return aIsCircle
          ? ShapeGap(centre, edge, (edge - centre).distance)
          : ShapeGap(edge, centre, (edge - centre).distance);
    }
    return closestBetweenShapes(a, b);
  }

  /// Topmost non-dimension shape under [scene], or null.
  CanvasShape? _measurableShapeAt(CanvasState state, Offset scene) {
    for (final s in state.shapes.toList().reversed) {
      if (s.type == ShapeType.dimension ||
          s.type == ShapeType.radiusDimension ||
          s.type == ShapeType.angleDimension) {
        continue;
      }
      if (hitTestShape(s, scene)) return s;
    }
    return null;
  }

  /// Measures the edge under [scene] (the original single-shape dimension).
  void _measureEdgeTap(Offset scene, CanvasState state) {
    final shape = _dimShapeAt(state, scene);
    if (shape == null) return;
    final edge = _dimEdgeAt(shape, scene);
    // A semicircle's flat side is its only line, so its dimension hugs it
    // rather than floating the default distance away.
    final outward = _outwardOffset(edge.a, edge.b, shape);
    // A semicircle's flat edge is its bottom side; push the dimension
    // straight down from it (away from the dome) and keep it close.
    final offset = shape.type == ShapeType.semiCircle
        ? _semiCircleFlatOffset(edge, shape)
        : outward;
    state.addDimension(edge.a, edge.b, offset: offset, refShapeId: shape.id);
    state.setTool(ToolMode.select);
  }

  /// Signed distance (magnitude 28) to offset a dimension line by, along
  /// its own normal, so it lands on the side of [refShape] that's away
  /// from the shape's center — i.e. outside it — rather than a fixed side
  /// that can cut back across the shape depending on click order.
  /// Offset for a semicircle's flat-edge dimension: a small gap on the side
  /// of the flat edge facing away from the dome, so it sits right against
  /// the line instead of below the shape.
  double _semiCircleFlatOffset(DimEdge edge, CanvasShape shape) {
    const gap = 6.0;
    final delta = edge.b - edge.a;
    if (delta.distance < 0.5) return gap;
    final dir = math.atan2(delta.dy, delta.dx);
    final normal = Offset(-math.sin(dir), math.cos(dir));
    // Dome is above the flat edge, so the side away from it is the one
    // whose normal points away from the rect center.
    final toCenter = shape.rect.center - Offset((edge.a.dx + edge.b.dx) / 2, (edge.a.dy + edge.b.dy) / 2);
    final dot = normal.dx * toCenter.dx + normal.dy * toCenter.dy;
    return dot > 0 ? -gap : gap;
  }

  double _outwardOffset(Offset a, Offset b, CanvasShape? refShape) {
    const mag = 28.0;
    if (refShape == null) return mag;
    final delta = b - a;
    if (delta.distance < 0.5) return mag;
    final dir = math.atan2(delta.dy, delta.dx);
    final normal = Offset(-math.sin(dir), math.cos(dir));
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final toMid = mid - refShape.rect.center;
    final dot = normal.dx * toMid.dx + normal.dy * toMid.dy;
    return dot >= 0 ? mag : -mag;
  }

  /// Radius tool: a single click on a circle/ellipse immediately creates
  /// its radius dimension — a leader from outside the circle in to the
  /// circumference nearest the click, CAD-style — with no second click
  /// needed. A circle already marked, or an empty-space click, does
  /// nothing: each circle gets at most one radius dimension.
  void _handleRadiusTap(Offset scene, CanvasState state) {
    final hit = _hitTest(state, scene);
    if (hit == null || hit.type != ShapeType.circle) {
      return;
    }
    if (state.hasRadiusDimension(hit.id)) return;
    state.addRadiusDimension(hit.id, scene);
    state.setTool(ToolMode.select);
  }

  Offset _oppositeAnchor(Rect bounds, HandleKind handle) {
    switch (handle) {
      case HandleKind.topLeft:
        return bounds.bottomRight;
      case HandleKind.topRight:
        return bounds.bottomLeft;
      case HandleKind.bottomLeft:
        return bounds.topRight;
      case HandleKind.bottomRight:
        return bounds.topLeft;
      case HandleKind.top:
        return Offset(bounds.center.dx, bounds.bottom);
      case HandleKind.bottom:
        return Offset(bounds.center.dx, bounds.top);
      case HandleKind.left:
        return Offset(bounds.right, bounds.center.dy);
      case HandleKind.right:
        return Offset(bounds.left, bounds.center.dy);
      case HandleKind.rotate:
        return bounds.center;
    }
  }

  void _onPanUpdate(Offset localPosition, Offset delta, CanvasState state) {
    final scene = _toScene(localPosition);

    if (_angleDragId != null) {
      _onAngleArcDrag(scene, state);
      return;
    }

    // --- Rotate the selected shape around the selection-bounds center ---
    if (_activeHandle == HandleKind.rotate && _rotatingShapeId != null) {
      final pointerAngle = (scene - _rotateCenter).direction;
      var newRotation = _rotateStartShapeRotation + (pointerAngle - _rotateStartPointerAngle);

      // Snap to common angles (0/45/90/.../315, in any full rotation)
      // when within a small tolerance, unless shift is held to rotate
      // freely. Snapping is done on the absolute on-screen angle so it
      // lines up with the horizontal/vertical grid regardless of the
      // shape's starting rotation.
      final freeRotate = HardwareKeyboard.instance.isShiftPressed;
      if (!freeRotate) {
        const snapStepDeg = 45.0;
        const snapToleranceDeg = 4.0;
        final degrees = newRotation * 180 / math.pi;
        final nearestSnap = (degrees / snapStepDeg).round() * snapStepDeg;
        if ((degrees - nearestSnap).abs() <= snapToleranceDeg) {
          newRotation = nearestSnap * math.pi / 180;
        }
      }

      state.rotateShapeTo(_rotatingShapeId!, newRotation);
      setState(() => _liveRotationDeg = newRotation * 180 / math.pi);
      return;
    }

    // --- Resize / scale an existing selected shape ---
    if (_activeHandle != null && _activeHandle != HandleKind.rotate && _resizingShapeId != null && _resizeStartRect != null && _resizeAnchor != null) {
      final anchor = _resizeAnchor!;
      Rect newRect;
      switch (_activeHandle!) {
        case HandleKind.topLeft:
        case HandleKind.topRight:
        case HandleKind.bottomLeft:
        case HandleKind.bottomRight:
          newRect = Rect.fromPoints(anchor, scene);
          break;
        case HandleKind.top:
        case HandleKind.bottom:
          newRect = Rect.fromLTRB(_resizeStartRect!.left, anchor.dy < scene.dy ? anchor.dy : scene.dy,
              _resizeStartRect!.right, anchor.dy < scene.dy ? scene.dy : anchor.dy);
          break;
        case HandleKind.left:
        case HandleKind.right:
          newRect = Rect.fromLTRB(anchor.dx < scene.dx ? anchor.dx : scene.dx, _resizeStartRect!.top,
              anchor.dx < scene.dx ? scene.dx : anchor.dx, _resizeStartRect!.bottom);
          break;
        case HandleKind.rotate:
          newRect = _resizeStartRect!;
          break;
      }
      // Snap the free corner/edge of the resize against other shapes'
      // edges/centers (relative snapping), same as move/draw does.
      final others = state.shapes.where((s) => s.id != _resizingShapeId).toList();
      final otherSnap = snapRectToShapes(newRect, others);
      newRect = otherSnap.rect;
      var guides = otherSnap.guides;

      // Also snap to the shape's own symmetry (equal width/height, i.e.
      // becoming a square) when dragging a corner — only if snapping to
      // another shape didn't already take effect on both axes, so the two
      // don't fight each other.
      final isCornerHandle = _activeHandle == HandleKind.topLeft ||
          _activeHandle == HandleKind.topRight ||
          _activeHandle == HandleKind.bottomLeft ||
          _activeHandle == HandleKind.bottomRight;
      if (isCornerHandle && otherSnap.guides.length < 2) {
        final selfSnap = snapRectToOwnSymmetry(newRect, anchor);
        if (selfSnap.guides.isNotEmpty) {
          newRect = selfSnap.rect;
          guides = [...guides, ...selfSnap.guides];
        }
      }

      final scaleX = _resizeStartRect!.width.abs() < 0.001 ? 1.0 : newRect.width / _resizeStartRect!.width;
      final scaleY = _resizeStartRect!.height.abs() < 0.001 ? 1.0 : newRect.height / _resizeStartRect!.height;
      state.scaleShapeFrom(_resizingShapeId!, anchor, scaleX, scaleY);
      _resizeStartRect = newRect;
      setState(() => _activeGuides = guides);
      return;
    }

    // --- Rubber-band selection ---
    if (_selectionBoxStartScene != null) {
      setState(() => _selectionBoxEndScene = scene);
      return;
    }

    // --- Moving selected shape(s): computed from the drag-start snapshot +
    // total delta each frame (not incremental per-frame deltas), so that
    // snapping the primary shape against other shapes doesn't accumulate
    // drift. ---
    if (_draggingShapeIds != null &&
        _moveStartScene != null &&
        _movePrimaryId != null) {
      // Commit the pending tap's selection change the first time the
      // pointer actually moves past the tap threshold, so a real drag
      // selects (if needed) and starts moving in one motion, matching
      // Canva: click-and-drag a shape moves it without a separate click.
      if (_pendingTapHitId != null) {
        _commitPendingSelection(state);
      }
      final rawDelta = scene - _moveStartScene!;
      final primaryOriginalTL = _moveOriginalTopLeft[_movePrimaryId!];
      final primaryOriginalBR = _moveOriginalBottomRight[_movePrimaryId!];

      var delta = rawDelta;
      var guides = const <AlignmentGuide>[];
      final primaryIsDimension = state.shapes
              .firstWhereOrNull((s) => s.id == _movePrimaryId)
              ?.type ==
          ShapeType.dimension; // dimension drag only slides its line: no edge snapping
      if (!primaryIsDimension && primaryOriginalTL != null && primaryOriginalBR != null) {
        final rawRect = Rect.fromPoints(primaryOriginalTL + rawDelta, primaryOriginalBR + rawDelta);
        final others = state.shapes.where((s) => !_draggingShapeIds!.contains(s.id)).toList();
        final snapResult = snapRectToShapes(rawRect, others);
        delta = rawDelta + (snapResult.rect.topLeft - rawRect.topLeft);
        guides = snapResult.guides;
      }

      state.moveShapesToDelta(
        _draggingShapeIds!,
        delta,
        _moveOriginalTopLeft,
        _moveOriginalBottomRight,
        _moveOriginalFreePoints,
      );
      setState(() => _activeGuides = guides);
      return;
    }

    // --- Dragging out a straight line ---
    if (_lineStartScene != null) {
      final snap = snapLineEnd(_lineStartScene!, scene, state.shapes.toList());
      setState(() {
        _lineEndScene = snap.end;
        _activeGuides = snap.extraGuide == null ? [] : [snap.extraGuide!];
      });
      return;
    }

    // --- Dragging out a freehand curve ---
    if (_curvePoints != null) {
      setState(() => _curvePoints = [..._curvePoints!, scene]);
      return;
    }

    if (_isPanning) {
      _panTotalDelta += delta;
      final scale = _controller.value.getMaxScaleOnAxis();
      final m = _controller.value.clone();
      m.translateByDouble(delta.dx / scale, delta.dy / scale, 0, 1);
      _controller.value = m;
      return;
    }
  }

  /// The dimension whose number is under [scene], or null. Dimension labels
  /// sit off the measured line, so they need their own hit check.
  CanvasShape? _dimensionLabelAt(CanvasState state, Offset? scene) {
    if (scene == null) return null;
    final s = _controller.value.getMaxScaleOnAxis();
    for (final shape in state.shapes.toList().reversed) {
      if (shape.type != ShapeType.dimension &&
          shape.type != ShapeType.radiusDimension &&
          shape.type != ShapeType.angleDimension) {
        continue;
      }
      final at = _labelAnchor(shape, state.shapes.toList()).at;
      // Generous box around the anchor so a tap on the number always lands,
      // even where the painted label is offset from the approximate anchor.
      final box = Rect.fromCenter(center: at, width: 80 / s, height: 44 / s);
      if (box.contains(scene)) return shape;
    }
    return null;
  }

  void _onPanEnd(CanvasState state) {
    if (_angleDragId != null) {
      _angleDragId = null;
      return;
    }

    // Double-tap on a text object opens its inline editor. A tap counts as
    // "same target" when the second tap lands on the same shape within 350ms.
    final labelShape = _dimensionLabelAt(state, _downScene);
    final tapId = labelShape?.id ?? _pendingTapHitId;
    if (tapId != null && _wasTapNotDrag()) {
      final now = DateTime.now();
      final isDoubleTap = _lastTapId == tapId &&
          _lastTapTime != null &&
          now.difference(_lastTapTime!) < const Duration(milliseconds: 350);
      _lastTapId = tapId;
      _lastTapTime = now;
      if (isDoubleTap) {
        final shape = state.shapes.firstWhereOrNull((s) => s.id == tapId);
        if (shape != null && _isLabelled(shape.type)) {
          _lastTapId = null;
          _lastTapTime = null;
          _beginTextEdit(shape.id, state);
          return;
        }
      }
    }

    if (_activeHandle != null) {
      _activeHandle = null;
      _resizingShapeId = null;
      _resizeStartRect = null;
      _resizeAnchor = null;
      _rotatingShapeId = null;
      setState(() {
        _activeGuides = [];
        _liveRotationDeg = null;
      });
      return;
    }

    // Rubber-band selection (select-tool only): if the box never grew past
    // a tap, treat this as a plain click — select the shape if the tap
    // landed on one despite _hitTest missing it at pan-start (shouldn't
    // normally happen), otherwise deselect (click on empty space).
    if (_selectionBoxStartScene != null && _selectionBoxEndScene != null) {
      final box = Rect.fromPoints(_selectionBoxStartScene!, _selectionBoxEndScene!);
      final additive =
          HardwareKeyboard.instance.isShiftPressed ||
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      final moved = (_selectionBoxEndScene! - _selectionBoxStartScene!).distance > _tapMoveThreshold;
      if (moved) {
        // Only select shapes fully enclosed by the box (all edges inside),
        // not just touched/overlapped by it.
        final ids = state.shapes.where((s) => box.contains(s.rect.topLeft) && box.contains(s.rect.bottomRight)).map((s) => s.id);
        if (additive) {
          state.selectShapes({...state.selectedShapeIds, ...ids});
        } else if (ids.isNotEmpty) {
          state.selectShapes(ids);
        }
      } else if (!additive) {
        // A tap on empty space: clear the current selection.
        state.clearSelection();
      }
      setState(() {
        _selectionBoxStartScene = null;
        _selectionBoxEndScene = null;
      });
      return;
    }

    // A potential move that was armed on pan-start: if the pointer never
    // moved past the tap threshold, this was a plain click — resolve the
    // deferred selection now (select, or toggle if shift/ctrl-clicking).
    // If it did move, _onPanUpdate already committed the selection change
    // and performed the move; just clear the drag bookkeeping.
    if (_draggingShapeIds != null) {
      if (_pendingTapHitId != null) {
        final id = _pendingTapHitId!;
        if (_pendingTapAdditive) {
          state.toggleSelection(id);
        } else {
          state.selectShape(id);
        }
        _pendingTapHitId = null;
      }
      _draggingShapeIds = null;
      _moveStartScene = null;
      _movePrimaryId = null;
      _moveOriginalTopLeft.clear();
      _moveOriginalBottomRight.clear();
      _moveOriginalFreePoints.clear();
      setState(() => _activeGuides = []);
      return;
    }

    // Commit a dragged-out straight line, unless it never grew past a tap
    // (a plain tap with the line tool draws nothing).
    if (_lineStartScene != null) {
      final start = _lineStartScene!;
      final end = _lineEndScene ?? start;
      if ((end - start).distance > _tapMoveThreshold) {
        final shape = state.addShape(ShapeType.line, start, end);
        state.selectShape(shape.id);
      } else {
        // A tap on empty canvas clears the selection, like the select tool.
        state.clearSelection();
      }
      setState(() {
        _lineStartScene = null;
        _lineEndScene = null;
        _activeGuides = [];
      });
      return;
    }

    // Commit a dragged-out freehand curve, unless it never grew past a tap.
    if (_curvePoints != null) {
      final pts = _curvePoints!;
      if (pts.length > 1 && (pts.last - pts.first).distance > _tapMoveThreshold) {
        final shape = state.addFreeform(ShapeType.curvedLine, pts);
        state.selectShape(shape.id);
      }
      setState(() => _curvePoints = null);
      return;
    }

    if (_isPanning) {
      final wasTap = _panTotalDelta.distance <= _tapMoveThreshold;
      if (_panStartedOnShape && _pendingTapHitId != null) {
        // The pan started on an unselected shape: a plain tap selects it
        // (toggling if shift/ctrl-held); an actual drag just panned the
        // canvas, so leave selection untouched.
        if (wasTap) {
          state.beginInteractiveChange();
          if (_pendingTapAdditive) {
            state.toggleSelection(_pendingTapHitId!);
          } else {
            state.selectShape(_pendingTapHitId!);
          }
        }
        _pendingTapHitId = null;
      } else if (wasTap) {
        // A tap (no real movement) on empty space deselects, matching
        // click-on-empty-space elsewhere; an actual pan drag leaves the
        // selection untouched.
        state.clearSelection();
      }
      _isPanning = false;
      _panStartedOnShape = false;
      _panTotalDelta = Offset.zero;
    }
  }

  /// Shapes whose text can be edited inline by double-tapping.
  static bool _isLabelled(ShapeType t) =>
      t == ShapeType.text ||
      t == ShapeType.dimension ||
      t == ShapeType.radiusDimension ||
      t == ShapeType.angleDimension;

  /// Direction (radians) of the ray from [vertex] along [line], toward the
  /// endpoint farther from the vertex. Same rule as the painter.
  double _rayAngleTo(CanvasShape line, Offset vertex) {
    final far = (line.topLeft - vertex).distance >= (line.bottomRight - vertex).distance
        ? line.topLeft
        : line.bottomRight;
    final d = far - vertex;
    return math.atan2(d.dy, d.dx);
  }

  /// Angle label anchor: just outside the arc, on its bisector. Mirrors the
  /// painter so the double-tap hit box lines up with the drawn text.
  ({Offset at, double angle}) _angleLabelAnchor(CanvasShape shape, List<CanvasShape> shapes) {
    CanvasShape? find(String? id) {
      for (final s in shapes) {
        if (s.id == id) return s;
      }
      return null;
    }
    final a = find(shape.refShapeId);
    final b = find(shape.refShapeId2);
    final vertex = shape.topLeft;
    if (a == null || b == null) return (at: vertex, angle: 0);
    final arc = angleArcFor(
      _rayAngleTo(a, vertex),
      _rayAngleTo(b, vertex),
      outside: shape.angleOutside,
    );
    final unit = Offset(math.cos(arc.bisector), math.sin(arc.bisector));
    return (at: vertex + unit * (shape.angleRadius + 14), angle: 0);
  }

  /// Scene-space anchor and rotation of a dimension's label. Must match the
  /// painter: linear labels sit at the dimension line's midpoint, rotated to
  /// the line; radius labels sit beyond the outer (label) end, away from
  /// the circle, along the leader's own direction.
  ({Offset at, double angle}) _labelAnchor(CanvasShape shape, List<CanvasShape> shapes) {
    if (shape.type == ShapeType.angleDimension) {
      return _angleLabelAnchor(shape, shapes);
    }
    final a = shape.topLeft;
    final b = shape.bottomRight;
    final delta = b - a;
    final dir = math.atan2(delta.dy, delta.dx);
    if (shape.type == ShapeType.radiusDimension) {
      final unit = Offset(math.cos(dir), math.sin(dir));
      return (at: b + unit * 20, angle: dir);
    }
    final offset = shape.freePoints.isNotEmpty ? shape.freePoints.first.dx : 28.0;
    final normal = Offset(-math.sin(dir), math.cos(dir));
    final sign = offset >= 0 ? 1.0 : -1.0;
    final outward = normal * sign;
    // Same push-out as the painter, using an approximate label half-size.
    final ext = outward.dx.abs() * 14 + outward.dy.abs() * 9 + 6;
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2) + normal * offset + outward * ext;
    return (at: mid, angle: dir);
  }

  Widget _buildTextEditor(CanvasState state) {
    final shape = state.shapes.firstWhereOrNull((s) => s.id == _editingTextId);
    if (shape == null) return const SizedBox.shrink();

    // Scene -> screen: apply the current pan/zoom matrix to the shape rect.
    final m = _controller.value;
    final scale = m.getMaxScaleOnAxis();
    final style = shape.style;

    Rect screenRect;
    if (shape.type == ShapeType.text) {
      final topLeft = MatrixUtils.transformPoint(m, shape.rect.topLeft);
      final bottomRight = MatrixUtils.transformPoint(m, shape.rect.bottomRight);
      screenRect = Rect.fromPoints(topLeft, bottomRight);
    } else {
      // Dimension label: a compact field centred on the label anchor.
      final anchor = MatrixUtils.transformPoint(m, _labelAnchor(shape, state.shapes.toList()).at);
      const w = 96.0, h = 28.0;
      screenRect = Rect.fromCenter(center: anchor, width: w, height: h);
    }

    return Positioned(
      left: screenRect.left,
      top: screenRect.top,
      width: screenRect.width,
      height: screenRect.height,
      child: Focus(
        onKeyEvent: (node, event) {
          // Escape cancels the edit. Plain key events are otherwise left to
          // the TextField, so modifier keys (Alt, Shift) never reach the
          // canvas gesture code while typing.
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            _endTextEdit();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: _textController,
          focusNode: _textFocus,
          autofocus: true,
          maxLines: null,
          textAlign: TextAlign.center,
          onSubmitted: (_) => _commitTextEdit(state),
          onTapOutside: (_) => _commitTextEdit(state),
          style: fontTextStyle(style.fontFamily, size: style.fontSize * scale, color: style.textColor).copyWith(
            fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
            fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
            decoration: style.underline ? TextDecoration.underline : TextDecoration.none,
          ),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CanvasState>();
    final selectionBounds = _currentSelectionBounds(state);
    final selectionBoxRect = (_selectionBoxStartScene != null && _selectionBoxEndScene != null)
        ? Rect.fromPoints(_selectionBoxStartScene!, _selectionBoxEndScene!)
        : null;

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          final factor = event.scrollDelta.dy > 0 ? 0.92 : 1.08;
          zoomBy(factor, focal: event.localPosition);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (d) => _onScaleStart(d, state),
        onScaleUpdate: (d) => _onScaleUpdate(d, state),
        onScaleEnd: (d) => _onPanEnd(state),
        child: Container(
          color: const Color(0xFFF7F8FB),
          child: ClipRect(
            child: Stack(
              children: [
                CustomPaint(
                  painter: DotGridPainter(transform: _controller.value),
                  foregroundPainter: ShapePainter(
                    shapes: state.shapes,
                    transform: _controller.value,
                    selectedId: state.selectedShapeId,
                    selectedIds: state.selectedShapeIds,
                    previewShape: _previewShape,
                    selectionBounds: selectionBounds,
                    selectionBoxRect: selectionBoxRect,
                    alignmentGuides: _activeGuides,
                    liveRotationDeg: _liveRotationDeg,
                    hiddenShapeId: _editingTextId,
                  ),
                  child: const SizedBox.expand(),
                ),
                if (_editingTextId != null) _buildTextEditor(state),

              ],
            ),
          ),
        ),
      ),
    );
  }
}
