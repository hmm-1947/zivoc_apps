import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/canvas_state.dart';
import '../models/shape.dart';
import 'infinite_canvas.dart';

class ShapeEntry {
  final ShapeType type;
  final IconData icon;
  final String label;
  const ShapeEntry(this.type, this.icon, this.label);
}

const List<ShapeEntry> kShapeEntries = [

  ShapeEntry(ShapeType.square, Icons.crop_square_rounded, 'Square'),
  ShapeEntry(ShapeType.circle, Icons.circle_outlined, 'Circle'),

  ShapeEntry(ShapeType.semiCircle, Icons.data_usage_rounded, 'Semi-circle'),
  ShapeEntry(ShapeType.triangle, Icons.change_history_rounded, 'Triangle'),
  ShapeEntry(ShapeType.rightTriangle, Icons.change_history_rounded, 'Right triangle'),
  ShapeEntry(ShapeType.diamond, Icons.diamond_outlined, 'Diamond'),
  ShapeEntry(ShapeType.pentagon, Icons.pentagon_outlined, 'Pentagon'),
  ShapeEntry(ShapeType.hexagon, Icons.hexagon_outlined, 'Hexagon'),

  ShapeEntry(ShapeType.arrow, Icons.arrow_forward_rounded, 'Arrow'),
  ShapeEntry(ShapeType.doubleArrow, Icons.compare_arrows_rounded, 'Double arrow'),
  ShapeEntry(ShapeType.door, Icons.door_front_door_outlined, 'Door'),
  ShapeEntry(ShapeType.doorDouble, Icons.sensor_door_outlined, 'Double door'),
  ShapeEntry(ShapeType.window, Icons.window_outlined, 'Window'),
  ShapeEntry(ShapeType.windowSliding, Icons.blinds_outlined, 'Sliding window'),
];

class FloatingToolbar extends StatefulWidget {
  final GlobalKey<InfiniteCanvasState> canvasKey;

  const FloatingToolbar({super.key, required this.canvasKey});

  @override
  State<FloatingToolbar> createState() => _FloatingToolbarState();
}

class _FloatingToolbarState extends State<FloatingToolbar> {
  bool _shapesOpen = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CanvasState>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_shapesOpen) _ShapeTray(state: state, canvasKey: widget.canvasKey),
        if (_shapesOpen) const SizedBox(height: 10),
        Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(22),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToolButton(
                  icon: Icons.near_me_outlined,
                  label: 'Select',
                  active: state.toolMode == ToolMode.select,
                  onTap: () {
                    setState(() => _shapesOpen = false);
                    // Toggle: selecting again turns it off, back to pan.
                    state.setTool(state.toolMode == ToolMode.select ? ToolMode.pan : ToolMode.select);
                  },
                ),
                _ToolButton(
                  icon: Icons.category_outlined,
                  label: 'Shapes',
                  active: _shapesOpen,
                  onTap: () => setState(() => _shapesOpen = !_shapesOpen),
                ),
                _ToolButton(
                  icon: Icons.show_chart_rounded,
                  label: 'Line',
                  active: state.toolMode == ToolMode.line,
                  onTap: () {
                    setState(() => _shapesOpen = false);
                    state.setTool(ToolMode.line);
                  },
                ),
                _ToolButton(
                  icon: Icons.gesture_rounded,
                  label: 'Freehand',
                  active: state.toolMode == ToolMode.curvedLine,
                  onTap: () {
                    setState(() => _shapesOpen = false);
                    state.setTool(ToolMode.curvedLine);
                  },
                ),
                _ToolButton(
                  icon: Icons.text_fields_rounded,
                  label: 'Text',
                  active: state.toolMode == ToolMode.text,
                  onTap: () {
                    setState(() => _shapesOpen = false);
                    state.setTool(ToolMode.text);
                  },
                ),
                _ToolButton(
                  icon: Icons.architecture_rounded,
                  label: 'Angle',
                  active: state.toolMode == ToolMode.angle,
                  onTap: () {
                    setState(() => _shapesOpen = false);
                    state.setTool(ToolMode.angle);
                  },
                ),
                _ToolButton(
                  icon: Icons.straighten_rounded,
                  label: 'Dimension',
                  active: state.toolMode == ToolMode.dimension,
                  onTap: () {
                    setState(() => _shapesOpen = false);
                    state.setTool(ToolMode.dimension);
                  },
                ),

                _ToolButton(
                  icon: Icons.auto_fix_normal_rounded,
                  label: 'Eraser',
                  active: state.toolMode == ToolMode.eraser,
                  onTap: () {
                    setState(() => _shapesOpen = false);
                    state.setTool(ToolMode.eraser);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ShapeTray extends StatelessWidget {
  final CanvasState state;
  final GlobalKey<InfiniteCanvasState> canvasKey;
  const _ShapeTray({required this.state, required this.canvasKey});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in kShapeEntries)
                _ShapeChip(
                  entry: entry,
                  active: state.toolMode == ToolMode.shape && state.activeShapeType == entry.type,
                  onTap: () {
                    state.setTool(ToolMode.shape, shapeType: entry.type);
                    canvasKey.currentState?.placeShapeAtViewportCenter(state, entry.type);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShapeChip extends StatelessWidget {
  final ShapeEntry entry;
  final bool active;
  final VoidCallback onTap;

  const _ShapeChip({required this.entry, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: entry.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active ? const Color(0xFFE8ECFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            entry.icon,
            size: 20,
            color: active ? const Color(0xFF4C6FFF) : const Color(0xFF4A4D5A),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToolButton({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Tooltip shows the tool name on long-press (mobile) or hover (desktop).
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: active ? const Color(0xFFE8ECFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 22,
            color: active ? const Color(0xFF4C6FFF) : const Color(0xFF1A1A2E),
          ),
        ),
      ),
    );
  }
}
