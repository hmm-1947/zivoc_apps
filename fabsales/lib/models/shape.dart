import 'package:flutter/painting.dart';

enum ShapeType {
  rectangle,
  square,
  circle,

  semiCircle,
  triangle,
  rightTriangle,
  diamond,
  pentagon,
  hexagon,

  arrow,
  doubleArrow,
  line,
  curvedLine,
  door,
  doorDouble,
  window,
  windowSliding,
  text,
  dimension,
  radiusDimension,
  angleDimension,
}

/// Each option maps to a concrete Windows font, with cross-platform fallbacks
/// so the choice still renders if the first font isn't installed.
const Map<String, List<String>> kFontStacks = {
  'Sans': ['Segoe UI', 'Arial', 'Roboto', 'sans-serif'],
  'Serif': ['Georgia', 'Times New Roman', 'serif'],
  'Monospace': ['Consolas', 'Courier New', 'monospace'],
  'Handwriting': ['Segoe Print', 'Comic Sans MS', 'cursive'],
};

/// Resolves a stored font label (e.g. 'Serif') to a TextStyle font family
/// plus fallbacks, so the text renders in that face on Windows.
TextStyle fontTextStyle(String label, {double? size, Color? color}) {
  final stack = kFontStacks[label] ?? kFontStacks['Sans']!;
  return TextStyle(
    fontFamily: stack.first,
    fontFamilyFallback: stack.skip(1).toList(),
    fontSize: size,
    color: color,
  );
}

class ShapeStyle {
  final Color strokeColor;
  final double strokeWidth;
  final Color fillColor;
  final bool filled;

  // Text-only properties (ignored by non-text shapes).
  final String fontFamily;
  final double fontSize;
  final Color textColor;
  final bool bold;
  final bool italic;
  final bool underline;

  const ShapeStyle({
    this.strokeColor = const Color(0xFF1A1A2E),
    this.strokeWidth = 2.0,
    this.fillColor = const Color(0x00000000),
    this.filled = false,
    this.fontFamily = 'Sans',
    this.fontSize = 24.0,
    this.textColor = const Color(0xFF1A1A2E),
    this.bold = false,
    this.italic = false,
    this.underline = false,
  });

  ShapeStyle copyWith({
    Color? strokeColor,
    double? strokeWidth,
    Color? fillColor,
    bool? filled,
    String? fontFamily,
    double? fontSize,
    Color? textColor,
    bool? bold,
    bool? italic,
    bool? underline,
  }) {
    return ShapeStyle(
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      fillColor: fillColor ?? this.fillColor,
      filled: filled ?? this.filled,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      textColor: textColor ?? this.textColor,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
    );
  }
}

class CanvasShape {
  final String id;
  final ShapeType type;
  Offset topLeft;
  Offset bottomRight;
  double rotation;
  ShapeStyle style;
  List<Offset> freePoints;
  String? text;

  /// For a radiusDimension: id of the circle/ellipse it measures, so its
  /// centre can stay pinned to that shape when the dimension is dragged.
  String? refShapeId;

  /// For an angleDimension: id of the second line (refShapeId is the first).
  String? refShapeId2;

  /// For an angleDimension: true when the arc shows the outside (reflex)
  /// angle instead of the inside one. Set by dragging the arc past the vertex.
  bool angleOutside;

  /// For an angleDimension: arc radius in scene units.
  double angleRadius;

  CanvasShape({
    required this.id,
    required this.type,
    required this.topLeft,
    required this.bottomRight,
    this.rotation = 0,
    ShapeStyle? style,
    List<Offset>? freePoints,
    this.text,
    this.refShapeId,
    this.refShapeId2,
    this.angleOutside = false,
    this.angleRadius = 36,
  })  : style = style ?? const ShapeStyle(),
        freePoints = freePoints ?? const [];

  Rect get rect => Rect.fromPoints(topLeft, bottomRight);

  double get lengthPx => (bottomRight - topLeft).distance;

  /// Angle in degrees, standard math convention (0 = right, -90 = up/screen-up).
  double get angleDeg => (bottomRight - topLeft).direction * 180 / 3.141592653589793;

  CanvasShape clone() => CanvasShape(
        id: id,
        type: type,
        topLeft: topLeft,
        bottomRight: bottomRight,
        rotation: rotation,
        style: style,
        freePoints: List.of(freePoints),
        text: text,
        refShapeId: refShapeId,
        refShapeId2: refShapeId2,
        angleOutside: angleOutside,
        angleRadius: angleRadius,
      );
}
