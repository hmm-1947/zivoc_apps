import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/canvas_state.dart';
import 'infinite_canvas.dart';

/// Floating pill of actions (duplicate, delete) shown above the current
/// single-shape selection, tracking it on screen as the canvas pans/zooms
/// and as the shape moves or resizes.
class SelectionActions extends StatelessWidget {
  final GlobalKey<InfiniteCanvasState> canvasKey;
  const SelectionActions({super.key, required this.canvasKey});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CanvasState>();
    final canvas = canvasKey.currentState;
    if (canvas == null || state.selectedShapeIds.length != 1) {
      return const SizedBox.shrink();
    }
    final pill = _ActionsPill(
      onDuplicate: () {
        final id = state.selectedShapeIds.first;
        state.duplicateShape(id);
      },
      onDelete: state.deleteSelected,
    );

    // An angle marker's bounds collapse to its vertex, which is under the
    // arc. Park the pill just beyond the arc instead, centred on that spot.
    final angleAnchor = canvas.angleActionAnchor(state);
    if (angleAnchor != null) {
      final anchorScreen = MatrixUtils.transformPoint(canvas.transform, angleAnchor);
      return Positioned(
        left: anchorScreen.dx,
        top: anchorScreen.dy,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: pill,
        ),
      );
    }

    final bounds = canvas.selectionBoundsFor(state);
    if (bounds == null) return const SizedBox.shrink();

    final topCenterScreen = MatrixUtils.transformPoint(canvas.transform, Offset(bounds.center.dx, bounds.top));
    const barHeight = 44.0;
    const gap = 12.0;

    return Positioned(
      left: topCenterScreen.dx,
      top: topCenterScreen.dy - barHeight - gap,
        child: FractionalTranslation(
          translation: const Offset(-0.5, 0),
          child: pill,
        ),
);
  }
}

class _ActionsPill extends StatelessWidget {
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  const _ActionsPill({required this.onDuplicate, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActionButton(icon: Icons.copy_rounded, onTap: onDuplicate),
            Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 2), color: const Color(0xFFE2E4EA)),
            _ActionButton(icon: Icons.delete_outline_rounded, onTap: onDelete),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 20, color: const Color(0xFF1A1A2E)),
      ),
    );
  }
}
